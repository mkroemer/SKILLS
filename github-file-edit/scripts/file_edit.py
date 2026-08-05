#!/usr/bin/env python3
"""Guarded local file edits for connector-backed GitHub workflows."""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from file_edit_core import (  # noqa: E402
    EditError,
    _changes,
    _copy_for_dry_run,
    _diff,
    _load_operations,
    _safe_path,
    _snapshot,
)
from file_edit_ops import _apply  # noqa: E402


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Apply guarded repository file operations"
    )
    sub = parser.add_subparsers(dest="command", required=True)
    cmd = sub.add_parser("apply")
    cmd.add_argument("--root", required=True)
    cmd.add_argument("--plan", required=True)
    cmd.add_argument("--dry-run", action="store_true")
    cmd.add_argument("--diff", action="store_true")
    cmd.add_argument("--json", action="store_true")
    cmd.add_argument("--manifest-out")
    args = parser.parse_args(argv)

    try:
        root = Path(args.root).expanduser().resolve()
        if not root.is_dir():
            raise EditError(f"Root is not a directory: {root}")
        plan = Path(args.plan).expanduser().resolve()
        operations = _load_operations(plan)
        before = _snapshot(root)

        if args.dry_run:
            with tempfile.TemporaryDirectory(prefix="file-edit-") as temp:
                shadow = Path(temp) / "workspace"
                _copy_for_dry_run(root, shadow)
                applied = _apply(operations, shadow)
                after = _snapshot(shadow)
        else:
            applied = _apply(operations, root)
            after = _snapshot(root)

        changes = _changes(before, after)
        diff = _diff(before, after, changes) if args.diff else ""
        payload = {
            "ok": True,
            "dry_run": args.dry_run,
            "root": str(root),
            "plan": str(plan),
            "operations": applied,
            "changes": changes,
        }
        if args.diff:
            payload["diff"] = diff
        if args.manifest_out:
            Path(args.manifest_out).write_text(
                json.dumps(payload, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
        if args.json:
            print(json.dumps(payload, indent=2, sort_keys=True))
        else:
            label = "Dry run" if args.dry_run else "Applied"
            print(
                f"{label}: {len(applied)} operation(s), "
                f"{len(changes)} changed path(s)"
            )
            for change in changes:
                print(f"- {change['status']}: {change['path']}")
            if diff:
                print(diff, end="" if diff.endswith("\n") else "\n")
        return 0
    except EditError as exc:
        if getattr(args, "json", False):
            print(json.dumps({"ok": False, "error": str(exc)}, indent=2))
        else:
            print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
