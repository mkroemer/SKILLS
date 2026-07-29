$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$DestDir = if ($env:OFFICE_VBA_MCP_INSTALL_DIR) { $env:OFFICE_VBA_MCP_INSTALL_DIR } else { Join-Path $Root "bin" }
$Python = if ($env:PYTHON) { $env:PYTHON } elseif (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" } else { "python" }
$Installer = Join-Path $Root "scripts/install-binary.py"

& $Python $Installer --install-dir $DestDir @args
exit $LASTEXITCODE
