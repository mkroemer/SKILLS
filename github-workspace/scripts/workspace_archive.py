"""Workspace archive, restore, integrity, and cleanup operations."""

from workspace_core import *
from workspace_state import *

def _archive_members(root: Path, include_build_output: bool) -> list[Path]:
    paths: list[Path] = []
    for current_root, dirs, files in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_root)
        dirs[:] = [
            name
            for name in dirs
            if include_build_output or name not in DEFAULT_ARCHIVE_EXCLUDES
        ]
        for name in files:
            paths.append(current / name)
        for name in dirs:
            path = current / name
            if path.is_symlink():
                paths.append(path)
    return paths


def command_archive(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).expanduser().resolve()
    _load_state(root)
    output = Path(args.output).expanduser().resolve()
    try:
        output.relative_to(root)
    except ValueError:
        pass
    else:
        raise WorkspaceError("Archive output must be outside the workspace root")
    members = _archive_members(root, args.include_build_output)
    total = sum(path.lstat().st_size for path in members if path.exists() or path.is_symlink())
    if total > args.max_bytes:
        raise WorkspaceError(f"Archive input size {total} exceeds max {args.max_bytes}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(output, "w:gz", dereference=False) as archive:
        for path in members:
            archive.add(path, arcname=(Path("workspace") / path.relative_to(root)).as_posix(), recursive=False)
    return {"ok": True, "output": str(output), "files": len(members), "input_bytes": total}


def _safe_archive_member(member: tarfile.TarInfo) -> PurePosixPath:
    pure = PurePosixPath(member.name)
    if pure.is_absolute() or not pure.parts or pure.parts[0] != "workspace":
        raise WorkspaceError(f"Unsafe archive member: {member.name}")
    rel = PurePosixPath(*pure.parts[1:])
    if not rel.parts or any(part in ("", ".", "..") for part in rel.parts):
        raise WorkspaceError(f"Unsafe archive member: {member.name}")
    return rel


def _restore_target(root: Path, rel: PurePosixPath) -> Path:
    current = root
    for part in rel.parts[:-1]:
        current /= part
        if current.is_symlink():
            raise WorkspaceError(f"Archive member traverses a symlink: {rel.as_posix()}")
    return current / rel.parts[-1]


def command_restore(args: argparse.Namespace) -> dict[str, Any]:
    archive_path = Path(args.archive).expanduser().resolve()
    root = Path(args.root).expanduser().resolve()
    if root.exists() and any(root.iterdir()):
        raise WorkspaceError(f"Restore root must be empty: {root}")
    root.mkdir(parents=True, exist_ok=True)
    try:
        with tarfile.open(archive_path, "r:gz") as archive:
            members = archive.getmembers()
            total = sum(member.size for member in members if member.isfile())
            if total > args.max_bytes:
                raise WorkspaceError(f"Archive expands to {total} bytes, above max {args.max_bytes}")
            seen: set[str] = set()
            for member in members:
                rel = _safe_archive_member(member)
                rel_text = rel.as_posix()
                if rel_text in seen:
                    raise WorkspaceError(f"Duplicate archive member: {rel_text}")
                seen.add(rel_text)
                target = _restore_target(root, rel)
                target.parent.mkdir(parents=True, exist_ok=True)
                if member.isdir():
                    target.mkdir(exist_ok=True)
                elif member.isfile():
                    source = archive.extractfile(member)
                    if source is None:
                        raise WorkspaceError(f"Cannot read archive member: {member.name}")
                    _atomic_bytes(target, source.read(), member.mode & 0o777)
                elif member.issym():
                    if target.exists() or target.is_symlink():
                        target.unlink()
                    target.symlink_to(member.linkname)
                else:
                    raise WorkspaceError(f"Unsupported archive member type: {member.name}")
        state = _load_state(root)
        command_verify(argparse.Namespace(root=str(root)))
    except Exception:
        if root.exists():
            shutil.rmtree(root)
        raise
    return {"ok": True, "root": str(root), "repository": state["repository"]}


def command_verify(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).expanduser().resolve()
    state = _load_state(root)
    missing: list[str] = []
    corrupt: list[str] = []
    for path, metadata in state["files"].items():
        object_path = _object_path(root, metadata["sha256"])
        if not object_path.is_file():
            missing.append(path)
        elif _sha256(object_path.read_bytes()) != metadata["sha256"]:
            corrupt.append(path)
    return {"ok": not missing and not corrupt, "missing_objects": missing, "corrupt_objects": corrupt}


def command_clean(args: argparse.Namespace) -> dict[str, Any]:
    if not args.yes:
        raise WorkspaceError("clean requires --yes")
    root = Path(args.root).expanduser().resolve()
    state = _load_state(root)
    status = _status(root, state)
    if not status["clean"] and not args.discard_changes:
        raise WorkspaceError("Workspace has local changes; use --discard-changes to remove it")
    shutil.rmtree(root)
    return {"ok": True, "removed": str(root), "repository": state["repository"]}

__all__ = [name for name in globals() if not name.startswith("__")]
