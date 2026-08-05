# GitHub Workspace

`github-workspace` creates reusable local repository workspaces from files fetched through a GitHub connector. It provides checkout-like behavior without giving the Python runtime GitHub credentials.

## Capabilities

- sparse or complete connector-backed materialization;
- exact baseline commit, tree, blob, mode, and SHA-256 tracking;
- local status and publication manifests;
- content-addressed baseline storage and reset;
- conflict-aware three-way refresh;
- portable archive and restore;
- guarded complete workspace cleanup;
- regular, executable, binary, and symlink preservation.

It does not authenticate to GitHub, clone repositories, push commits, or create pull requests.

## Requirements

- Python 3.9 or later;
- a writable local filesystem;
- a GitHub connector capable of listing repository content and fetching blobs;
- connector write operations when publication is required.

No third-party Python packages are required.

## Installation

Project-local:

```bash
mkdir -p .agents/skills
cp -R /path/to/SKILLS/github-workspace .agents/skills/github-workspace
```

Global:

```text
~/.agents/skills/github-workspace
```

The skill is also available through the repository's OpenCode V2 HTTP catalog.

## Materialize a workspace

The connector first fetches the desired files and records their exact repository metadata. Create a manifest such as [`examples/materialize-manifest.json`](examples/materialize-manifest.json).

Each file uses either:

- `source`: an absolute path or a path relative to the manifest; or
- `content_base64`: exact bytes encoded as base64.

Then run:

```bash
python3 .agents/skills/github-workspace/scripts/github_workspace.py --json materialize \
  --root /absolute/path/to/workspace \
  --manifest /absolute/path/to/materialize.json
```

The root must be empty. The helper creates `.github-workspace/state.json` and a content-addressed baseline object store.

## Status and publication

```bash
python3 .agents/skills/github-workspace/scripts/github_workspace.py --json status \
  --root /absolute/path/to/workspace
```

```bash
python3 .agents/skills/github-workspace/scripts/github_workspace.py --json manifest \
  --root /absolute/path/to/workspace \
  --output /absolute/path/to/publish.json
```

The publication manifest identifies local sources, hashes, modes, and deletions. The GitHub connector must still create blobs, a commit, and update the branch.

## Refresh

A refresh manifest has the same file-entry format as materialization plus:

```json
{
  "commit_sha": "new commit SHA",
  "tree_sha": "new tree SHA",
  "files": [],
  "deleted": []
}
```

Preview first:

```bash
python3 .agents/skills/github-workspace/scripts/github_workspace.py --json refresh \
  --root /absolute/path/to/workspace \
  --manifest /absolute/path/to/refresh.json
```

Apply only when the preview reports no conflicts:

```bash
python3 .agents/skills/github-workspace/scripts/github_workspace.py --json refresh \
  --root /absolute/path/to/workspace \
  --manifest /absolute/path/to/refresh.json \
  --apply
```

## Reset

```bash
python3 .agents/skills/github-workspace/scripts/github_workspace.py --json reset \
  --root /absolute/path/to/workspace \
  --path src/lib.rs \
  --yes
```

Untracked file deletion additionally requires `--remove-untracked`. Untracked directories are not recursively deleted.

## Archive and restore

```bash
python3 .agents/skills/github-workspace/scripts/github_workspace.py --json archive \
  --root /absolute/path/to/workspace \
  --output /absolute/path/to/workspace.tar.gz
```

```bash
python3 .agents/skills/github-workspace/scripts/github_workspace.py --json restore \
  --archive /absolute/path/to/workspace.tar.gz \
  --root /absolute/path/to/restored
```

Archives include the workspace state and baseline objects. Common build outputs are excluded unless `--include-build-output` is explicitly provided.

## Verify and clean

```bash
python3 .agents/skills/github-workspace/scripts/github_workspace.py --json verify \
  --root /absolute/path/to/workspace
```

```bash
python3 .agents/skills/github-workspace/scripts/github_workspace.py --json clean \
  --root /absolute/path/to/workspace \
  --yes
```

Dirty workspaces are refused. Add `--discard-changes` only when unpublished changes are intentionally being destroyed.

## Safety boundaries

- GitHub credentials remain in the connector.
- `.github-workspace` must never be committed.
- Materialization and restore require an empty root.
- Refresh conflicts block all refresh writes.
- Repository and archive symlinks are preserved but never followed.
- Archive size is limited and common caches are excluded by default.
- Local runtime storage is temporary unless explicitly archived or published.
- The branch head must be rechecked before publication.

## Verification

From a clone of this repository:

```bash
python3 -m py_compile github-workspace/scripts/github_workspace.py
python3 -m unittest discover -s github-workspace/tests -p 'test_*.py'
python3 github-workspace/scripts/github_workspace.py --help
```

## Documentation

- [`SKILL.md`](SKILL.md): complete agent workflow and connector boundaries.
- [`examples/materialize-manifest.json`](examples/materialize-manifest.json): manifest format example.
