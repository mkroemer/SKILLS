# Office VBA Agent Skill

Portable Agent Skill for inspecting, extracting, modifying, and optionally executing VBA in macro-enabled Excel, Word, and PowerPoint files.

It uses [`miclip/office-vba-mcp`](https://github.com/miclip/office-vba-mcp) as the Office-file engine. The binary is not committed to this repository; the included installer downloads the correct upstream release for the consumer's operating system and architecture.

## Install the skill and binary

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

The skill is installed at `~/.agents/skills/office-vba`. By default, the installer also downloads the latest upstream `office-vba-mcp` release into the skill's private `bin/` directory and runs the MCP doctor check.

Set `OFFICE_VBA_SKIP_BINARY_INSTALL=1` before running `install-skill.sh` or `install-skill.ps1` to install only the skill files.

## Install or update only the binary

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

The default version is `latest`. Use an explicit release tag for reproducible installation. `--force` replaces an existing binary.

The installer:

1. Detects macOS, Linux, or Windows and the CPU architecture.
2. Queries the original `miclip/office-vba-mcp` GitHub release.
3. Selects the matching release asset from `manifest.json`.
4. Downloads to a temporary file and installs atomically.
5. Verifies GitHub's SHA-256 asset digest or a published checksum file when available.
6. Writes installation metadata to `bin/VERSION.json`.
7. Runs `office-vba.py doctor` unless `--no-doctor` is supplied.

When no upstream checksum is available, installation succeeds with a warning. Use `--require-checksum` in environments that must reject unverified release assets.

## Supported release assets

| Platform | Upstream asset |
|---|---|
| macOS Apple Silicon | `office-vba-mcp-darwin-arm64` |
| macOS Intel | `office-vba-mcp-darwin-amd64` |
| Linux AMD64 | `office-vba-mcp-linux-amd64` |
| Windows AMD64 | `office-vba-mcp-windows-amd64.exe` |

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

See [`SKILL.md`](SKILL.md), [`references/installation.md`](references/installation.md), [`references/commands.md`](references/commands.md), and [`references/safety.md`](references/safety.md).

## Operating modes

- **Standalone:** The skill calls the included Python wrapper. Works with OpenCode and other shell-capable agents.
- **Native MCP:** Configure `office-vba-mcp` directly in OpenCode or another MCP client. Example configurations are in [`examples/`](examples/).

## License

The skill, wrappers, and installers in this directory are licensed under MIT. The separately downloaded upstream binary remains subject to its upstream license.
