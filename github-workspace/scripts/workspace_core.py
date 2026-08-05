#!/usr/bin/env python3
"""Managed connector-backed repository workspaces.

The helper performs local filesystem and state operations only. GitHub reads and
writes remain the responsibility of the agent's GitHub connector.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import os
import re
import shutil
import stat
import sys
import tarfile
import tempfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any, Iterable, Optional

STATE_DIR = ".github-workspace"
STATE_FILE = "state.json"
OBJECT_DIR = "objects"
SCHEMA_VERSION = 1
REPOSITORY_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
SHA_RE = re.compile(r"^[0-9a-fA-F]{40,64}$")
MODES = {"100644", "100755", "120000"}
DEFAULT_ARCHIVE_EXCLUDES = {
    ".git",
    ".hg",
    ".svn",
    "__pycache__",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
    ".venv",
    "node_modules",
    "target",
}


class WorkspaceError(RuntimeError):
    """Raised when workspace safety or consistency checks fail."""


def _utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _json_load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise WorkspaceError(f"Cannot read JSON {path}: {exc}") from exc


def _atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8")
    _atomic_bytes(path, data)


def _atomic_bytes(path: Path, data: bytes, mode: Optional[int] = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and not path.is_file():
        raise WorkspaceError(f"Cannot replace non-file path: {path}")
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temp = Path(temp_name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        if mode is not None:
            os.chmod(temp, mode)
        os.replace(temp, path)
    finally:
        if temp.exists():
            temp.unlink()


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _validate_relative(value: str) -> PurePosixPath:
    if not isinstance(value, str) or not value or "\\" in value:
        raise WorkspaceError(f"Unsafe repository path: {value!r}")
    pure = PurePosixPath(value)
    if pure.is_absolute() or any(part in ("", ".", "..") for part in pure.parts):
        raise WorkspaceError(f"Unsafe repository path: {value!r}")
    if pure.parts[0] == STATE_DIR:
        raise WorkspaceError(f"Reserved workspace path: {value!r}")
    return pure


def _workspace_path(root: Path, value: str, *, allow_final_symlink: bool = True) -> Path:
    pure = _validate_relative(value)
    current = root
    for part in pure.parts[:-1]:
        current /= part
        if current.exists() and current.is_symlink():
            raise WorkspaceError(f"Symlink traversal is not allowed: {value!r}")
    result = current / pure.parts[-1]
    if result.exists() and result.is_symlink() and not allow_final_symlink:
        raise WorkspaceError(f"Symlink target is not allowed: {value!r}")
    return result


def _state_path(root: Path) -> Path:
    return root / STATE_DIR / STATE_FILE


def _object_path(root: Path, digest: str) -> Path:
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise WorkspaceError(f"Invalid object digest: {digest!r}")
    return root / STATE_DIR / OBJECT_DIR / digest[:2] / digest[2:]


def _load_state(root: Path) -> dict[str, Any]:
    state = _json_load(_state_path(root))
    if not isinstance(state, dict) or state.get("schema_version") != SCHEMA_VERSION:
        raise WorkspaceError("Unsupported or missing workspace state")
    if not isinstance(state.get("files"), dict):
        raise WorkspaceError("Workspace state has no valid files map")
    return state


def _save_state(root: Path, state: dict[str, Any]) -> None:
    state["updated_at"] = _utc_now()
    _atomic_json(_state_path(root), state)


def _entry_bytes(entry: dict[str, Any], manifest_dir: Path) -> bytes:
    choices = [key for key in ("source", "content_base64") if key in entry]
    if len(choices) != 1:
        raise WorkspaceError("Each manifest file needs exactly one of source or content_base64")
    if "source" in entry:
        source_value = entry["source"]
        if not isinstance(source_value, str) or not source_value:
            raise WorkspaceError("Manifest source must be a non-empty path")
        source = Path(source_value).expanduser()
        if not source.is_absolute():
            source = manifest_dir / source
        if source.is_symlink():
            raise WorkspaceError(f"Manifest source must not be a symlink: {source}")
        source = source.resolve(strict=True)
        if not source.is_file():
            raise WorkspaceError(f"Manifest source is not a regular file: {source}")
        return source.read_bytes()
    try:
        return base64.b64decode(entry["content_base64"], validate=True)
    except (TypeError, ValueError, binascii.Error) as exc:
        raise WorkspaceError("Invalid content_base64 in manifest") from exc


def _validate_file_entry(entry: Any) -> tuple[str, str, Optional[str]]:
    if not isinstance(entry, dict):
        raise WorkspaceError("Manifest file entries must be objects")
    path = entry.get("path")
    _validate_relative(path)
    mode = entry.get("mode", "100644")
    if mode not in MODES:
        raise WorkspaceError(f"Unsupported Git mode for {path}: {mode!r}")
    blob_sha = entry.get("blob_sha")
    if blob_sha is not None and (not isinstance(blob_sha, str) or not SHA_RE.fullmatch(blob_sha)):
        raise WorkspaceError(f"Invalid blob SHA for {path}")
    return path, mode, blob_sha


def _store_object(root: Path, data: bytes) -> str:
    digest = _sha256(data)
    target = _object_path(root, digest)
    if target.exists():
        if target.read_bytes() != data:
            raise WorkspaceError(f"Object-store collision for {digest}")
    else:
        _atomic_bytes(target, data, 0o600)
    return digest


def _write_working_entry(root: Path, path: str, data: bytes, mode: str) -> None:
    target = _workspace_path(root, path)
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() or target.is_symlink():
        if target.is_dir() and not target.is_symlink():
            raise WorkspaceError(f"Cannot replace directory with file: {path}")
        target.unlink()
    if mode == "120000":
        try:
            link_target = data.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise WorkspaceError(f"Symlink target is not UTF-8: {path}") from exc
        target.symlink_to(link_target)
    else:
        _atomic_bytes(target, data, 0o755 if mode == "100755" else 0o644)


def _read_working(root: Path, path: str) -> Optional[tuple[str, bytes]]:
    target = _workspace_path(root, path)
    if target.is_symlink():
        return "120000", os.readlink(target).encode("utf-8")
    if target.is_file():
        mode = "100755" if stat.S_IMODE(target.stat().st_mode) & 0o111 else "100644"
        return mode, target.read_bytes()
    if target.exists():
        return "other", b""
    return None


def _baseline_equal(root: Path, path: str, metadata: dict[str, Any]) -> bool:
    current = _read_working(root, path)
    if current is None:
        return False
    mode, data = current
    return mode == metadata["mode"] and _sha256(data) == metadata["sha256"]

__all__ = [name for name in globals() if not name.startswith("__")]
