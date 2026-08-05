---
name: github-file-edit
description: Edit, create, move, copy, or delete GitHub repository files when a connector can read and replace files but cannot apply patches. Materialize the relevant files in a Python workspace, apply guarded declarative edits, validate the resulting diff, and publish with SHA-aware connector writes or one atomic Git tree commit.
compatibility: ChatGPT and other agents with a GitHub connector plus Python 3.9+ execution and a writable temporary filesystem.
metadata:
  author: mkroemer
  runtime: python3
  scope: github-repository-files
---

# GitHub File Edit

Use this skill when repository content must change through a GitHub connector that exposes file fetch/create/update/delete operations but no native patch tool or local checkout.

Do not use it for issue comments, PR reviews, labels, or other non-file GitHub operations.

## Core principle

The connector remains the source of truth and the publication channel. Python is the local edit engine.

Never send unified-diff text as a replacement file. Fetch the original file, materialize it in a workspace, apply the intended transformation, inspect the final diff, then send the complete final file content or construct one Git tree commit.

## Required workflow

### 1. Resolve repository state

1. Identify the repository, base branch, and repository instructions such as `AGENTS.md`.
2. Read the current base commit SHA and tree SHA.
3. Create or select a working branch before publishing.
4. Record the branch head SHA. Treat it as an optimistic-concurrency token.
5. Determine the complete intended file scope, including generated catalog or index files required by repository rules.

Do not begin writes while the repository, base branch, or intended file scope is ambiguous.

### 2. Fetch and materialize files

1. Fetch every existing target file through the GitHub connector.
2. Record each file's repository path, blob SHA, encoding, and exact content.
3. For moves or copies, fetch the source file or directory entries too.
4. Create a dedicated temporary workspace, normally below `/mnt/data/github-file-edit/<owner>/<repo>/<branch>/`.
5. Recreate only the relevant repository-relative paths in that workspace. A focused workspace is faster and safer than downloading the entire repository.
6. Write fetched text with exact newline preservation. Decode base64 connector responses before storing binary files.
7. Do not materialize credentials, tokens, or unrelated private files.

Connector resources are not automatically local files. Explicitly write fetched content into the Python workspace before editing it.

### 3. Build a declarative edit plan

Prefer the bundled `scripts/file_edit.py` helper over ad hoc string manipulation. Create a JSON plan such as:

```json
{
  "operations": [
    {
      "op": "replace_text",
      "path": "src/example.py",
      "old": "old_call()",
      "new": "new_call()",
      "expected": 1
    },
    {
      "op": "write_text",
      "path": "tests/test_example.py",
      "content": "def test_example():\n    assert True\n",
      "if_exists": "error"
    }
  ]
}
```

Supported operations:

- `assert_text`: require an exact-text occurrence count before editing.
- `assert_sha256`: require exact file bytes before editing.
- `replace_text`: replace exact text with an exact expected match count.
- `delete_text`: delete exact text with an exact expected match count.
- `replace_regex`: apply a regex replacement with explicit flags and expected count.
- `insert_text`: insert before or after an exact anchor.
- `replace_lines`: replace a 1-based inclusive line range.
- `append_text` and `prepend_text`.
- `write_text` and `write_base64`.
- `mkdir`, `copy`, `move`, `delete`, and `chmod`.

Use forward-slash repository paths. The helper rejects absolute paths, `..`, backslashes, and symlink traversal.

For semantic changes that cannot be represented safely by these operations, use a small Python parser or formatter specific to the file format, but retain the same workspace, precondition, diff, and publication workflow. Do not use broad unguarded replacements.

### 4. Dry-run and inspect

Run:

```bash
python3 scripts/file_edit.py apply \
  --root /absolute/path/to/workspace \
  --plan /absolute/path/to/edit-plan.json \
  --dry-run \
  --diff
```

A dry run must succeed before the real apply.

Inspect the complete diff. Confirm:

- only intended paths changed;
- exact replacement counts matched;
- moves and deletions are correct;
- formatting and line endings are acceptable;
- repository-required generated indexes or catalogs are included.

If the diff is wrong, correct the plan rather than patching the result manually without preconditions.

### 5. Apply and validate

Run:

```bash
python3 scripts/file_edit.py apply \
  --root /absolute/path/to/workspace \
  --plan /absolute/path/to/edit-plan.json \
  --diff \
  --manifest-out /absolute/path/to/manifest.json
```

Then run the most relevant offline validation available in the Python environment, for example:

- JSON or YAML parsing;
- Python compilation or unit tests;
- formatter or linter checks through `subprocess.run` when installed;
- project-specific tests documented by the repository;
- explicit checks that moved/deleted paths have the intended state.

Do not claim a build or test passed unless it actually ran successfully.

### 6. Recheck for conflicts

Immediately before publishing:

1. Re-read the working branch head SHA.
2. Compare it with the recorded head SHA.
3. If the branch moved, stop the write sequence, fetch the new versions, recreate the workspace, reapply the plan, and validate the new diff.
4. Never force-update a branch merely to preserve the local result.

For a single connector `update_file`, also use the fetched blob SHA expected by that operation.

### 7. Publish through the connector

#### Single-file change

For one independent file:

- existing file: use the connector's full-file update with the original blob SHA;
- new file: use create-file;
- deletion: use delete-file with the original blob SHA.

Send the complete final content, not a patch fragment.

#### Multi-file, move, or mixed create/delete change

Prefer one atomic Git data commit:

1. Create a blob for every final created or modified file.
2. Build a tree from the current branch tree SHA.
3. Add tree entries for created or modified paths using the new blob SHAs and correct modes.
4. Add deletion entries with a null SHA for removed paths.
5. Create one commit whose parent is the rechecked branch head SHA.
6. Update the working branch ref with fast-forward enforcement and `force: false`.
7. Open or update a pull request through the GitHub connector.

Do not publish a move as only a create. The old path must also be deleted in the same tree.

If the connector does not expose Git blob/tree/commit/ref operations, sequential content writes are a fallback. State that they are non-atomic, order deletions last, stop on the first failure, and report any partial publication precisely.

### 8. Verify the published result

1. Fetch the changed paths from the working branch.
2. Compare their bytes or SHA-256 values with the workspace manifest.
3. Confirm deleted paths no longer exist.
4. Inspect the branch or PR diff.
5. Report branch, commit, changed paths, and validation results.

## Safety requirements

- Read repository instructions before editing.
- Work on a branch unless the user explicitly directs an allowed default-branch write.
- Never overwrite a file from stale content.
- Require exact match counts or content hashes for nontrivial edits.
- Reject path traversal and symlink-based escapes.
- Use `recursive: true` only for an explicitly intended directory deletion.
- Treat binary data as base64 and verify hashes.
- Keep unrelated files out of the workspace and commit.
- Do not place secrets in edit plans, diffs, logs, or PR descriptions.
- Do not use Python to bypass connector permissions, branch protection, reviews, or repository security controls.
- Do not report success until the published branch has been re-fetched and verified.

## Helper boundary

The bundled helper performs local filesystem operations only. It does not authenticate to GitHub, call network APIs, create commits, or push branches. Those actions remain connector responsibilities.
