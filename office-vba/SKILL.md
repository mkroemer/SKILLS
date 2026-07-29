---
name: office-vba
description: Inspect, extract, create, modify, verify, and optionally execute VBA in macro-enabled Excel, Word, and PowerPoint files. Uses native office-vba MCP tools when available, otherwise calls the bundled standalone Python wrapper.
license: MIT
compatibility: OpenCode, Claude Code, Codex, and shell-capable agents; requires Python 3.9+ and the office-vba-mcp binary.
metadata:
  author: mkroemer
  supported-files: xlsm,xlam,docm,dotm,pptm,ppam,potm
  runtime: python3,office-vba-mcp
---

# Office VBA

Use this skill for VBA projects stored in macro-enabled Microsoft Office files.

Supported extensions:

- Excel: `.xlsm`, `.xlam`
- Word: `.docm`, `.dotm`
- PowerPoint: `.pptm`, `.ppam`, `.potm`

Do not treat `.xlsx`, `.docx`, or `.pptx` as macro-enabled files. Do not silently rename or convert them.

## Tool selection

1. If native tools named `vba_list`, `vba_read`, `vba_write`, and `vba_run` are available, use them directly.
2. Otherwise call the standalone wrapper in `scripts/office-vba.py`.
3. Resolve all document and source-directory paths to absolute paths before invoking a tool.
4. Run `doctor` first when the binary location or installation state is uncertain.

The wrapper locates the MCP binary in this order:

1. `OFFICE_VBA_MCP`
2. `bin/office-vba-mcp` inside this skill
3. `office-vba-mcp` on `PATH`

## Standalone commands

Run these from the skill directory, or use an absolute path to the script.

```bash
python3 scripts/office-vba.py doctor
python3 scripts/office-vba.py list /absolute/path/Report.pptm
python3 scripts/office-vba.py read /absolute/path/Report.pptm --output-dir /absolute/path/vba_src
python3 scripts/office-vba.py read /absolute/path/Report.pptm --module Module1
python3 scripts/office-vba.py write /absolute/path/Report.pptm --input-dir /absolute/path/vba_src --yes
python3 scripts/office-vba.py run /absolute/path/Report.pptm Module1.Main --yes
```

Add `--json` when structured output is preferable.

## Safe workflow

### Inspect or explain existing VBA

1. Run `list`.
2. Run `read` into a dedicated source directory.
3. Read only the modules needed for the task.
4. Explain findings using module and procedure names.

### Modify VBA

1. Confirm that the target is a supported macro-enabled file.
2. Run `list` and `read` before changing source.
3. Edit the smallest necessary `.bas` or `.cls` files in the extracted source directory.
4. Preserve VBA attributes and document-module names unless the task explicitly requires changing them.
5. Show or summarize the intended source changes before writing when they are substantial.
6. Run `write ... --yes`. The upstream tool creates a sibling `.bak` file before modification.
7. Run `list` again.
8. Re-extract the changed modules and compare them with the intended source.
9. Report the changed modules and backup path.

### Execute VBA

Only run a macro when the user explicitly requests execution.

1. Confirm the host application is running and the target file is open.
2. State the macro name and target file.
3. Run `run ... --yes`.
4. Report the returned output or error without claiming success from absence of output alone.

## Safety requirements

- Never modify the only copy without a recoverable backup.
- Never run an unknown macro merely to inspect it.
- Never bypass Office macro-security settings.
- Modifying a VBA project invalidates existing digital signatures; disclose this before writing signed files.
- Treat VBA as executable code. Inspect suspicious file, network, shell, registry, AppleScript, or COM operations before execution.
- Do not overwrite unrelated modules.
- Do not claim VBA compilation succeeded unless the code was compiled by Office or an equivalent compiler. File-level validation is not compilation.
- For detailed constraints, read `references/safety.md`.

## Installation

Install the upstream binary into this skill's private `bin/` directory:

```bash
sh ./install.sh
```

Windows PowerShell:

```powershell
./install.ps1
```

The skill does not redistribute the upstream binary. The installers download the appropriate release from `miclip/office-vba-mcp`.

For native OpenCode MCP registration, see `examples/` and `references/opencode.md`.
