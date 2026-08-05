# GitHub Actions Build

`github-actions-build` provides a guarded way to compile an exact repository commit through a dedicated manual GitHub Actions workflow when the local agent runtime lacks the required compiler.

The default implementation supports focused Rust package validation and maintains its own daily and monthly execution budget from that workflow's job history.

## What it provides

- reviewed Rust build profiles rather than arbitrary commands;
- exact commit and package validation;
- daily and monthly skill-specific minute budgets;
- conservative per-job minute rounding;
- active-job and incomplete-history blocking;
- successful-run reuse;
- no automatic retries;
- one runner, no matrix, strict timeouts;
- disabled-by-policy installation;
- explicit workflow disablement and complete removal plan.

It does not query account-wide GitHub billing and does not call GitHub from Python.

## Requirements

- Python 3.9 or later;
- a GitHub repository with Actions enabled;
- a connector capable of reading workflow runs and jobs;
- connector Actions write capabilities for execution;
- write access to install the optional workflow and policy on the default branch.

No third-party Python packages are required.

## Installation

Install the skill project-locally or globally:

```bash
mkdir -p .agents/skills
cp -R /path/to/SKILLS/github-actions-build .agents/skills/github-actions-build
```

Installing the skill does not install or enable a repository workflow.

For a consuming repository, copy and review:

```text
github-actions-build/examples/policy.json
  -> .github/agent-build-policy.json

github-actions-build/templates/agent-compile.yml
  -> rendered .github/workflows/agent-compile.yml
```

Render the configured hard limits:

```bash
python3 .agents/skills/github-actions-build/scripts/github_actions_build.py --json render-workflow \
  --policy .github/agent-build-policy.json \
  --template .agents/skills/github-actions-build/templates/agent-compile.yml \
  --output .github/workflows/agent-compile.yml
```

The workflow must be merged to the default branch before manual dispatch is available. Keep the policy disabled until explicit activation.

## Validate policy

```bash
python3 .agents/skills/github-actions-build/scripts/github_actions_build.py --json validate-policy \
  --policy .github/agent-build-policy.json
```

The included validator intentionally accepts only:

- one `ubuntu-latest` runner;
- no parallel jobs;
- no automatic retry;
- no artifacts;
- the three included Rust package profiles.

## Ask for remaining budget

Use the connector to retrieve runs and jobs only for `.github/workflows/agent-compile.yml`. Normalize them using [`examples/history.json`](examples/history.json), then run:

```bash
python3 .agents/skills/github-actions-build/scripts/github_actions_build.py --json budget \
  --policy .github/agent-build-policy.json \
  --history /absolute/path/to/history.json
```

The result reports daily and monthly limits, used minutes, remaining minutes, active jobs, history completeness, and the reservation required for another run.

Each non-skipped job or its overlap with the current UTC accounting period is rounded upward to a full minute. Running jobs count through the current time. Deleted or unavailable history must be marked incomplete and blocks dispatch.

## Prepare and preflight

Enable the policy only through an explicit reviewed or user-approved change. Prepare a request:

```bash
python3 .agents/skills/github-actions-build/scripts/github_actions_build.py --json prepare \
  --policy .github/agent-build-policy.json \
  --target-sha 0123456789abcdef0123456789abcdef01234567 \
  --profile rust-check-package \
  --package gear-math \
  --output /absolute/path/to/request.json
```

Refresh history and run preflight:

```bash
python3 .agents/skills/github-actions-build/scripts/github_actions_build.py --json preflight \
  --policy .github/agent-build-policy.json \
  --history /absolute/path/to/history.json \
  --request /absolute/path/to/request.json
```

The result is `reuse`, `dispatch`, or `deny`. Only `dispatch` permits a new run.

## Workflow behavior

The included workflow:

- runs only through `workflow_dispatch`;
- has `contents: read` permissions;
- checks out the exact supplied commit;
- pins `actions/checkout` to the commit for v6.0.2;
- validates the Cargo package through `cargo metadata`;
- runs one allowlisted Cargo command;
- uploads no artifacts;
- writes nothing to the repository;
- uses strict command and job timeouts.

## Disable or remove

Temporary shutdown:

1. set `enabled` to `false` in `.github/agent-build-policy.json`;
2. disable the workflow through GitHub.

Complete removal:

```bash
python3 .agents/skills/github-actions-build/scripts/github_actions_build.py --json removal-plan \
  --policy .github/agent-build-policy.json
```

Cancel active runs before deleting:

```text
.github/workflows/agent-compile.yml
.github/agent-build-policy.json
.agents/skills/github-actions-build/
```

Do not delete workflow runs from the current accounting periods unless accepting that the budget history becomes incomplete.

## Safety boundaries

- No arbitrary commands or command inputs.
- No branch-head builds when an exact commit SHA is available.
- No matrix, parallel jobs, automatic retries, artifacts, secrets, publishing, or write permissions.
- No dispatch with incomplete history or insufficient reserved budget.
- The connector retains GitHub authentication.
- Repository-specific installation is separate from the skill and can be removed completely.

## Verification

From a clone of this repository:

```bash
python3 -m py_compile github-actions-build/scripts/github_actions_build.py
python3 -m unittest discover -s github-actions-build/tests -p 'test_*.py'
python3 github-actions-build/scripts/github_actions_build.py --help
python3 github-actions-build/scripts/github_actions_build.py --json validate-policy \
  --policy github-actions-build/examples/policy.json
```

## Documentation

- [`SKILL.md`](SKILL.md): complete execution, accounting, connector, and removal workflow.
- [`templates/agent-compile.yml`](templates/agent-compile.yml): reviewed manual Rust workflow template.
- [`examples/policy.json`](examples/policy.json): disabled default policy.
- [`examples/history.json`](examples/history.json): normalized connector history format.
