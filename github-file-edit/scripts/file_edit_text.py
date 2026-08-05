"""Text-oriented operations for github-file-edit."""

from __future__ import annotations

import hashlib
import re

from file_edit_core import (
    EditError, _enc, _expected, _i, _read, _s, _safe_path, _write,
)


TEXT_OPS = {
    "assert_text", "assert_sha256", "replace_text", "delete_text",
    "replace_regex", "insert_text", "replace_lines", "append_text",
    "prepend_text",
}


def _counted(op, root, regex=False, delete=False):
    path = _safe_path(root, _s(op, "path"))
    encoding = _enc(op)
    text, expected = _read(path, encoding), _expected(op)
    if regex:
        flags = 0
        allowed = {
            name: getattr(re, name)
            for name in ("ASCII", "DOTALL", "IGNORECASE", "MULTILINE", "VERBOSE")
        }
        try:
            for name in op.get("flags", []):
                flags |= allowed[name]
            result, count = re.subn(
                _s(op, "pattern"),
                _s(op, "replacement", True),
                text,
                flags=flags,
            )
        except (KeyError, TypeError, re.error) as exc:
            raise EditError(f"Invalid regex or flag: {exc}") from exc
    else:
        old = _s(op, "old")
        count = text.count(old)
        replacement = "" if delete else _s(op, "new", True)
        result = text.replace(old, replacement)
    if count != expected:
        raise EditError(
            f"{path}: expected {expected} match(es), found {count}"
        )
    _write(path, result, encoding, False)


def apply_text(name, op, root):
    if name not in TEXT_OPS:
        return False
    path = _safe_path(root, _s(op, "path"))

    if name in ("replace_text", "delete_text"):
        _counted(op, root, delete=name == "delete_text")
    elif name == "replace_regex":
        _counted(op, root, regex=True)
    elif name == "assert_text":
        count = _read(path, _enc(op)).count(_s(op, "text"))
        if count != _expected(op):
            raise EditError(f"{path}: assertion found {count} match(es)")
    elif name == "assert_sha256":
        expected = _s(op, "sha256").lower()
        if not path.is_file() or not re.fullmatch(r"[0-9a-f]{64}", expected):
            raise EditError("Invalid SHA-256 assertion")
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise EditError(f"{path}: SHA-256 mismatch")
    elif name == "insert_text":
        encoding = _enc(op)
        anchor, added = _s(op, "anchor"), _s(op, "content", True)
        position, text = op.get("position", "after"), _read(path, encoding)
        if position not in ("before", "after"):
            raise EditError("'position' must be before or after")
        count = text.count(anchor)
        if count != _expected(op):
            raise EditError(
                f"{path}: expected {_expected(op)} anchor(s), found {count}"
            )
        replacement = (
            added + anchor if position == "before" else anchor + added
        )
        _write(path, text.replace(anchor, replacement), encoding, False)
    elif name == "replace_lines":
        encoding = _enc(op)
        start, end = _i(op, "start", 0), _i(op, "end", 0)
        lines = _read(path, encoding).splitlines(keepends=True)
        if start < 1 or end < start or end > len(lines):
            raise EditError(f"{path}: invalid line range {start}-{end}")
        result = (
            "".join(lines[:start - 1])
            + _s(op, "content", True)
            + "".join(lines[end:])
        )
        _write(path, result, encoding, False)
    elif name in ("append_text", "prepend_text"):
        encoding = _enc(op)
        old, added = _read(path, encoding), _s(op, "content", True)
        result = added + old if name == "prepend_text" else old + added
        _write(path, result, encoding, False)
    return True
