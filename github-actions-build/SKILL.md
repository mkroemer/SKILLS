---
name: github-actions-build
description: Run narrowly scoped, reviewed compilation checks through a dedicated manual GitHub Actions workflow when the local ChatGPT runtime cannot compile the project. Enforce a skill-specific daily and monthly minute budget from workflow job history, reuse matching successful runs, allow no arbitrary commands, and support disablement and complete removal.
compatibility: ChatGPT and other agents with a GitHub connector capable of reading workflow history and, for execution, enabling, dispatching, monitoring, cancelling, and disabling workflows. Python 3.9+ is required for local policy and budget checks.
metadata:
  author: mkroemer
  runtime: python3,github-actions
  scope: guarded-remote-builds
---

# GitHub Actions Build

Use this optional skill when source changes require compilation or focused tests that cannot run in the local agent environment, for example Rust compilation in a ChatGPT Python runtime.

Do not use GitHub Actions merely for convenience. Prefer local validation when the required compiler is available.

This skill uses a dedicated manual workflow and a dedicated execution budget derived only from that workflow's history. It does not need account-wide GitHub billing access.

## Separation of responsibility

The bundled Python helper:

- validates a checked-in build policy;
- prepares allowlisted build requests;
- calculates daily and monthly usage from connector-fetched workflow jobs;
- reports the skill budget remaining;
- reuses matching successful runs;
- renders the reviewed workflow template;
- produces a complete removal plan.

The GitHub connector remains responsible for:

- reading workflow runs and jobs;
- enabling and disabling the workflow;
- dispatching `workflow_dispatch`;
- monitoring, cancelling, and retrieving logs;
- deleting repository files when uninstalling.

The Python helper receives no GitHub token and performs no network requests.

## Installation is explicit

The skill directory alone cannot run Actions. A consuming repository must separately install:

```text
.github/workflows/agent-compile.yml
.github/agent-build-policy.json
```

Start from:

- `templates/agent-compile.yml`
- `examples/policy.json`

Render the hard limits into the workflow:

```bash
python3 scripts/github_actions_build.py --json render-workflow \
  --policy /path/to/policy.json \
  --template templates/agent-compile.yml \
  --output /workspace/.github/workflows/agent-compile.yml
```

The workflow must be reviewed and merged to the repository's default branch before GitHub accepts manual dispatches. Installation must never be silently bundled into an unrelated feature pull request.

Keep the policy disabled initially:

```json
"enabled": false
```

After the workflow reaches the default branch, disable it through GitHub as an additional operational control when the connector exposes workflow enable/disable operations.

## Fixed safety profile

The included workflow supports exactly:

- `rust-check-package`
- `rust-test-package`
- `rust-build-package`

Every request requires:

- an exact 40-character commit SHA;
- one explicit Cargo package;
- one reviewed profile;
- one request identifier.

It does not accept shell commands, arbitrary arguments, feature lists, workspace-wide builds, matrices, custom runners, artifacts, publication, deployment, or repository writes.

The workflow uses:

- `workflow_dispatch` only;
- `contents: read` only;
- one `ubuntu-latest` job;
- one concurrency group;
- cancellation of obsolete in-progress agent builds;
- a strict job timeout;
- a shorter command timeout;
- an exact commit checkout;
- `persist-credentials: false`;
- a full commit SHA pin for `actions/checkout`.

Any expansion of profiles or permissions requires a separate reviewed change to both the policy validator and workflow template.

## Ask for the skill budget

When the user asks how much agent build budget remains:

1. Read `.github/agent-build-policy.json` from the default branch.
2. List runs belonging only to the configured `workflow_path`.
3. Fetch jobs for every run needed for the current UTC day and month.
4. Include older matching runs when checking result reuse.
5. Write normalized history matching `examples/history.json`.
6. Set `complete: false` when runs or job pages are unavailable, deleted, truncated, or ambiguous.
7. Run:

```bash
python3 scripts/github_actions_build.py --json budget \
  --policy /path/to/policy.json \
  --history /path/to/history.json
```

Report separately:

- daily limit, used, and remaining minutes;
- monthly limit, used, and remaining minutes;
- maximum reservation for the next run;
- active agent jobs;
- whether history was complete;
- whether another run is allowed.

Do not infer account-wide Actions allowance. This budget applies only to the dedicated agent workflow.

## Accounting rules

For every non-skipped job in the dedicated workflow:

