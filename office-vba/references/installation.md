# Runtime installation

The Agent Skill contains instructions and a Python MCP client, but VBA file operations are implemented by the separate `office-vba-mcp` executable. The executable is downloaded from the original `miclip/office-vba-mcp` GitHub releases and stored locally; it is not committed to this repository.

## One-step skill installation

macOS or Linux:

```bash
sh ./install-skill.sh
```

Windows PowerShell:

```powershell
./install-skill.ps1
```

These commands install the skill under `~/.agents/skills/office-vba` and install the runtime binary by default. Set `OFFICE_VBA_SKIP_BINARY_INSTALL=1` to install only the skill files.

## Binary-only installation

```bash
sh ./install.sh
```

```powershell
./install.ps1
```

Both launch `scripts/install-binary.py`, which uses only the Python standard library.

## Version selection

The default is configured in `manifest.json` and is currently `latest`.

```bash
sh ./install.sh --version latest
sh ./install.sh --version v1.2.3
```

Use an explicit tag for CI, managed environments, or any workflow that requires reproducible runtime versions.

## Updating

The installer does not overwrite an existing binary unless `--force` is supplied:

```bash
sh ./install.sh --force
sh ./install.sh --version v1.2.3 --force
```

## Integrity checks

The installer calculates SHA-256 for every download. It verifies that value against, in order:

1. GitHub's release-asset `digest` field.
2. A matching `<asset>.sha256` or `<asset>.sha256sum` release asset.
3. A release checksum file named `checksums.txt`, `CHECKSUMS.txt`, `SHA256SUMS`, or `sha256sums.txt`.

If upstream provides no checksum, installation succeeds with a warning and records `verified: false` in `bin/VERSION.json`. Supply `--require-checksum` to fail instead.

Downloads are written to a temporary file and moved into place only after size and checksum validation. A failed download does not replace the existing binary.

## Installed metadata

`bin/VERSION.json` records:

- upstream repository and release tag;
- selected platform and asset;
- download URL;
- calculated SHA-256;
- verification status and source;
- installation timestamp.

The `bin/` directory is excluded from Git except for `.gitkeep`.

## Supported platforms

The asset map is defined in `manifest.json`:

- `darwin-arm64`
- `darwin-amd64`
- `linux-amd64`
- `windows-amd64`

Unsupported platforms fail before downloading anything.

## Environment variables

- `OFFICE_VBA_MCP_VERSION`: default release tag when `--version` is omitted.
- `OFFICE_VBA_MCP_REPOSITORY`: alternate `owner/repository` source.
- `OFFICE_VBA_MCP_INSTALL_DIR`: alternate installation directory.
- `OFFICE_VBA_MCP_GITHUB_API_BASE`: alternate GitHub-compatible API base, mainly for mirrors and tests.
- `GITHUB_TOKEN` or `GH_TOKEN`: optional token for GitHub API rate limits.
- `PYTHON`: Python executable used by the shell wrappers.
- `OFFICE_VBA_SKIP_BINARY_INSTALL`: set to `1` to make the skill installer skip the runtime download.

Do not point the installer at an untrusted repository or mirror without explicit user approval.
