# OpenCode setup

## Install as an Agent Skill

OpenCode discovers project and global Agent Skills from `.agents/skills/<name>/SKILL.md` and `~/.agents/skills/<name>/SKILL.md`.

From a clone of this repository:

```bash
sh ./office-vba/install-skill.sh
sh ./office-vba/install.sh
```

On Windows PowerShell:

```powershell
./office-vba/install-skill.ps1
./office-vba/install.ps1
```

A project-local installation can instead copy or link `office-vba/` to:

```text
<project>/.agents/skills/office-vba/
```

## Standalone mode

No OpenCode MCP configuration is required. The agent loads `SKILL.md` and invokes `scripts/office-vba.py`, which starts the MCP server for one command and exits.

This mode is portable across agents that can execute shell commands and Python.

## Native MCP mode

Native mode keeps the server connected and exposes its four tools directly to OpenCode. Use an absolute binary path in `opencode.json`.

Current stable configuration shape:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "office-vba": {
      "type": "local",
      "command": ["/absolute/path/to/office-vba-mcp"],
      "enabled": true
    }
  }
}
```

OpenCode V2 configuration shape:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "office-vba": {
        "type": "local",
        "command": ["/absolute/path/to/office-vba-mcp"],
        "codemode": false
      }
    }
  }
}
```

Use the configuration shape documented by the installed OpenCode version. The examples directory contains both forms.