1. Use `started_at` to `completed_at` duration.
2. For a running job, use `started_at` to the current time.
3. Attribute only the job-duration overlap to the current UTC day and month.
4. Round each job or period overlap upward to a full minute.
5. Sum jobs, not workflow wall-clock duration.
6. Count successful, failed, cancelled, and timed-out jobs.
7. Exclude queue time before `started_at`.
8. Treat incomplete history as blocking.

Workflow-run deletion can remove accounting evidence. Do not delete runs inside the active daily or monthly budget periods. Logs and artifacts are not enabled by the default profile.

## Prepare a build request

The policy must first be explicitly enabled in a reviewed repository change or user-approved temporary policy edit.

```bash
python3 scripts/github_actions_build.py --json prepare \
  --policy /path/to/policy.json \
  --target-sha 0123456789abcdef0123456789abcdef01234567 \
  --profile rust-check-package \
  --package gear-math \
  --output /path/to/request.json
```

The request records a policy hash. Any policy change invalidates the request.

## Mandatory preflight

Immediately before dispatch:

1. Refresh workflow run and job history.
2. Run:

```bash
python3 scripts/github_actions_build.py --json preflight \
  --policy /path/to/policy.json \
  --history /path/to/history.json \
  --request /path/to/request.json
```

Possible actions:

- `reuse`: a successful run already exists for the same commit, profile, and package;
- `dispatch`: budget and concurrency checks pass;
- `deny`: do not dispatch and report all reasons.

A run is denied when:

- policy is disabled;
- history is incomplete;
- another agent build is active;
- daily or monthly remaining budget is less than the full run reservation;
- the same request reached its run limit.

Never bypass preflight because a change appears small.

## Dispatch lifecycle

When preflight returns `dispatch`:

1. State the requested profile, package, exact commit, daily remaining minutes, monthly remaining minutes, and maximum run reservation.
2. Obtain explicit user approval unless the current user instruction already clearly authorizes this exact build.
3. Enable the dedicated workflow if it is disabled.
4. Dispatch the workflow on the default branch using only `request.dispatch_inputs`.
5. Identify the created run by request ID and creation time.
6. Disable the workflow immediately after the run is accepted, where connector support permits it.
7. Monitor the run and cancel it if it becomes irrelevant, exceeds policy, or the user cancels.
8. Fetch job logs after completion.
9. Report exact commands represented by the profile and the run result.

If the connector cannot enable, dispatch, cancel, or inspect the workflow safely, stop and state the missing capability. Do not place GitHub credentials into Python to work around it.

## Retry policy

No automatic retries are allowed.

A second run requires:

- changed source, target SHA, profile, or package; or
- clear evidence of transient GitHub infrastructure failure;
- another complete preflight;
- remaining budget;
- explicit user approval for an unchanged request.

Prefer re-running only a failed job when the connector supports it and the policy permits the request count. The default policy still counts all consumed job minutes.

## Disablement

Temporary shutdown has two layers:

1. set policy `enabled` to `false`;
2. disable the workflow through GitHub.

The skill must report both states when known. A disabled policy blocks local request preparation even if someone can still see the workflow in GitHub.

## Complete removal

Before removal:

1. cancel any active agent build;
2. disable the workflow;
3. ask for explicit confirmation;
4. run the removal-plan command:

```bash
python3 scripts/github_actions_build.py --json removal-plan \
  --policy /path/to/policy.json
```

Then delete in one reviewed change:

```text
.github/workflows/agent-compile.yml
.github/agent-build-policy.json
.agents/skills/github-actions-build/
```

If the skill was installed globally rather than vendored, remove only the consuming repository's workflow and policy plus the global skill directory separately.

Historical workflow runs may remain for audit and budget history. Removing repository files does not cancel an already running job.

## Safety requirements

- Never accept arbitrary build commands or shell fragments.
- Never run against a moving branch when an exact commit can be used.
- Never use a matrix or parallel jobs in the default profile.
- Never automatically retry.
- Never dispatch with incomplete history.
- Never dispatch when remaining daily or monthly budget is below the full reservation.
- Never enable artifacts, publication, deployment, secrets, or write permissions without a separate reviewed design.
- Never build untrusted fork code with repository secrets.
- Never modify unrelated CI workflows to obtain compilation.
- Never claim account-wide budget visibility.
- Never delete active-period run history used for accounting.
- Keep the workflow removable and independent from `github-file-edit` and `github-workspace`.
