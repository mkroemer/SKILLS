# SKILLS

Reusable Agent Skills with human documentation, agent instructions, and supporting scripts or references.

## Available skills

| Skill | Purpose | Primary environment |
|---|---|---|
| [`github-file-edit`](github-file-edit/) | Edit, create, move, copy, or delete GitHub repository files through connector-backed Python workspaces when native patch operations are unavailable. | ChatGPT or another agent with a GitHub connector, Python 3.9+ |
| [`office-vba`](office-vba/) | Inspect, extract, modify, verify, and optionally execute VBA in macro-enabled Excel, Word, and PowerPoint files. | macOS, Linux, or Windows; Python and downloaded MCP runtime |
| [`sinumerik-ipc-bootstrap`](sinumerik-ipc-bootstrap/) | Classify and guide network, WinRM, bootstrap, deployment, and optional runtime diagnosis or recovery using a selected IPC profile. | Windows, PowerShell, SINUMERIK IPC, host project files |
| [`sinumerik-ipc-connect`](sinumerik-ipc-connect/) | Connect to a configured SINUMERIK IPC with protected credentials, exact-host trust handling, or approved bootstrap staging. | Windows, PowerShell, SINUMERIK IPC |
| [`sinumerik-ipc-profiles`](sinumerik-ipc-profiles/) | Share non-secret machine targets, account names, transport settings, bootstrap mappings, runtime probes, and Operate paths across SINUMERIK skills. | Windows, JSON profiles, PowerShell |
| [`sinumerik-operate-softkeys`](sinumerik-operate-softkeys/) | Inspect, add, update, or remove ownership-tracked SINUMERIK Operate OEM softkeys with guarded WinRM or SMB staging. | Windows, PowerShell, SINUMERIK Operate IPC |

Each skill directory contains a human-facing `README.md` and an agent-facing `SKILL.md`. Read the individual README before installing or running a skill; some skills depend on files from a host project and are not standalone utilities.

The SINUMERIK skills use the shared `sinumerik-ipc-profiles` format. Generic
skill logic contains no organization accounts or fixed machine addresses. The
baseline profile supplies overridable IPC and remote-scope defaults, while
optional presets provide further organization-specific non-secret values,
including the Gleason values that were previously hardcoded.

## Use as an OpenCode V2 catalog

This repository publishes an OpenCode V2 HTTP catalog through [`index.json`](index.json).

Add the raw repository root to the `skills` array in a project or global `opencode.json`/`opencode.jsonc`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "skills": [
    "https://raw.githubusercontent.com/mkroemer/SKILLS/main/"
  ]
}
```

A copyable example is available in [`opencode.catalog.example.json`](opencode.catalog.example.json). OpenCode downloads the files listed for each skill and refreshes an entry when its catalog `version` changes.

The catalog provides skill discovery and supporting files. It does not remove runtime, credential, network, or consuming-project requirements. Read [`CATALOG.md`](CATALOG.md) and the selected skill's README before executing scripts.

## Give the repository URL to an agent

An agent with Git and filesystem access can install a named skill from:

```text
https://github.com/mkroemer/SKILLS
```

A safe request is:

```text
Install <skill-name> from https://github.com/mkroemer/SKILLS.
Read the repository and selected skill documentation first. Install only that
skill and its documented dependencies, verify the installation, and do not run
the skill's operational task as part of installation.
```

The agent should clone the repository, read the root and skill documentation, copy or link only the requested skill to the correct skill directory, install documented dependencies, and run the skill's verification steps. Detailed instructions and limitations are in [`CATALOG.md`](CATALOG.md).

## Install a skill from a clone

OpenCode and other Agent Skills consumers can discover project-local skills under `.agents/skills/<name>` and global skills under `~/.agents/skills/<name>`. OpenCode also supports `.opencode/skills` and additional compatible locations.

### Project-local installation

From the project that should use a skill, copy or link the selected directory into `.agents/skills`.

macOS or Linux:

```bash
mkdir -p .agents/skills
ln -s "$(pwd)/../SKILLS/<skill-name>" ".agents/skills/<skill-name>"
```

Windows PowerShell:

```powershell
New-Item -ItemType Directory -Force '.agents\skills' | Out-Null
New-Item -ItemType Junction `
  -Path '.agents\skills\<skill-name>' `
  -Target (Resolve-Path '..\SKILLS\<skill-name>')
```

Adjust the source path to the location where this repository was cloned. A normal directory copy is also valid.

### Global installation

Place or link a skill directory at:

```text
~/.agents/skills/<skill-name>
```

Use a project-local installation when the skill requires companion files from the consuming repository. The `office-vba` skill provides dedicated installers that also retrieve its required runtime binary; see its README.

## Repository conventions

Repository-wide maintenance rules are in [`AGENTS.md`](AGENTS.md). In particular:

- every skill must have its own README for human consumers;
- adding, renaming, or removing a skill requires updating this root README and `index.json` in the same change;
- catalog file lists must contain every file required by remote consumers;
- a skill's catalog `version` must change whenever a catalog-delivered file changes;
- individual READMEs must stay synchronized with installation, usage, safety, and dependency changes.

## Skill anatomy

```text
<skill-name>/
├── SKILL.md       # Agent-facing workflow and boundaries
├── README.md      # Human-facing installation and usage guide
├── AGENTS.md      # Optional, stricter maintenance rules
├── scripts/       # Optional executable helpers
├── references/    # Optional detailed guidance
├── examples/      # Optional configuration examples
└── tests/         # Optional offline validation
```

OpenCode filesystem discovery is documented in the official [Agent Skills documentation](https://opencode.ai/docs/skills). OpenCode V2 HTTP catalogs are documented in the official [V2 Skills documentation](https://opencode.ai/v2/docs/skills).
