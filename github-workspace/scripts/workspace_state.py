"""Materialization, status, manifests, and reset operations."""

from workspace_core import *

def _walk_working_files(root: Path) -> Iterable[str]:
    for current_root, dirs, files in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_root)
        rel_dir = current.relative_to(root)
        dirs[:] = [name for name in dirs if not (rel_dir == Path(".") and name == STATE_DIR)]
        for name in files:
            path = current / name
            yield path.relative_to(root).as_posix()
        for name in dirs:
            path = current / name
            if path.is_symlink():
                yield path.relative_to(root).as_posix()


def _status(root: Path, state: dict[str, Any]) -> dict[str, Any]:
    tracked = state["files"]
    changes: list[dict[str, Any]] = []
    for path, metadata in sorted(tracked.items()):
        current = _read_working(root, path)
        if current is None:
            changes.append({"path": path, "status": "deleted", "baseline": metadata})
            continue
        mode, data = current
        if mode == "other":
            changes.append({"path": path, "status": "type_changed", "baseline": metadata})
            continue
        digest = _sha256(data)
        if digest != metadata["sha256"] or mode != metadata["mode"]:
            changes.append(
                {
                    "path": path,
                    "status": "modified",
                    "mode": mode,
                    "sha256": digest,
                    "size": len(data),
                    "baseline": metadata,
                }
            )
    for path in sorted(set(_walk_working_files(root)) - set(tracked)):
        mode, data = _read_working(root, path) or ("other", b"")
        changes.append(
            {
                "path": path,
                "status": "untracked" if mode != "other" else "type_changed",
                "mode": mode,
                "sha256": _sha256(data) if mode != "other" else None,
                "size": len(data) if mode != "other" else None,
            }
        )
    return {
        "schema_version": SCHEMA_VERSION,
        "repository": state["repository"],
        "ref": state["ref"],
        "baseline_commit_sha": state["commit_sha"],
        "checkout": state["checkout"],
        "clean": not changes,
        "changes": changes,
    }


def command_materialize(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).expanduser().resolve()
    manifest_path = Path(args.manifest).expanduser().resolve()
    manifest = _json_load(manifest_path)
    if not isinstance(manifest, dict) or manifest.get("schema_version") != SCHEMA_VERSION:
        raise WorkspaceError("Unsupported materialization manifest")
    repository = manifest.get("repository")
    if not isinstance(repository, str) or not REPOSITORY_RE.fullmatch(repository):
        raise WorkspaceError("Manifest repository must use owner/name form")
    ref = manifest.get("ref")
    commit_sha = manifest.get("commit_sha")
    tree_sha = manifest.get("tree_sha")
    checkout = manifest.get("checkout", "sparse")
    if not isinstance(ref, str) or not ref:
        raise WorkspaceError("Manifest ref is required")
    if not isinstance(commit_sha, str) or not SHA_RE.fullmatch(commit_sha):
        raise WorkspaceError("Manifest commit_sha is invalid")
    if tree_sha is not None and (not isinstance(tree_sha, str) or not SHA_RE.fullmatch(tree_sha)):
        raise WorkspaceError("Manifest tree_sha is invalid")
    if checkout not in ("sparse", "complete"):
        raise WorkspaceError("checkout must be sparse or complete")
    files = manifest.get("files")
    if not isinstance(files, list):
        raise WorkspaceError("Manifest files must be an array")
    if root.exists() and any(root.iterdir()):
        raise WorkspaceError(f"Workspace root must be empty: {root}")
    root.mkdir(parents=True, exist_ok=True)
    state_files: dict[str, Any] = {}
    seen: set[str] = set()
    try:
        for entry in files:
            path, mode, blob_sha = _validate_file_entry(entry)
            if path in seen:
                raise WorkspaceError(f"Duplicate manifest path: {path}")
            seen.add(path)
            data = _entry_bytes(entry, manifest_path.parent)
            digest = _store_object(root, data)
            _write_working_entry(root, path, data, mode)
            state_files[path] = {
                "blob_sha": blob_sha,
                "mode": mode,
                "sha256": digest,
                "size": len(data),
            }
        state = {
            "schema_version": SCHEMA_VERSION,
            "repository": repository,
            "ref": ref,
            "commit_sha": commit_sha.lower(),
            "tree_sha": tree_sha.lower() if isinstance(tree_sha, str) else None,
            "checkout": checkout,
            "created_at": _utc_now(),
            "updated_at": _utc_now(),
            "files": state_files,
        }
        _save_state(root, state)
    except Exception:
        if root.exists():
            shutil.rmtree(root)
        raise
    return {"ok": True, "root": str(root), "files": len(state_files), "state": state}


def command_status(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).expanduser().resolve()
    return _status(root, _load_state(root))


def command_manifest(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).expanduser().resolve()
    state = _load_state(root)
    status = _status(root, state)
    files: list[dict[str, Any]] = []
    deleted: list[str] = []
    for change in status["changes"]:
        path = change["path"]
        if change["status"] == "deleted":
            deleted.append(path)
            continue
        if change["status"] == "type_changed":
            raise WorkspaceError(f"Cannot publish unsupported path type: {path}")
        mode, data = _read_working(root, path) or ("other", b"")
        entry = {
            "path": path,
            "status": change["status"],
            "mode": mode,
            "sha256": _sha256(data),
            "size": len(data),
        }
        if mode == "120000":
            entry["content_base64"] = base64.b64encode(data).decode("ascii")
        else:
            entry["source"] = str(_workspace_path(root, path))
        files.append(entry)
    result = {
        "schema_version": SCHEMA_VERSION,
        "repository": state["repository"],
        "ref": state["ref"],
        "baseline_commit_sha": state["commit_sha"],
        "baseline_tree_sha": state.get("tree_sha"),
        "files": files,
        "deleted": deleted,
    }
    if args.output:
        _atomic_json(Path(args.output).expanduser().resolve(), result)
    return result


def command_reset(args: argparse.Namespace) -> dict[str, Any]:
    if not args.yes:
        raise WorkspaceError("reset requires --yes")
    root = Path(args.root).expanduser().resolve()
    state = _load_state(root)
    requested = args.path or sorted(state["files"])
    restored: list[str] = []
    removed: list[str] = []
    for path in requested:
        _validate_relative(path)
        metadata = state["files"].get(path)
        target = _workspace_path(root, path)
        if metadata is None:
            if not args.remove_untracked:
                raise WorkspaceError(f"Path is not tracked: {path}")
            if target.is_dir() and not target.is_symlink():
                raise WorkspaceError(f"Refusing to remove untracked directory: {path}")
            if target.exists() or target.is_symlink():
                target.unlink()
                removed.append(path)
            continue
        object_path = _object_path(root, metadata["sha256"])
        if not object_path.is_file() or _sha256(object_path.read_bytes()) != metadata["sha256"]:
            raise WorkspaceError(f"Missing or corrupt baseline object for {path}")
        _write_working_entry(root, path, object_path.read_bytes(), metadata["mode"])
        restored.append(path)
    return {"ok": True, "restored": restored, "removed": removed}

__all__ = [name for name in globals() if not name.startswith("__")]
