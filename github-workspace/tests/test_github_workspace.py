import base64
import importlib.util
import json
import os
import tempfile
import tarfile
import io
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[1] / "scripts" / "github_workspace.py"
SPEC = importlib.util.spec_from_file_location("github_workspace", MODULE)
assert SPEC and SPEC.loader
workspace = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(workspace)


class WorkspaceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.root = self.base / "workspace"

    def tearDown(self):
        self.temp.cleanup()

    def manifest(self, files, **extra):
        value = {
            "schema_version": 1,
            "repository": "owner/repo",
            "ref": "dev",
            "commit_sha": "a" * 40,
            "tree_sha": "b" * 40,
            "checkout": "sparse",
            "files": files,
        }
        value.update(extra)
        path = self.base / f"manifest-{len(list(self.base.glob('manifest-*')))}.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def materialize(self):
        manifest = self.manifest([
            {
                "path": "src/lib.rs",
                "blob_sha": "1" * 40,
                "mode": "100644",
                "content_base64": base64.b64encode(b"pub fn value() -> i32 { 1 }\n").decode(),
            },
            {
                "path": "run.sh",
                "blob_sha": "2" * 40,
                "mode": "100755",
                "content_base64": base64.b64encode(b"#!/bin/sh\necho ok\n").decode(),
            },
        ])
        return workspace.command_materialize(
            type("Args", (), {"root": str(self.root), "manifest": str(manifest)})()
        )

    def test_materialize_status_manifest_and_reset(self):
        result = self.materialize()
        self.assertEqual(2, result["files"])
        self.assertTrue(workspace.command_status(type("Args", (), {"root": str(self.root)})())["clean"])

        lib = self.root / "src/lib.rs"
        lib.write_text("pub fn value() -> i32 { 2 }\n", encoding="utf-8")
        (self.root / "new.txt").write_text("new\n", encoding="utf-8")
        status = workspace.command_status(type("Args", (), {"root": str(self.root)})())
        self.assertEqual({"modified", "untracked"}, {item["status"] for item in status["changes"]})

        publish = workspace.command_manifest(
            type("Args", (), {"root": str(self.root), "output": None})()
        )
        self.assertEqual(2, len(publish["files"]))
        self.assertEqual([], publish["deleted"])

        workspace.command_reset(
            type(
                "Args",
                (),
                {
                    "root": str(self.root),
                    "path": ["src/lib.rs", "new.txt"],
                    "remove_untracked": True,
                    "yes": True,
                },
            )()
        )
        self.assertIn("{ 1 }", lib.read_text())
        self.assertFalse((self.root / "new.txt").exists())

    def test_refresh_updates_unchanged_file(self):
        self.materialize()
        refresh = self.manifest(
            [
                {
                    "path": "src/lib.rs",
                    "blob_sha": "3" * 40,
                    "mode": "100644",
                    "content_base64": base64.b64encode(b"pub fn value() -> i32 { 3 }\n").decode(),
                }
            ],
            commit_sha="c" * 40,
            tree_sha="d" * 40,
            deleted=[],
        )
        args = type("Args", (), {"root": str(self.root), "manifest": str(refresh), "apply": True})()
        result = workspace.command_refresh(args)
        self.assertTrue(result["ok"])
        self.assertIn("{ 3 }", (self.root / "src/lib.rs").read_text())
        state = workspace._load_state(self.root)
        self.assertEqual("c" * 40, state["commit_sha"])

    def test_refresh_conflict_is_non_destructive(self):
        self.materialize()
        local = self.root / "src/lib.rs"
        local.write_text("local\n", encoding="utf-8")
        refresh = self.manifest(
            [
                {
                    "path": "src/lib.rs",
                    "blob_sha": "3" * 40,
                    "mode": "100644",
                    "content_base64": base64.b64encode(b"remote\n").decode(),
                }
            ],
            commit_sha="c" * 40,
            deleted=[],
        )
        args = type("Args", (), {"root": str(self.root), "manifest": str(refresh), "apply": False})()
        result = workspace.command_refresh(args)
        self.assertFalse(result["ok"])
        self.assertEqual("local\n", local.read_text())
        args.apply = True
        with self.assertRaises(workspace.WorkspaceError):
            workspace.command_refresh(args)
        self.assertEqual("local\n", local.read_text())

    def test_archive_and_restore(self):
        self.materialize()
        archive = self.base / "workspace.tar.gz"
        workspace.command_archive(
            type(
                "Args",
                (),
                {
                    "root": str(self.root),
                    "output": str(archive),
                    "max_bytes": 10_000_000,
                    "include_build_output": False,
                },
            )()
        )
        restored = self.base / "restored"
        result = workspace.command_restore(
            type(
                "Args",
                (),
                {"archive": str(archive), "root": str(restored), "max_bytes": 10_000_000},
            )()
        )
        self.assertTrue(result["ok"])
        self.assertEqual((self.root / "src/lib.rs").read_bytes(), (restored / "src/lib.rs").read_bytes())
        self.assertTrue(workspace.command_verify(type("Args", (), {"root": str(restored)})())["ok"])


    def test_restore_rejects_symlink_parent_traversal(self):
        archive_path = self.base / "malicious.tar.gz"
        with tarfile.open(archive_path, "w:gz") as archive:
            link = tarfile.TarInfo("workspace/link")
            link.type = tarfile.SYMTYPE
            link.linkname = "../../outside"
            archive.addfile(link)
            data = b"pwned"
            file_info = tarfile.TarInfo("workspace/link/pwn.txt")
            file_info.size = len(data)
            archive.addfile(file_info, io.BytesIO(data))
        with self.assertRaises(workspace.WorkspaceError):
            workspace.command_restore(
                type(
                    "Args",
                    (),
                    {
                        "archive": str(archive_path),
                        "root": str(self.root),
                        "max_bytes": 10_000_000,
                    },
                )()
            )
        self.assertFalse(self.root.exists())

    @unittest.skipIf(os.name == "nt", "symlink semantics")
    def test_symlink_is_preserved_and_not_followed(self):
        manifest = self.manifest([
            {
                "path": "link",
                "blob_sha": "4" * 40,
                "mode": "120000",
                "content_base64": base64.b64encode(b"../../outside").decode(),
            }
        ])
        workspace.command_materialize(type("Args", (), {"root": str(self.root), "manifest": str(manifest)})())
        self.assertTrue((self.root / "link").is_symlink())
        status = workspace.command_status(type("Args", (), {"root": str(self.root)})())
        self.assertTrue(status["clean"])

    def test_path_traversal_is_rejected(self):
        for value in ("../file", "/absolute", r"src\file", ".github-workspace/state.json"):
            with self.assertRaises(workspace.WorkspaceError):
                workspace._validate_relative(value)

    def test_clean_requires_managed_workspace_and_confirmation(self):
        self.materialize()
        args = type("Args", (), {"root": str(self.root), "yes": False, "discard_changes": False})()
        with self.assertRaises(workspace.WorkspaceError):
            workspace.command_clean(args)
        (self.root / "src/lib.rs").write_text("dirty\n", encoding="utf-8")
        args.yes = True
        with self.assertRaises(workspace.WorkspaceError):
            workspace.command_clean(args)
        args.discard_changes = True
        workspace.command_clean(args)
        self.assertFalse(self.root.exists())


if __name__ == "__main__":
    unittest.main()
