"""Operation dispatcher for github-file-edit."""

from __future__ import annotations

from file_edit_core import EditError
from file_edit_fs import apply_fs
from file_edit_text import apply_text


def _apply_one(op, root):
    name = op["op"]
    if not apply_text(name, op, root) and not apply_fs(name, op, root):
        raise EditError(f"Unsupported operation: {name!r}")


def _apply(operations, root):
    applied = []
    for index, op in enumerate(operations, 1):
        try:
            _apply_one(op, root)
        except EditError:
            raise
        except OSError as exc:
            raise EditError(
                f"Operation {index} ({op['op']}) failed: {exc}"
            ) from exc
        applied.append(
            {
                "index": index,
                "op": op["op"],
                "path": op.get("path"),
                "source": op.get("source"),
            }
        )
    return applied
