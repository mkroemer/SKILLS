"""Workflow-history accounting for the agent build budget."""

from actions_build_core import *

def _parse_time(value: Any, name: str) -> Optional[datetime]:
    if value is None:
        return None
    if not isinstance(value, str) or not value:
        raise BuildPolicyError(f"{name} must be an ISO-8601 string or null")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise BuildPolicyError(f"Invalid timestamp for {name}: {value}") from exc
    if parsed.tzinfo is None:
        raise BuildPolicyError(f"Timestamp for {name} must include a timezone")
    return parsed.astimezone(timezone.utc)


def _now(value: Optional[str]) -> datetime:
    if value is None:
        return datetime.now(timezone.utc)
    parsed = _parse_time(value, "now")
    assert parsed is not None
    return parsed


def _job_minutes(
    job: dict[str, Any], now: datetime
) -> tuple[int, bool, Optional[datetime], Optional[datetime]]:
    conclusion = job.get("conclusion")
    status = job.get("status")
    if conclusion == "skipped":
        return 0, False, None, None
    started = _parse_time(job.get("started_at"), "job.started_at")
    completed = _parse_time(job.get("completed_at"), "job.completed_at")
    active = status in ("queued", "in_progress", "waiting", "pending", "requested")
    if started is None:
        if active:
            return 0, True, None, None
        raise BuildPolicyError(f"Completed job {job.get('id')} has no started_at")
    end = now if completed is None else completed
    if end < started:
        raise BuildPolicyError(f"Job {job.get('id')} completed before it started")
    seconds = max(1.0, (end - started).total_seconds())
    return math.ceil(seconds / 60.0), active or completed is None, started, end


def _period_minutes(start: Optional[datetime], end: Optional[datetime], period_start: datetime, period_end: datetime) -> int:
    if start is None or end is None:
        return 0
    overlap_start = max(start, period_start)
    overlap_end = min(end, period_end)
    if overlap_end <= overlap_start:
        return 0
    return math.ceil((overlap_end - overlap_start).total_seconds() / 60.0)


def _run_success(run: dict[str, Any]) -> bool:
    jobs = run.get("jobs")
    if not isinstance(jobs, list) or not jobs:
        return False
    relevant = [job for job in jobs if job.get("conclusion") != "skipped"]
    return bool(relevant) and all(job.get("conclusion") == "success" for job in relevant)


def calculate_budget(policy: dict[str, Any], history: Any, *, now: datetime) -> dict[str, Any]:
    policy = validate_policy(policy)
    if not isinstance(history, dict) or history.get("schema_version") != SCHEMA_VERSION:
        raise BuildPolicyError("Unsupported workflow history schema")
    if history.get("workflow_path") != policy["workflow_path"]:
        raise BuildPolicyError("History workflow_path does not match policy")
    complete = history.get("complete", True)
    if not isinstance(complete, bool):
        raise BuildPolicyError("history.complete must be boolean")
    runs = history.get("runs")
    if not isinstance(runs, list):
        raise BuildPolicyError("history.runs must be an array")
    day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    day_end = day_start + timedelta(days=1)
    month_start = day_start.replace(day=1)
    if month_start.month == 12:
        month_end = month_start.replace(year=month_start.year + 1, month=1)
    else:
        month_end = month_start.replace(month=month_start.month + 1)
    daily_used = 0
    monthly_used = 0
    total_used = 0
    active_jobs = 0
    run_usage: list[dict[str, Any]] = []
    for run in runs:
        if not isinstance(run, dict):
            raise BuildPolicyError("History runs must be objects")
        jobs = run.get("jobs")
        if not isinstance(jobs, list):
            raise BuildPolicyError(f"Run {run.get('id')} has no jobs array")
        run_minutes = 0
        run_active = 0
        first_start: Optional[datetime] = None
        for job in jobs:
            if not isinstance(job, dict):
                raise BuildPolicyError("History jobs must be objects")
            minutes, active, started, ended = _job_minutes(job, now)
            if started is not None and (first_start is None or started < first_start):
                first_start = started
            run_minutes += minutes
            daily_used += _period_minutes(started, ended, day_start, day_end)
            monthly_used += _period_minutes(started, ended, month_start, month_end)
            run_active += int(active)
        total_used += run_minutes
        active_jobs += run_active
        run_usage.append(
            {
                "run_id": run.get("id"),
                "minutes": run_minutes,
                "active_jobs": run_active,
                "successful": _run_success(run),
                "inputs": run.get("inputs", {}),
            }
        )
    daily_remaining = max(0, policy["daily_budget_minutes"] - daily_used)
    monthly_remaining = max(0, policy["monthly_budget_minutes"] - monthly_used)
    reservation = policy["max_run_minutes"]
    reasons: list[str] = []
    if not policy["enabled"]:
        reasons.append("policy_disabled")
    if not complete:
        reasons.append("history_incomplete")
    if active_jobs:
        reasons.append("agent_build_already_active")
    if daily_remaining < reservation:
        reasons.append("daily_budget_below_run_reservation")
    if monthly_remaining < reservation:
        reasons.append("monthly_budget_below_run_reservation")
    return {
        "schema_version": SCHEMA_VERSION,
        "workflow_path": policy["workflow_path"],
        "now": now.isoformat(),
        "enabled": policy["enabled"],
        "history_complete": complete,
        "daily": {
            "limit_minutes": policy["daily_budget_minutes"],
            "used_minutes": daily_used,
            "remaining_minutes": daily_remaining,
        },
        "monthly": {
            "limit_minutes": policy["monthly_budget_minutes"],
            "used_minutes": monthly_used,
            "remaining_minutes": monthly_remaining,
        },
        "total_history_minutes": total_used,
        "active_jobs": active_jobs,
        "next_run_reservation_minutes": reservation,
        "allowed": not reasons,
        "reasons": reasons,
        "runs": run_usage,
    }

__all__ = [name for name in globals() if not name.startswith("__")]
