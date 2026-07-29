# Office VBA Agent Skill

Human-facing guide for the portable `office-vba` Agent Skill.

## What it does

The skill can inspect, extract, modify, verify, and optionally execute VBA stored in macro-enabled Microsoft Office files:

- Excel: `.xlsm`, `.xlam`
- Word: `.docm`, `.dotm`
- PowerPoint: `.pptm`, `.ppam`, `.potm`

It uses [`miclip/office-vba-mcp`](https://github.com/miclip/office-vba-mcp) as the Office-file engine. The platform binary is not committed to this repository; the included installer retrieves the matching upstream release for the consumer's operating system and CPU architecture.

Do not use this skill to silently rename or convert `.xlsx`, `.docx`, or `.pptx` files. Those formats are not macro-enabled.

## Requirements

- Python 3.9 or newer.
- macOS, Linux AMD64, or Windows AMD64 for the documented upstream release assets.
- A macro-enabled Office file for list, read, or write operations.
- Microsoft Office is not required for file-level reading or writing.
- Running a macro requires the corresponding Office application to be running with the target document open and depends on host/platform automation support.

## Install the skill and runtime

The skill installer places the skill at `~/.agents/skills/office-vba`, downloads the upstream runtime into its private `bin/` directory, and runs the MCP doctor check.

macOS or Linux:

```bash
git clone https://github.com/mkroemer/SKILLS.git
cd SKILLS
sh ./office-vba/install-skill.sh
```

Windows PowerShell:

```powershell
git clone https://github.com/mkroemer/SKILLS.git
cd SKILLS
./office-vba/install-skill.ps1
```

Set `OFFICE_VBA_SKIP_BINARY_INSTALL=1` before running the skill installer to install only the skill files.

## Install or update only the runtime binary

From the `office-vba` directory:

```bash
sh ./install.sh
sh ./install.sh --version v1.2.3
sh ./install.sh --force
sh ./install.sh --require-checksum
```

Windows:

```powershell
./install.ps1
./install.ps1 --version v1.2.3
./install.ps1 --force
./install.ps1 --require-checksum
```

The default version is `latest`. Use an explicit release tag when reproducible installation is required. `--force` replaces an existing binary.

The installer:

1. detects the operating system and CPU architecture;
2. queries the original `miclip/office-vba-mcp` GitHub release;
3. selects the matching release asset from `manifest.json`;
4. downloads to a temporary file and installs atomically;
5. verifies GitHub's SHA-256 asset digest or a published checksum file when available;
6. records provenance in `bin/VERSION.json`;
7. runs `office-vba.py doctor` unless `--no-doctor` is supplied.

When no upstream checksum is available, installation succeeds with a warning. Use `--require-checksum` where unverified release assets must be rejected.

## Supported runtime assets

| Platform | Upstream asset |
|---|---|
| macOS Apple Silicon | `office-vba-mcp-darwin-arm64` |
| macOS Intel | `office-vba-mcp-darwin-amd64` |
| Linux AMD64 | `office-vba-mcp-linux-amd64` |
| Windows AMD64 | `office-vba-mcp-windows-amd64.exe` |

## Verify the installation

macOS or Linux:

```bash
python3 ~/.agents/skills/office-vba/scripts/office-vba.py doctor
```

Windows PowerShell:

```powershell
& "$HOME\.agents\skills\office-vba\scripts\office-vba.ps1" doctor
```

The doctor check confirms that the runtime starts and exposes `vba_list`, `vba_read`, `vba_write`, and `vba_run`.

## Basic usage

The standalone wrapper works even when the host agent is not configured as an MCP client.

List modules and procedures:

```bash
python3 office-vba/scripts/office-vba.py list /absolute/path/Deck.pptm
```

Extract VBA source:

```bash
python3 office-vba/scripts/office-vba.py read /absolute/path/Deck.pptm \
  --output-dir /absolute/path/vba_src
```

Write edited `.bas` and `.cls` files back into the document:

```bash
python3 office-vba/scripts/office-vba.py write /absolute/path/Deck.pptm \
  --input-dir /absolute/path/vba_src \
  --yes
```

Run a named macro only when execution is explicitly intended:

```bash
python3 office-vba/scripts/office-vba.py run /absolute/path/Deck.pptm Module1.Main --yes
```

Add `--json` to commands when structured output is required.

## Safe workflow

1. List the VBA modules before changing anything.
2. Extract source into a dedicated directory.
3. Inspect suspicious file, network, shell, registry, AppleScript, or COM operations before execution.
4. Edit only the necessary modules and preserve VBA attributes and document-module names.
5. Write with explicit `--yes`; the runtime creates a sibling `.bak` file.
6. List and re-extract the changed modules to verify the written source.
7. Keep the backup until the document has been opened and tested in Office.

Important limitations:

- Modifying a VBA project invalidates its existing digital signature.
- File-level validation is not equivalent to compilation by Office.
- Do not run an unknown macro merely to inspect it.
- Do not bypass Office macro-security controls.
- Do not claim macro execution succeeded solely because no output was returned.

## Operating modes

- **Standalone:** the included Python wrapper launches the MCP runtime over stdio for each command. This works with OpenCode and other shell-capable agents.
- **Native MCP:** configure `office-vba-mcp` directly in an MCP-capable client. Example configurations are in [`examples/`](examples/).

## Documentation

- [`SKILL.md`](SKILL.md) — agent workflow and safety requirements.
- [`references/installation.md`](references/installation.md) — installer behavior and environment variables.
- [`references/commands.md`](references/commands.md) — complete command reference.
- [`references/safety.md`](references/safety.md) — detailed VBA handling boundaries.
- [`../AGENTS.md`](../AGENTS.md) — repository-wide documentation requirements.

## License

The skill, wrappers, and installers in this directory are licensed under MIT. The separately downloaded runtime remains subject to its upstream license.
