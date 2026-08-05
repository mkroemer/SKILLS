#!/usr/bin/env python3
"""Managed connector-backed repository workspaces."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from workspace_core import *
from workspace_state import *
from workspace_refresh import *
from workspace_archive import *

def _add_common_root(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--root", required=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Manage connector-backed GitHub workspaces")
    parser.add_argument("--json", action="store_true", help="Emit JSON output")
    sub = parser.add_subparsers(dest="command", required=True)

    materialize = sub.add_parser("materialize", help="Create a workspace from a connector manifest")
    _add_common_root(materialize)
    materialize.add_argument("--manifest", required=True)
    materialize.set_defaults(handler=command_materialize)

    status = sub.add_parser("status", help="Compare working files with the recorded baseline")
    _add_common_root(status)
    status.set_defaults(handler=command_status)

    manifest = sub.add_parser("manifest", help="Create a publication manifest")
    _add_common_root(manifest)
    manifest.add_argument("--output")
    manifest.set_defaults(handler=command_manifest)

    reset = sub.add_parser("reset", help="Restore tracked files from the local object store")
    _add_common_root(reset)
    reset.add_argument("--path", action="append")
    reset.add_argument("--remove-untracked", action="store_true")
    reset.add_argument("--yes", action="store_true")
    reset.set_defaults(handler=command_reset)

    refresh = sub.add_parser("refresh", help="Three-way refresh from connector-fetched content")
    _add_common_root(refresh)
    refresh.add_argument("--manifest", required=True)
    refresh.add_argument("--apply", action="store_true")
    refresh.set_defaults(handler=command_refresh)

    archive = sub.add_parser("archive", help="Create a portable workspace archive")
    _add_common_root(archive)
    archive.add_argument("--output", required=True)
    archive.add_argument("--max-bytes", type=int, default=250 * 1024 * 1024)
    archive.add_argument("--include-build-output", action="store_true")
    archive.set_defaults(handler=command_archive)

    restore = sub.add_parser("restore", help="Restore a portable workspace archive")
    restore.add_argument("--archive", required=True)
    _add_common_root(restore)
    restore.add_argument("--max-bytes", type=int, default=250 * 1024 * 1024)
    restore.set_defaults(handler=command_restore)

    verify = sub.add_parser("verify", help="Verify baseline object-store integrity")
    _add_common_root(verify)
    verify.set_defaults(handler=command_verify)

    clean = sub.add_parser("clean", help="Delete a managed workspace")
    _add_common_root(clean)
    clean.add_argument("--yes", action="store_true")
    clean.add_argument("--discard-changes", action="store_true")
    clean.set_defaults(handler=command_clean)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        result = args.handler(args)
        if args.json:
            print(json.dumps(result, indent=2, sort_keys=True))
        else:
            print(json.dumps(result, indent=2, sort_keys=True))
        return 0 if result.get("ok", True) else 3
    except WorkspaceError as exc:
        payload = {"ok": False, "error": str(exc)}
        if args.json:
            print(json.dumps(payload, indent=2, sort_keys=True))
        else:
            print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
