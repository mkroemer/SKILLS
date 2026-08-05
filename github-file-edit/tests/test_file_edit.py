import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[1] / "scripts" / "file_edit.py"
SPEC = importlib.util.spec_from_file_location("github_file_edit", MODULE)
assert SPEC and SPEC.loader
edit = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = edit
SPEC.loader.exec_module(edit)


class FileEditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "workspace"
        (self.root / "src").mkdir(parents=True)
        (self.root / "src/app.py").write_text(
            "VALUE = 1\n\ndef run():\n    return VALUE\n", encoding="utf-8"
        )

    def tearDown(self):
        self.temp.cleanup()

    def plan(self, operations):
        path = Path(self.temp.name) / "plan.json"
        path.write_text(json.dumps({"operations": operations}), encoding="utf-8")
        return path

    def apply(self, operations, root=None):
        edit._apply(edit._load_operations(self.plan(operations)), root or self.root)

    def test_replace_write_move_copy_and_delete(self):
        self.apply([
            {"op": "replace_text", "path": "src/app.py", "old": "VALUE = 1",
             "new": "VALUE = 2", "expected": 1},
            {"op": "write_text", "path": "src/new.py",
             "content": "NEW = True\n", "if_exists": "error"},
            {"op": "copy", "source": "src/new.py", "path": "src/copy.py"},
            {"op": "move", "source": "src/copy.py", "path": "src/moved.py"},
            {"op": "delete", "path": "src/new.py"},
        ])
        self.assertIn("VALUE = 2", (self.root / "src/app.py").read_text())
        self.assertFalse((self.root / "src/new.py").exists())
        self.assertEqual("NEW = True\n", (self.root / "src/moved.py").read_text())

    def test_dry_run_does_not_change_original(self):
        before = edit._snapshot(self.root)
        with tempfile.TemporaryDirectory() as temp:
            shadow = Path(temp) / "workspace"
            edit._copy_for_dry_run(self.root, shadow)
            self.apply([{"op": "replace_text", "path": "src/app.py",
                         "old": "VALUE = 1", "new": "VALUE = 3"}], shadow)
            after = edit._snapshot(shadow)
        self.assertIn("VALUE = 1", (self.root / "src/app.py").read_text())
        self.assertEqual([("src/app.py", "modified")],
                         [(x["path"], x["status"]) for x in edit._changes(before, after)])

    def test_expected_count_guard(self):
        with self.assertRaises(edit.EditError):
            self.apply([{"op": "replace_text", "path": "src/app.py",
                         "old": "VALUE", "new": "OTHER", "expected": 1}])
        self.assertIn("VALUE = 1", (self.root / "src/app.py").read_text())

    def test_path_traversal_rejected(self):
        for path in ("../outside.txt", "/absolute.txt", r"src\app.py"):
            with self.assertRaises(edit.EditError):
                edit._safe_path(self.root, path)

    def test_regex_and_line_replacement(self):
        self.apply([
            {"op": "replace_regex", "path": "src/app.py",
             "pattern": r"^VALUE = \d+$", "replacement": "VALUE = 4",
             "flags": ["MULTILINE"], "expected": 1},
            {"op": "replace_lines", "path": "src/app.py", "start": 3, "end": 4,
             "content": "def run():\n    return VALUE * 2\n"},
        ])
        self.assertEqual("VALUE = 4\n\ndef run():\n    return VALUE * 2\n",
                         (self.root / "src/app.py").read_text())

    @unittest.skipIf(os.name == "nt", "POSIX mode semantics")
    def test_chmod(self):
        self.apply([{"op": "chmod", "path": "src/app.py", "mode": "755"}])
        self.assertEqual(0o755, (self.root / "src/app.py").stat().st_mode & 0o777)


if __name__ == "__main__":
    unittest.main()
