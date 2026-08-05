"""Shared safety, plan, snapshot, and diff helpers for github-file-edit."""

from __future__ import annotations

import difflib
import hashlib
import json
import os
import shutil
import stat
import tempfile
from pathlib import Path, PurePosixPath


class EditError(RuntimeError):
    pass


OPS = {
    "assert_text", "assert_sha256", "replace_text", "delete_text",
    "replace_regex", "insert_text", "replace_lines", "append_text",
    "prepend_text", "write_text", "write_base64", "mkdir", "copy",
    "move", "delete", "chmod",
}


def _s(op, key, empty=False):
    value = op.get(key)
    if not isinstance(value, str) or (not empty and not value):
        raise EditError(f"{key!r} must be a string")
    return value


def _b(op, key, default):
    value = op.get(key, default)
    if not isinstance(value, bool):
        raise EditError(f"{key!r} must be boolean")
    return value


def _i(op, key, default):
    value = op.get(key, default)
    if not isinstance(value, int) or isinstance(value, bool):
        raise EditError(f"{key!r} must be an integer")
    return value


def _enc(op):
    return _s(op, "encoding") if "encoding" in op else "utf-8"


def _expected(op):
    value = _i(op, "expected", 1)
    if value < 0:
        raise EditError("'expected' must be non-negative")
    return value


def _safe_path(root, value):
    if not isinstance(value, str) or not value or "\\" in value:
        raise EditError(f"Unsafe repository path: {value!r}")
    pure = PurePosixPath(value)
    if pure.is_absolute() or any(p in ("", ".", "..") for p in pure.parts):
        raise EditError(f"Unsafe repository path: {value!r}")
    path = root
    for part in pure.parts:
        path /= part
        if path.exists() and path.is_symlink():
            raise EditError(f"Symlink traversal is not allowed: {value!r}")
    path = path.resolve(strict=False)
    try:
        path.relative_to(root)
    except ValueError as exc:
        raise EditError(f"Path escapes workspace: {value!r}") from exc
    return path


def _read(path, encoding="utf-8"):
    if not path.is_file():
        raise EditError(f"Expected file: {path}")
    try:
        with path.open("r", encoding=encoding, newline="") as handle:
            return handle.read()
    except UnicodeError as exc:
        raise EditError(f"Cannot decode {path} as {encoding}") from exc


def _write_bytes(path, data, parents=True):
    if parents:
        path.parent.mkdir(parents=True, exist_ok=True)
    elif not path.parent.exists():
        raise EditError(f"Missing parent: {path.parent}")
    if path.exists() and not path.is_file():
        raise EditError(f"Cannot replace non-file: {path}")
    mode = stat.S_IMODE(path.stat().st_mode) if path.is_file() else None
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temp = Path(name)
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


def _write(path, text, encoding="utf-8", parents=True):
    try:
        _write_bytes(path, text.encode(encoding), parents)
    except UnicodeError as exc:
        raise EditError(f"Cannot encode {path} as {encoding}") from exc


def _remove(path, recursive=False):
    if path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path) if recursive else path.rmdir()
    else:
        raise EditError(f"Unsupported path: {path}")


def _load_operations(path):
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise EditError(f"Cannot read plan: {exc}") from exc
    raw = (
        document if isinstance(document, list)
        else document.get("operations") if isinstance(document, dict)
        else None
    )
    if not isinstance(raw, list) or not raw:
        raise EditError("Plan must contain a non-empty operations array")
    for index, op in enumerate(raw, 1):
        if not isinstance(op, dict) or op.get("op") not in OPS:
            raise EditError(f"Operation {index} is invalid")
    return raw


def _snapshot(root):
    result = {}
    ignored = {".git", ".hg", ".svn", "__pycache__"}
    for path in sorted(root.rglob("*")):
        if any(part in ignored for part in path.parts):
            continue
        rel = path.relative_to(root).as_posix()
        if path.is_symlink():
            result[rel] = ("symlink", os.readlink(path).encode(), None)
        elif path.is_file():
            result[rel] = (
                "file", path.read_bytes(), stat.S_IMODE(path.stat().st_mode)
            )
        elif path.is_dir():
            result[rel] = ("dir", None, stat.S_IMODE(path.stat().st_mode))
    return result


def _changes(before, after):
    result = []
    for path in sorted(set(before) | set(after)):
        old, new = before.get(path), after.get(path)
        if old == new:
            continue
        status = (
            "created" if old is None
            else "deleted" if new is None
            else "modified"
        )
        item = {"path": path, "status": status}
        if old and old[0] == "file":
            item.update(
                old_sha256=hashlib.sha256(old[1]).hexdigest(),
                old_size=len(old[1]),
            )
        if new and new[0] == "file":
            item.update(
                new_sha256=hashlib.sha256(new[1]).hexdigest(),
                new_size=len(new[1]),
            )
        result.append(item)
    return result


def _diff(before, after, changes):
    output = []
    for change in changes:
        path = change["path"]
        old, new = before.get(path), after.get(path)
        if (old and old[0] != "file") or (new and new[0] != "file"):
            output.append(f"# {change['status']}: {path}\n")
            continue
        try:
            a = [] if old is None else old[1].decode().splitlines(keepends=True)
            b = [] if new is None else new[1].decode().splitlines(keepends=True)
        except UnicodeDecodeError:
            output.append(f"# {change['status']}: {path} (binary)\n")
            continue
        output.extend(
            difflib.unified_diff(a, b, fromfile=f"a/{path}", tofile=f"b/{path}")
        )
    return "".join(output)


def _copy_for_dry_run(source, target):
    shutil.copytree(
        source,
        target,
        symlinks=True,
        ignore=shutil.ignore_patterns(".git", ".hg", ".svn", "__pycache__"),
    )
