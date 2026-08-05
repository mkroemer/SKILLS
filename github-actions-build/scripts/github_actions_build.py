#!/usr/bin/env python3
"""Guarded GitHub Actions build requests and budget accounting."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from actions_build_core import *
from actions_build_budget import *
from actions_build_request import *

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Prepare and budget connector-run GitHub Actions builds")
    parser.add_argument("--json", action="store_true")
    sub = parser.add_subparsers(dest="command", required=True)

    validate = sub.add_parser("validate-policy")
    validate.add_argument("--policy", required=True)
    validate.set_defaults(handler=command_validate_policy)

    prepare = sub.add_parser("prepare")
    prepare.add_argument("--policy", required=True)
    prepare.add_argument("--target-sha", required=True)
    prepare.add_argument("--profile", required=True)
    prepare.add_argument("--package", required=True)
    prepare.add_argument("--request-id")
    prepare.add_argument("--output")
    prepare.set_defaults(handler=command_prepare)

    budget = sub.add_parser("budget")
    budget.add_argument("--policy", required=True)
    budget.add_argument("--history", required=True)
    budget.add_argument("--now")
    budget.set_defaults(handler=command_budget)

    preflight = sub.add_parser("preflight")
    preflight.add_argument("--policy", required=True)
    preflight.add_argument("--history", required=True)
    preflight.add_argument("--request", required=True)
    preflight.add_argument("--now")
    preflight.set_defaults(handler=command_preflight)

    render = sub.add_parser("render-workflow")
    render.add_argument("--policy", required=True)
    render.add_argument("--template", required=True)
    render.add_argument("--output", required=True)
    render.set_defaults(handler=command_render_workflow)

    remove = sub.add_parser("removal-plan")
    remove.add_argument("--policy", required=True)
    remove.set_defaults(handler=command_removal_plan)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        result = args.handler(args)
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0 if result.get("ok", True) else 3
    except BuildPolicyError as exc:
        payload = {"ok": False, "error": str(exc)}
        if args.json:
            print(json.dumps(payload, indent=2, sort_keys=True))
        else:
            print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
