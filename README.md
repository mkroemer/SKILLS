# SKILLS

Reusable Agent Skills with human documentation, agent instructions, and supporting scripts or references.

## Available skills

| Skill | Purpose | Primary environment |
|---|---|---|
| [`gleason-operate-softkeys`](gleason-operate-softkeys/) | Inspect, add, update, or remove managed SINUMERIK Operate OEM softkeys with guarded WinRM or SMB staging. | Windows, SINUMERIK Operate IPC, project-local companion files |
| [`gleason-winrm-connect`](gleason-winrm-connect/) | Connect to a Gleason IPC through WinRM with protected credentials, or stage the approved bootstrap when transport is unavailable. | Windows, PowerShell, Gleason IPC |
| [`ipc-smb-winrm-bootstrap`](ipc-smb-winrm-bootstrap/) | Classify and guide approved SMB/WinRM bootstrap, deployment, runtime verification, diagnosis, and recovery for a SINUMERIK ONE IPC. | Windows, PowerShell, host project deployment scripts |
| [`office-vba`](office-vba/) | Inspect, extract, modify, verify, and optionally execute VBA in macro-enabled Excel, Word, and PowerPoint files. | macOS, Linux, or Windows; Python and downloaded MCP runtime |

Each skill directory contains a human-facing `README.md` and an agent-facing `SKILL.md`. Read the individual README before installing or running a skill; some skills depend on files from a host project and are not standalone utilities.

## Install a skill

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
- adding, renaming, or removing a skill requires updating this root README in the same change;
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

OpenCode discovery details are documented in the official [Agent Skills documentation](https://opencode.ai/docs/skills).
