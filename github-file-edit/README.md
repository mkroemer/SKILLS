# GitHub File Edit

`github-file-edit` lets an agent make repository file changes when its GitHub connector can fetch and replace files but cannot apply patches.

The connector remains responsible for repository access and publication. The included Python helper applies guarded edits to a temporary workspace, shows the resulting diff, and produces a manifest that can be verified after publication.

## What it supports

The helper can:

- create or replace UTF-8 text files;
- write binary files from base64;
- replace exact text or regular expressions with required match counts;
- insert, append, prepend, delete, or replace line ranges;
- create directories;
- copy, move, delete, and change file modes;
- dry-run an edit plan without changing the workspace;
- show unified diffs for UTF-8 files;
- report SHA-256 hashes and file states for connector verification.

It does not call GitHub, hold credentials, commit, push, or bypass branch protection.

## Requirements

- Python 3.9 or later.
- A writable temporary filesystem.
- A GitHub connector that can fetch repository files and publish full file contents.
- For atomic multi-file publication, connector operations equivalent to Git blobs, trees, commits, and ref updates.

No third-party Python packages are required.

## Installation

### Project-local

Copy or link the skill into the consuming project's Agent Skills directory:

```bash
mkdir -p .agents/skills
ln -s "/path/to/SKILLS/github-file-edit" \
  ".agents/skills/github-file-edit"
```

On Windows PowerShell:

```powershell
New-Item -ItemType Directory -Force '.agents\skills' | Out-Null
New-Item -ItemType Junction `
  -Path '.agents\skills\github-file-edit' `
  -Target 'C:\path\to\SKILLS\github-file-edit'
```

### Global

Copy or link the directory to:

```text
~/.agents/skills/github-file-edit
```

The skill is also available through this repository's OpenCode V2 HTTP catalog.

## Basic usage

The agent first fetches relevant repository files through the connector and writes them into a focused workspace that preserves repository-relative paths.

Create an edit plan:

```json
{
  "operations": [
    {
      "op": "replace_text",
      "path": "src/example.py",
      "old": "return old_value",
      "new": "return new_value",
      "expected": 1
    },
    {
      "op": "write_text",
      "path": "tests/test_example.py",
      "content": "def test_value():\n    assert True\n",
      "if_exists": "error"
    }
  ]
}
```

Dry-run it:

```bash
python3 .agents/skills/github-file-edit/scripts/file_edit.py apply \
  --root /absolute/path/to/workspace \
  --plan /absolute/path/to/edit-plan.json \
  --dry-run \
  --diff
```

Apply it after reviewing the diff:

```bash
python3 .agents/skills/github-file-edit/scripts/file_edit.py apply \
  --root /absolute/path/to/workspace \
  --plan /absolute/path/to/edit-plan.json \
  --diff \
  --manifest-out /absolute/path/to/manifest.json
```

Publish the complete resulting file contents through the connector. For multiple files, moves, or mixed creations and deletions, prefer one Git tree commit rather than a sequence of independent file commits.

A more complete example plan is in [`examples/edit-plan.json`](examples/edit-plan.json).

## Plan operations

Every plan contains a non-empty `operations` array. Repository paths use forward slashes and are relative to `--root`.

### Guard operations

```json
{"op": "assert_text", "path": "README.md", "text": "Expected heading", "expected": 1}
```

```json
{"op": "assert_sha256", "path": "config.json", "sha256": "<64 hex characters>"}
```

### Text operations

```json
{
  "op": "replace_text",
  "path": "src/app.py",
  "old": "old()",
  "new": "new()",
  "expected": 1
}
```

```json
{
  "op": "replace_regex",
  "path": "src/app.py",
  "pattern": "^VERSION = .+$",
  "replacement": "VERSION = \"2\"",
  "flags": ["MULTILINE"],
  "expected": 1
}
```

```json
{
  "op": "insert_text",
  "path": "README.md",
  "anchor": "## Usage\n",
  "content": "New introductory text.\n\n",
  "position": "after",
  "expected": 1
}
```

`delete_text` uses `old` plus `expected`. `replace_lines` uses 1-based inclusive `start` and `end`. `append_text` and `prepend_text` use `content`.

### Filesystem operations

- `write_text`: `path`, `content`, optional `encoding`, `parents`, and `if_exists`.
- `write_base64`: `path`, `content_base64`, optional `parents`, and `if_exists`.
- `mkdir`: `path`, optional `parents` and `exist_ok`.
- `copy`: `source`, `path`, optional `overwrite` and `parents`.
- `move`: `source`, `path`, optional `overwrite` and `parents`.
- `delete`: `path`, optional `missing_ok`; directory trees require explicit `recursive: true`.
- `chmod`: `path`, `mode` as an octal string such as `"755"`.

`if_exists` accepts `replace`, `error`, or `skip`.

## Safety boundaries

- Use a branch and recheck its head SHA immediately before publication.
- Re-fetch and reapply when the branch moved. Do not overwrite newer repository content.
- Review a dry-run diff before applying.
- Use exact expected match counts or SHA-256 assertions for nontrivial changes.
- The helper rejects absolute paths, `..`, backslashes, and symlink traversal.
- Recursive deletion must be explicit.
- Keep the workspace limited to intended files. Dry-run copies the workspace and can be expensive for a complete large repository.
- Do not store credentials or private keys in plans, workspaces, diffs, manifests, or PR text.
- The helper's local success does not prove that a connector write or GitHub commit succeeded. Re-fetch the branch and compare hashes.

## Verification

From a clone of this repository:

```bash
python3 -m unittest discover \
  -s github-file-edit/tests \
  -p 'test_*.py'
```

Basic CLI verification:

```bash
python3 github-file-edit/scripts/file_edit.py --help
```

After connector publication, fetch every changed path from the branch and compare it with the generated manifest. Confirm deleted paths return not found and inspect the final PR diff.

## Documentation

- [`SKILL.md`](SKILL.md): agent workflow, connector publication strategy, and safety requirements.
- [`examples/edit-plan.json`](examples/edit-plan.json): copyable operation plan.
