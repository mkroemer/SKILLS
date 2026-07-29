# Command reference

All examples use the portable Python wrapper. Native MCP tools accept the equivalent arguments.

## Diagnose installation

```bash
python3 scripts/office-vba.py doctor
python3 scripts/office-vba.py doctor --json
```

Checks that the upstream binary can start and exposes `vba_list`, `vba_read`, `vba_write`, and `vba_run`.

## List modules and procedures

```bash
python3 scripts/office-vba.py list /absolute/path/Workbook.xlsm
```

MCP call:

```json
{"name":"vba_list","arguments":{"file_path":"/absolute/path/Workbook.xlsm"}}
```

## Extract source

```bash
python3 scripts/office-vba.py read /absolute/path/Deck.pptm --output-dir /absolute/path/vba_src
python3 scripts/office-vba.py read /absolute/path/Deck.pptm --module Module1
```

MCP arguments:

```json
{
  "file_path": "/absolute/path/Deck.pptm",
  "output_dir": "/absolute/path/vba_src",
  "module_name": "Module1"
}
```

`output_dir` and `module_name` are optional. The upstream default output directory is `vba_src/` next to the Office file.

## Write source

```bash
python3 scripts/office-vba.py write /absolute/path/Deck.pptm \
  --input-dir /absolute/path/vba_src \
  --yes
```

MCP call:

```json
{
  "name": "vba_write",
  "arguments": {
    "file_path": "/absolute/path/Deck.pptm",
    "input_dir": "/absolute/path/vba_src"
  }
}
```

The wrapper requires `--yes`, confirms that `.bas` or `.cls` source files exist, and checks that the expected sibling `.bak` file exists after writing.

## Run a macro

```bash
python3 scripts/office-vba.py run /absolute/path/Deck.pptm Module1.Main --yes
```

MCP call:

```json
{
  "name": "vba_run",
  "arguments": {
    "file_path": "/absolute/path/Deck.pptm",
    "macro_name": "Module1.Main"
  }
}
```

The host application must be running with the target file open. Execution support is host- and platform-dependent.

## Environment variables

- `OFFICE_VBA_MCP`: absolute path to the upstream MCP binary.
- `PYTHON`: Python executable used by the shell wrappers.
- `OFFICE_VBA_MCP_INSTALL_DIR`: installer destination; defaults to `bin/` inside the skill.
- `OFFICE_VBA_MCP_RELEASE_BASE_URL`: alternative release download base URL.
- `AGENT_SKILLS_DIR`: alternative global Agent Skills directory.
