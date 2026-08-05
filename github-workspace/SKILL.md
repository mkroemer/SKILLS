---
name: github-workspace
description: Create and maintain connector-backed local repository workspaces with sparse materialization, baseline objects, status, publication manifests, conflict-aware refresh, reset, archive, restore, and cleanup. Use when repository work needs a reusable local filesystem without giving Python GitHub credentials.
compatibility: ChatGPT and other agents with a GitHub connector plus Python 3.9+ and a writable local filesystem.
metadata:
  author: mkroemer
  runtime: python3
  scope: github-repository-workspaces
---

# GitHub Workspace

Use this skill when GitHub repository files need to be materialized into a local workspace for repeated inspection, editing, testing, or handoff.

The GitHub connector remains responsible for authentication, repository reads, branch state, blob creation, commits, and pull requests. The bundled Python helper performs local storage and synchronization only.

For guarded text and filesystem transformations inside a workspace, use `github-file-edit`. The workspace skill does not require it.

## Workspace boundary

A workspace contains:

```text
<workspace-root>/
├── repository files
└── .github-workspace/
    ├── state.json
    └── objects/
```

`.github-workspace` is runtime state. Never publish it to the repository.

The object store retains the exact baseline bytes needed for status, reset, refresh conflict detection, and portable archives. It does not store GitHub credentials.

## Required connector workflow

### 1. Resolve repository state

Before materialization:

1. Read repository instructions such as `AGENTS.md`.
2. Resolve the exact repository, ref, commit SHA, and tree SHA.
3. Decide whether the requested checkout is `sparse` or `complete`.
4. Define include and exclude scope before fetching files.
5. Set explicit maximum file and total workspace sizes.

Prefer a sparse checkout. Do not fetch a complete repository merely because it is simpler.

### 2. Fetch files through GitHub

Use the GitHub connector to list the selected tree and fetch each required blob. Record:

- repository-relative path;
- blob SHA;
- Git mode (`100644`, `100755`, or `120000`);
- exact bytes;
- baseline commit and tree SHAs.

Do not follow repository symlinks. Fetch their Git blob content, which is the link target text.

Write connector-fetched bytes to temporary input files or encode them as base64 in a materialization manifest. Connector references are not automatically local files.

### 3. Materialize

Create a manifest matching `examples/materialize-manifest.json`, then run:

```bash
python3 scripts/github_workspace.py --json materialize \
  --root /absolute/path/to/workspace \
  --manifest /absolute/path/to/materialize.json
```

The workspace root must be empty. The helper:

- validates repository-relative paths;
- rejects path traversal and reserved state paths;
- recreates regular files, executable files, and symlinks;
- creates content-addressed baseline objects;
- records the connector blob SHAs and baseline commit.

### 4. Inspect local state

```bash
python3 scripts/github_workspace.py --json status \
  --root /absolute/path/to/workspace
```

Status reports tracked modifications, deletions, mode changes, unsupported type changes, and untracked files. It excludes `.github-workspace` automatically.

### 5. Edit and test

Use ordinary local tools or `github-file-edit` against the workspace root. Keep build outputs and dependency caches outside the workspace when practical.

Do not treat local success as repository publication. The local workspace remains derived state until a GitHub commit is created.

### 6. Build a publication manifest

```bash
python3 scripts/github_workspace.py --json manifest \
  --root /absolute/path/to/workspace \
  --output /absolute/path/to/publish.json
```

The manifest includes:

- baseline commit and tree SHAs;
- created and modified file paths;
- Git modes;
- local source paths or base64 symlink content;
- SHA-256 values;
- explicit deletions.

Immediately before publication, re-read the branch head. If it differs from the baseline, refresh before writing.

For multiple changes, prefer one Git tree commit with fast-forward ref update. Never publish `.github-workspace`.

## Conflict-aware refresh

To update a workspace after its branch moved:

1. Use the connector to fetch every remotely changed file needed for the workspace scope.
2. Include explicit deleted paths.
3. Create a refresh manifest containing the new commit SHA, tree SHA, fetched file bytes, and deletions.
4. Preview:

```bash
python3 scripts/github_workspace.py --json refresh \
  --root /absolute/path/to/workspace \
  --manifest /absolute/path/to/refresh.json
```

5. If there are no conflicts, apply:

```bash
python3 scripts/github_workspace.py --json refresh \
  --root /absolute/path/to/workspace \
  --manifest /absolute/path/to/refresh.json \
  --apply
```

The helper uses baseline, local, and remote content:

- local unchanged and remote changed: update locally;
- local changed and remote unchanged: keep local change;
- local and remote changed: conflict;
- remote deleted and local unchanged: delete locally;
- remote deleted and local changed: conflict.

If any conflict exists, `--apply` changes nothing. Resolve conflicts deliberately, then create a new refresh manifest or re-materialize.

## Reset

Restore tracked paths from the local baseline object store:

```bash
python3 scripts/github_workspace.py --json reset \
  --root /absolute/path/to/workspace \
  --path src/lib.rs \
  --yes
```

Removing an untracked file requires both `--path`, `--remove-untracked`, and `--yes`. The helper refuses to recursively remove an untracked directory.

## Persistent handoff archive

A ChatGPT local filesystem must not be assumed to persist across runtimes. Create an explicit archive when the workspace must be retained or handed off:

```bash
python3 scripts/github_workspace.py --json archive \
  --root /absolute/path/to/workspace \
  --output /absolute/path/to/workspace.tar.gz
```

By default, common build outputs and caches such as `.git`, `target`, `node_modules`, and virtual environments are excluded. Build outputs require explicit `--include-build-output` and still obey the archive size limit.

Restore only into an empty directory:

```bash
python3 scripts/github_workspace.py --json restore \
  --archive /absolute/path/to/workspace.tar.gz \
  --root /absolute/path/to/restored
```

The restore path validates archive members and rejects devices, hard links, absolute paths, and traversal.

## Verification and cleanup

Verify baseline object integrity:

```bash
python3 scripts/github_workspace.py --json verify \
  --root /absolute/path/to/workspace
```

Delete a workspace only after confirming it is managed and no unpublished changes are needed:

```bash
python3 scripts/github_workspace.py --json clean \
  --root /absolute/path/to/workspace \
  --yes
```

Dirty workspaces are refused. Add `--discard-changes` only when unpublished changes are intentionally being destroyed.

## Safety requirements

- Keep GitHub authentication in the connector, never in workspace files.
- Never publish `.github-workspace` or temporary connector inputs.
- Resolve and record an exact baseline commit SHA.
- Recheck branch state before publication.
- Prefer sparse materialization and explicit size limits.
- Never follow repository or archive symlinks.
- Treat refresh conflicts as blocking.
- Do not overwrite a non-empty directory during materialization or restore.
- Do not claim persistence unless an archive, branch, commit, or external storage object was created.
- Do not archive secrets, credentials, private keys, environment files, or unrelated private content.
- Verify the published branch after connector writes.

## Helper boundary

The helper does not:

- call GitHub APIs;
- clone with Git;
- store tokens;
- create branches or commits;
- resolve connector file references;
- automatically upload archives.

Those operations remain explicit agent and connector responsibilities.
