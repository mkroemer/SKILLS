"""Conflict-aware workspace refresh operations."""

from workspace_core import *
from workspace_state import *

def _refresh_plan(root: Path, state: dict[str, Any], manifest: dict[str, Any], manifest_dir: Path) -> dict[str, Any]:
    if manifest.get("schema_version") != SCHEMA_VERSION:
        raise WorkspaceError("Unsupported refresh manifest")
    if manifest.get("repository") != state["repository"]:
        raise WorkspaceError("Refresh repository does not match workspace")
    commit_sha = manifest.get("commit_sha")
    tree_sha = manifest.get("tree_sha")
    if not isinstance(commit_sha, str) or not SHA_RE.fullmatch(commit_sha):
        raise WorkspaceError("Refresh commit_sha is invalid")
    if tree_sha is not None and (not isinstance(tree_sha, str) or not SHA_RE.fullmatch(tree_sha)):
        raise WorkspaceError("Refresh tree_sha is invalid")
    files = manifest.get("files", [])
    deleted = manifest.get("deleted", [])
    if not isinstance(files, list) or not isinstance(deleted, list):
        raise WorkspaceError("Refresh files and deleted must be arrays")
    actions: list[dict[str, Any]] = []
    conflicts: list[dict[str, Any]] = []
    seen: set[str] = set()
    for entry in files:
        path, mode, blob_sha = _validate_file_entry(entry)
        if path in seen:
            raise WorkspaceError(f"Duplicate refresh path: {path}")
        seen.add(path)
        data = _entry_bytes(entry, manifest_dir)
        digest = _sha256(data)
        baseline = state["files"].get(path)
        current = _read_working(root, path)
        if baseline is None:
            if current is None or (current[0] == mode and _sha256(current[1]) == digest):
                actions.append({"action": "add", "path": path, "mode": mode, "blob_sha": blob_sha, "data": data})
            else:
                conflicts.append({"path": path, "reason": "local_untracked_and_remote_added"})
            continue
        local_changed = not _baseline_equal(root, path, baseline)
        remote_changed = (
            baseline.get("blob_sha") != blob_sha
            or baseline["mode"] != mode
            or baseline["sha256"] != digest
        )
        if local_changed and remote_changed:
            conflicts.append({"path": path, "reason": "local_and_remote_modified"})
        elif not local_changed and remote_changed:
            actions.append({"action": "update", "path": path, "mode": mode, "blob_sha": blob_sha, "data": data})
        elif not remote_changed:
            actions.append({
                "action": "keep_local" if local_changed else "unchanged",
                "path": path,
            })
    for raw_path in deleted:
        path = str(raw_path)
        _validate_relative(path)
        if path in seen:
            raise WorkspaceError(f"Path is both refreshed and deleted: {path}")
        seen.add(path)
        baseline = state["files"].get(path)
        current = _read_working(root, path)
        if baseline is None:
            if current is not None:
                conflicts.append({"path": path, "reason": "local_untracked_but_remote_deleted"})
            continue
        if _baseline_equal(root, path, baseline):
            actions.append({"action": "delete", "path": path})
        else:
            conflicts.append({"path": path, "reason": "local_modified_but_remote_deleted"})
    return {
        "commit_sha": commit_sha.lower(),
        "tree_sha": tree_sha.lower() if isinstance(tree_sha, str) else None,
        "ref": manifest.get("ref", state["ref"]),
        "actions": actions,
        "conflicts": conflicts,
    }


def command_refresh(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).expanduser().resolve()
    state = _load_state(root)
    manifest_path = Path(args.manifest).expanduser().resolve()
    manifest = _json_load(manifest_path)
    if not isinstance(manifest, dict):
        raise WorkspaceError("Refresh manifest must be an object")
    plan = _refresh_plan(root, state, manifest, manifest_path.parent)
    public_actions = [{key: value for key, value in item.items() if key != "data"} for item in plan["actions"]]
    result = {
        "ok": not plan["conflicts"],
        "apply": bool(args.apply),
        "actions": public_actions,
        "conflicts": plan["conflicts"],
        "target_commit_sha": plan["commit_sha"],
    }
    if plan["conflicts"]:
        if args.apply:
            raise WorkspaceError("Refresh has conflicts; no changes were applied")
        return result
    if not args.apply:
        return result
    for item in plan["actions"]:
        action, path = item["action"], item["path"]
        if action in ("add", "update"):
            data = item["data"]
            digest = _store_object(root, data)
            _write_working_entry(root, path, data, item["mode"])
            state["files"][path] = {
                "blob_sha": item["blob_sha"],
                "mode": item["mode"],
                "sha256": digest,
                "size": len(data),
            }
        elif action == "delete":
            target = _workspace_path(root, path)
            if target.exists() or target.is_symlink():
                if target.is_dir() and not target.is_symlink():
                    raise WorkspaceError(f"Refusing to delete directory during refresh: {path}")
                target.unlink()
            state["files"].pop(path, None)
    state["commit_sha"] = plan["commit_sha"]
    state["tree_sha"] = plan["tree_sha"]
    state["ref"] = plan["ref"]
    _save_state(root, state)
    result["ok"] = True
    return result

__all__ = [name for name in globals() if not name.startswith("__")]
