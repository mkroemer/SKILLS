"""Filesystem-oriented operations for github-file-edit."""

from __future__ import annotations

import base64
import binascii
import os
import re
import shutil

from file_edit_core import (
    EditError, _b, _enc, _remove, _s, _safe_path, _write, _write_bytes,
)


FS_OPS = {
    "write_text", "write_base64", "mkdir", "copy", "move", "delete", "chmod"
}


def _transfer(op, root, move=False):
    source = _safe_path(root, _s(op, "source"))
    target = _safe_path(root, _s(op, "path"))
    if not source.exists() or source == target:
        raise EditError(f"Invalid source: {source}")
    if source.is_dir():
        try:
            target.relative_to(source)
        except ValueError:
            pass
        else:
            raise EditError("Destination cannot be inside source directory")
    if target.exists():
        if not _b(op, "overwrite", False):
            raise EditError(f"Destination exists: {target}")
        _remove(target, True)
    if _b(op, "parents", True):
        target.parent.mkdir(parents=True, exist_ok=True)
    elif not target.parent.exists():
        raise EditError(f"Missing parent: {target.parent}")
    if move:
        shutil.move(str(source), str(target))
    elif source.is_dir():
        shutil.copytree(source, target)
    elif source.is_file():
        shutil.copy2(source, target)
    else:
        raise EditError(f"Unsupported source: {source}")


def apply_fs(name, op, root):
    if name not in FS_OPS:
        return False
    path = _safe_path(root, _s(op, "path"))

    if name in ("write_text", "write_base64"):
        policy = op.get("if_exists", "replace")
        if policy not in ("replace", "error", "skip"):
            raise EditError("'if_exists' must be replace, error, or skip")
        if path.exists() and policy == "error":
            raise EditError(f"Destination exists: {path}")
        if path.exists() and policy == "skip":
            return True
        if name == "write_text":
            _write(
                path,
                _s(op, "content", True),
                _enc(op),
                _b(op, "parents", True),
            )
        else:
            try:
                data = base64.b64decode(
                    _s(op, "content_base64", True), validate=True
                )
            except (ValueError, binascii.Error) as exc:
                raise EditError("Invalid base64 content") from exc
            _write_bytes(path, data, _b(op, "parents", True))
    elif name == "mkdir":
        path.mkdir(
            parents=_b(op, "parents", True),
            exist_ok=_b(op, "exist_ok", True),
        )
    elif name in ("copy", "move"):
        _transfer(op, root, name == "move")
    elif name == "delete":
        if not path.exists():
            if _b(op, "missing_ok", False):
                return True
            raise EditError(f"Delete target missing: {path}")
        _remove(path, _b(op, "recursive", False))
    elif name == "chmod":
        mode = _s(op, "mode")
        if not path.exists() or not re.fullmatch(r"[0-7]{3,4}", mode):
            raise EditError(f"Invalid chmod target or mode: {path}, {mode!r}")
        os.chmod(path, int(mode, 8))
    return True
