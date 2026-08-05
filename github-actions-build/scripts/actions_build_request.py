"""Build request, preflight, workflow rendering, and removal plans."""

from actions_build_core import *
from actions_build_budget import *

def prepare_request(policy: dict[str, Any], args: argparse.Namespace) -> dict[str, Any]:
    policy = validate_policy(policy)
    if not policy["enabled"]:
        raise BuildPolicyError("Build policy is disabled")
    target_sha = args.target_sha.lower()
    if not SHA_RE.fullmatch(target_sha):
        raise BuildPolicyError("target_sha must be a full 40-character commit SHA")
    if args.profile not in policy["profiles"]:
        raise BuildPolicyError(f"Unknown build profile: {args.profile}")
    if not PACKAGE_RE.fullmatch(args.package):
        raise BuildPolicyError("package contains unsafe characters")
    request_id = args.request_id or f"agent-build-{uuid.uuid4().hex[:16]}"
    if not REQUEST_RE.fullmatch(request_id):
        raise BuildPolicyError("request_id contains unsafe characters or is too long")
    return {
        "schema_version": SCHEMA_VERSION,
        "request_id": request_id,
        "target_sha": target_sha,
        "profile": args.profile,
        "package": args.package,
        "workflow_path": policy["workflow_path"],
        "dispatch_inputs": {
            "request_id": request_id,
            "target_sha": target_sha,
            "profile": args.profile,
            "package": args.package,
        },
        "budget_reservation_minutes": policy["max_run_minutes"],
        "policy_sha256": _canonical_hash(policy),
        "summary": policy["profiles"][args.profile]["summary"],
    }


def _matching_success(history: dict[str, Any], request: dict[str, Any]) -> Optional[dict[str, Any]]:
    for run in history.get("runs", []):
        inputs = run.get("inputs", {})
        if (
            inputs.get("target_sha", "").lower() == request["target_sha"]
            and inputs.get("profile") == request["profile"]
            and inputs.get("package") == request["package"]
            and _run_success(run)
        ):
            return {"run_id": run.get("id"), "html_url": run.get("html_url")}
    return None


def command_validate_policy(args: argparse.Namespace) -> dict[str, Any]:
    policy = validate_policy(_load_json(Path(args.policy).expanduser().resolve()))
    return {"ok": True, "policy_sha256": _canonical_hash(policy), "policy": policy}


def command_prepare(args: argparse.Namespace) -> dict[str, Any]:
    policy = validate_policy(_load_json(Path(args.policy).expanduser().resolve()))
    request = prepare_request(policy, args)
    if args.output:
        _write_json(Path(args.output).expanduser().resolve(), request)
    return {"ok": True, "request": request}


def command_budget(args: argparse.Namespace) -> dict[str, Any]:
    policy = validate_policy(_load_json(Path(args.policy).expanduser().resolve()))
    history = _load_json(Path(args.history).expanduser().resolve())
    result = calculate_budget(policy, history, now=_now(args.now))
    return {"ok": True, "budget": result}


def command_preflight(args: argparse.Namespace) -> dict[str, Any]:
    policy = validate_policy(_load_json(Path(args.policy).expanduser().resolve()))
    history = _load_json(Path(args.history).expanduser().resolve())
    request = _load_json(Path(args.request).expanduser().resolve())
    if not isinstance(request, dict) or request.get("schema_version") != SCHEMA_VERSION:
        raise BuildPolicyError("Unsupported build request schema")
    if request.get("policy_sha256") != _canonical_hash(policy):
        raise BuildPolicyError("Build request was prepared with a different policy")
    if request.get("workflow_path") != policy["workflow_path"]:
        raise BuildPolicyError("Build request workflow does not match policy")
    match = _matching_success(history, request)
    budget = calculate_budget(policy, history, now=_now(args.now))
    same_request_runs = sum(
        1
        for run in history.get("runs", [])
        if run.get("inputs", {}).get("request_id") == request.get("request_id")
    )
    reasons = list(budget["reasons"])
    if same_request_runs >= policy["max_runs_per_request"]:
        reasons.append("request_run_limit_reached")
    if match:
        return {
            "ok": True,
            "action": "reuse",
            "matching_success": match,
            "budget": budget,
            "request": request,
        }
    return {
        "ok": not reasons,
        "action": "dispatch" if not reasons else "deny",
        "reasons": reasons,
        "budget": budget,
        "request": request,
    }


def command_render_workflow(args: argparse.Namespace) -> dict[str, Any]:
    policy = validate_policy(_load_json(Path(args.policy).expanduser().resolve()))
    template_path = Path(args.template).expanduser().resolve()
    try:
        text = template_path.read_text(encoding="utf-8")
    except OSError as exc:
        raise BuildPolicyError(f"Cannot read workflow template: {exc}") from exc
    replacements = {
        "__MAX_RUN_MINUTES__": str(policy["max_run_minutes"]),
        "__COMMAND_TIMEOUT_SECONDS__": str(policy["command_timeout_seconds"]),
    }
    for marker, replacement in replacements.items():
        if text.count(marker) != 1:
            raise BuildPolicyError(f"Workflow template must contain exactly one {marker}")
        text = text.replace(marker, replacement)
    if "__" in text:
        raise BuildPolicyError("Workflow template contains unresolved placeholders")
    output = Path(args.output).expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")
    return {
        "ok": True,
        "output": str(output),
        "workflow_path": policy["workflow_path"],
        "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
    }


def command_removal_plan(args: argparse.Namespace) -> dict[str, Any]:
    policy = validate_policy(_load_json(Path(args.policy).expanduser().resolve()))
    return {
        "ok": True,
        "cancel_active_runs_first": True,
        "disable_workflow_first": True,
        "delete_paths": [
            policy["workflow_path"],
            ".github/agent-build-policy.json",
            ".agents/skills/github-actions-build",
        ],
        "note": "Historical workflow runs remain unless separately deleted and are needed for budget accounting.",
    }

__all__ = [name for name in globals() if not name.startswith("__")]
