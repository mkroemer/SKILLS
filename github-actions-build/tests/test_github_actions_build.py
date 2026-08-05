import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[1] / "scripts" / "github_actions_build.py"
SPEC = importlib.util.spec_from_file_location("github_actions_build", MODULE)
assert SPEC and SPEC.loader
build = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build)


class BuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.policy = {
            "schema_version": 1,
            "enabled": True,
            "workflow_path": ".github/workflows/agent-compile.yml",
            "workflow_name": "Agent compile",
            "daily_budget_minutes": 10,
            "monthly_budget_minutes": 30,
            "max_run_minutes": 8,
            "max_runs_per_request": 2,
            "command_timeout_seconds": 360,
            "runner": "ubuntu-latest",
            "allow_parallel_jobs": False,
            "allow_automatic_retry": False,
            "allow_artifacts": False,
            "profiles": {
                "rust-check-package": {
                    "language": "rust",
                    "package_required": True,
                    "summary": "check"
                },
                "rust-test-package": {
                    "language": "rust",
                    "package_required": True,
                    "summary": "test"
                },
                "rust-build-package": {
                    "language": "rust",
                    "package_required": True,
                    "summary": "build"
                }
            }
        }

    def tearDown(self):
        self.temp.cleanup()

    def write(self, name, value):
        path = self.base / name
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def history(self, runs=None, complete=True):
        return {
            "schema_version": 1,
            "workflow_path": ".github/workflows/agent-compile.yml",
            "complete": complete,
            "runs": runs or [],
        }

    def test_policy_validation(self):
        normalized = build.validate_policy(self.policy)
        self.assertEqual(8, normalized["max_run_minutes"])
        bad = dict(self.policy)
        bad["allow_parallel_jobs"] = True
        with self.assertRaises(build.BuildPolicyError):
            build.validate_policy(bad)

    def test_budget_rounds_each_job_up(self):
        history = self.history([
            {
                "id": 1,
                "inputs": {},
                "jobs": [
                    {
                        "id": 10,
                        "status": "completed",
                        "conclusion": "success",
                        "started_at": "2026-08-05T10:00:00Z",
                        "completed_at": "2026-08-05T10:00:01Z",
                    },
                    {
                        "id": 11,
                        "status": "completed",
                        "conclusion": "success",
                        "started_at": "2026-08-05T10:00:00Z",
                        "completed_at": "2026-08-05T10:01:01Z",
                    },
                ],
            }
        ])
        now = build._now("2026-08-05T12:00:00Z")
        result = build.calculate_budget(self.policy, history, now=now)
        self.assertEqual(3, result["daily"]["used_minutes"])
        self.assertEqual(3, result["monthly"]["used_minutes"])
        self.assertFalse(result["allowed"])
        self.assertIn("daily_budget_below_run_reservation", result["reasons"])


    def test_budget_counts_overlap_across_utc_midnight(self):
        history = self.history([
            {
                "id": 1,
                "inputs": {},
                "jobs": [
                    {
                        "id": 10,
                        "status": "completed",
                        "conclusion": "success",
                        "started_at": "2026-08-04T23:59:30Z",
                        "completed_at": "2026-08-05T00:00:30Z",
                    }
                ],
            }
        ])
        result = build.calculate_budget(
            self.policy, history, now=build._now("2026-08-05T12:00:00Z")
        )
        self.assertEqual(1, result["daily"]["used_minutes"])
        self.assertEqual(1, result["monthly"]["used_minutes"])

    def test_budget_query_succeeds_while_policy_disabled(self):
        policy = dict(self.policy)
        policy["enabled"] = False
        policy_path = self.write("disabled-policy.json", policy)
        history_path = self.write("empty-history.json", self.history())
        result = build.command_budget(
            type(
                "Args",
                (),
                {
                    "policy": str(policy_path),
                    "history": str(history_path),
                    "now": "2026-08-05T12:00:00Z",
                },
            )()
        )
        self.assertTrue(result["ok"])
        self.assertFalse(result["budget"]["allowed"])
        self.assertIn("policy_disabled", result["budget"]["reasons"])

    def test_active_job_blocks_dispatch_and_reserves_runtime(self):
        history = self.history([
            {
                "id": 1,
                "inputs": {},
                "jobs": [
                    {
                        "id": 10,
                        "status": "in_progress",
                        "conclusion": None,
                        "started_at": "2026-08-05T11:58:20Z",
                        "completed_at": None,
                    }
                ],
            }
        ])
        result = build.calculate_budget(self.policy, history, now=build._now("2026-08-05T12:00:00Z"))
        self.assertEqual(2, result["daily"]["used_minutes"])
        self.assertEqual(1, result["active_jobs"])
        self.assertIn("agent_build_already_active", result["reasons"])

    def test_prepare_rejects_disabled_policy_and_unsafe_package(self):
        args = type(
            "Args",
            (),
            {
                "target_sha": "a" * 40,
                "profile": "rust-check-package",
                "package": "bad;command",
                "request_id": None,
            },
        )()
        with self.assertRaises(build.BuildPolicyError):
            build.prepare_request(self.policy, args)
        disabled = dict(self.policy)
        disabled["enabled"] = False
        args.package = "safe-package"
        with self.assertRaises(build.BuildPolicyError):
            build.prepare_request(disabled, args)

    def test_preflight_reuses_success_without_new_budget(self):
        policy_path = self.write("policy.json", self.policy)
        args = type(
            "Args",
            (),
            {
                "target_sha": "a" * 40,
                "profile": "rust-check-package",
                "package": "safe-package",
                "request_id": "request-1",
            },
        )()
        request = build.prepare_request(self.policy, args)
        request_path = self.write("request.json", request)
        history = self.history([
            {
                "id": 42,
                "html_url": "https://example/run/42",
                "inputs": {
                    "request_id": "older-request",
                    "target_sha": "a" * 40,
                    "profile": "rust-check-package",
                    "package": "safe-package",
                },
                "jobs": [
                    {
                        "id": 10,
                        "status": "completed",
                        "conclusion": "success",
                        "started_at": "2026-07-01T10:00:00Z",
                        "completed_at": "2026-07-01T10:02:00Z",
                    }
                ],
            }
        ])
        history_path = self.write("history.json", history)
        preflight_args = type(
            "Args",
            (),
            {
                "policy": str(policy_path),
                "history": str(history_path),
                "request": str(request_path),
                "now": "2026-08-05T12:00:00Z",
            },
        )()
        result = build.command_preflight(preflight_args)
        self.assertEqual("reuse", result["action"])
        self.assertEqual(42, result["matching_success"]["run_id"])

    def test_incomplete_history_blocks_dispatch(self):
        result = build.calculate_budget(
            self.policy,
            self.history(complete=False),
            now=build._now("2026-08-05T12:00:00Z"),
        )
        self.assertIn("history_incomplete", result["reasons"])

    def test_render_workflow_resolves_placeholders(self):
        policy_path = self.write("policy.json", self.policy)
        template = Path(__file__).resolve().parents[1] / "templates" / "agent-compile.yml"
        output = self.base / "agent-compile.yml"
        args = type(
            "Args",
            (),
            {"policy": str(policy_path), "template": str(template), "output": str(output)},
        )()
        result = build.command_render_workflow(args)
        text = output.read_text()
        self.assertNotIn("__MAX_RUN_MINUTES__", text)
        self.assertIn("timeout-minutes: 8", text)
        self.assertTrue(result["ok"])


if __name__ == "__main__":
    unittest.main()
