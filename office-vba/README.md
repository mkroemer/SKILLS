# Office VBA Agent Skill

Portable Agent Skill for inspecting, extracting, modifying, and optionally executing VBA in macro-enabled Excel, Word, and PowerPoint files.

It uses [`miclip/office-vba-mcp`](https://github.com/miclip/office-vba-mcp) as the Office-file engine but does not require the host agent to support MCP configuration. A standard-library Python wrapper can launch the MCP server over stdio for each command.

## Install

```bash
git clone https://github.com/mkroemer/SKILLS.git
cd SKILLS
sh ./office-vba/install-skill.sh
sh ./office-vba/install.sh
```

Windows PowerShell:

```powershell
git clone https://github.com/mkroemer/SKILLS.git
cd SKILLS
./office-vba/install-skill.ps1
./office-vba/install.ps1
```

The skill becomes available globally at `~/.agents/skills/office-vba`.

## Verify

```bash
python3 ~/.agents/skills/office-vba/scripts/office-vba.py doctor
```

Windows:

```powershell
~/.agents/skills/office-vba/scripts/office-vba.ps1 doctor
```

## Usage

```bash
python3 office-vba/scripts/office-vba.py list /path/to/file.pptm
python3 office-vba/scripts/office-vba.py read /path/to/file.pptm --output-dir /path/to/vba_src
python3 office-vba/scripts/office-vba.py write /path/to/file.pptm --input-dir /path/to/vba_src --yes
```

See [`SKILL.md`](SKILL.md), [`references/commands.md`](references/commands.md), and [`references/safety.md`](references/safety.md).

## Operating modes

- **Standalone:** The skill calls the included Python wrapper. Works with OpenCode and other shell-capable agents.
- **Native MCP:** Configure `office-vba-mcp` directly in OpenCode or another MCP client. Example configurations are in [`examples/`](examples/).

## License

The skill, wrappers, and installers in this directory are licensed under MIT. The separately downloaded upstream binary remains subject to its own license.
