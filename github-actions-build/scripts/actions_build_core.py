#!/usr/bin/env python3
"""Local policy, request, and budget tooling for connector-run GitHub Actions builds."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path, PurePosixPath
from typing import Any, Optional

SCHEMA_VERSION = 1
SHA_RE = re.compile(r"^[0-9a-fA-F]{40}$")
PACKAGE_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
PROFILE_RE = re.compile(r"^[a-z0-9][a-z0-9-]{1,62}$")
REQUEST_RE = re.compile(r"^[A-Za-z0-9_.-]{1,80}$")


class BuildPolicyError(RuntimeError):
    """Raised when build policy, history, or request data is unsafe or invalid."""


def _load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BuildPolicyError(f"Cannot read JSON {path}: {exc}") from exc


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _canonical_hash(value: Any) -> str:
    data = json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def _positive_int(value: Any, name: str, *, minimum: int = 1) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < minimum:
        raise BuildPolicyError(f"{name} must be an integer >= {minimum}")
    return value


def _validate_workflow_path(value: Any) -> str:
    if not isinstance(value, str) or not value:
        raise BuildPolicyError("workflow_path is required")
    pure = PurePosixPath(value)
    if pure.is_absolute() or any(part in ("", ".", "..") for part in pure.parts):
        raise BuildPolicyError("workflow_path must be a safe repository-relative path")
    if len(pure.parts) != 3 or pure.parts[:2] != (".github", "workflows"):
        raise BuildPolicyError("workflow_path must be below .github/workflows")
    if pure.suffix not in (".yml", ".yaml"):
        raise BuildPolicyError("workflow_path must be a YAML workflow file")
    return pure.as_posix()


def validate_policy(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict) or value.get("schema_version") != SCHEMA_VERSION:
        raise BuildPolicyError("Unsupported build policy schema")
    enabled = value.get("enabled")
    if not isinstance(enabled, bool):
        raise BuildPolicyError("enabled must be boolean")
    workflow_path = _validate_workflow_path(value.get("workflow_path"))
    workflow_name = value.get("workflow_name")
    if not isinstance(workflow_name, str) or not workflow_name.strip():
        raise BuildPolicyError("workflow_name is required")
    daily = _positive_int(value.get("daily_budget_minutes"), "daily_budget_minutes")
    monthly = _positive_int(value.get("monthly_budget_minutes"), "monthly_budget_minutes")
    max_run = _positive_int(value.get("max_run_minutes"), "max_run_minutes")
    max_runs = _positive_int(value.get("max_runs_per_request"), "max_runs_per_request")
    command_timeout = _positive_int(value.get("command_timeout_seconds"), "command_timeout_seconds", minimum=30)
    if max_run > daily or max_run > monthly:
        raise BuildPolicyError("max_run_minutes must not exceed daily or monthly budgets")
    if command_timeout > max_run * 60 - 30:
        raise BuildPolicyError("command_timeout_seconds must reserve at least 30 seconds for setup and cleanup")
    runner = value.get("runner")
    if runner != "ubuntu-latest":
        raise BuildPolicyError("Only ubuntu-latest is allowed by this skill version")
    if value.get("allow_parallel_jobs") is not False:
        raise BuildPolicyError("allow_parallel_jobs must be false")
    if value.get("allow_automatic_retry") is not False:
        raise BuildPolicyError("allow_automatic_retry must be false")
    if value.get("allow_artifacts") is not False:
        raise BuildPolicyError("allow_artifacts must be false in the default safety profile")
    profiles = value.get("profiles")
    if not isinstance(profiles, dict) or not profiles:
        raise BuildPolicyError("profiles must be a non-empty object")
    normalized_profiles: dict[str, dict[str, Any]] = {}
    for name, profile in profiles.items():
        if not isinstance(name, str) or not PROFILE_RE.fullmatch(name):
            raise BuildPolicyError(f"Invalid profile name: {name!r}")
        if not isinstance(profile, dict):
            raise BuildPolicyError(f"Profile {name} must be an object")
        language = profile.get("language")
        summary = profile.get("summary")
        package_required = profile.get("package_required")
        if language != "rust":
            raise BuildPolicyError(f"Profile {name} uses unsupported language {language!r}")
        if not isinstance(summary, str) or not summary:
            raise BuildPolicyError(f"Profile {name} needs a summary")
        if package_required is not True:
            raise BuildPolicyError(f"Profile {name} must require an explicit package")
        normalized_profiles[name] = {
            "language": language,
            "summary": summary,
            "package_required": True,
        }
    required_profiles = {"rust-check-package", "rust-test-package", "rust-build-package"}
    if set(normalized_profiles) != required_profiles:
        raise BuildPolicyError(
            "Default workflow requires exactly rust-check-package, rust-test-package, and rust-build-package"
        )
    normalized = dict(value)
    normalized.update(
        workflow_path=workflow_path,
        workflow_name=workflow_name.strip(),
        daily_budget_minutes=daily,
        monthly_budget_minutes=monthly,
        max_run_minutes=max_run,
        max_runs_per_request=max_runs,
        command_timeout_seconds=command_timeout,
        profiles=normalized_profiles,
    )
    return normalized

__all__ = [name for name in globals() if not name.startswith("__")]
