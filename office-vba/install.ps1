$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$DestDir = if ($env:OFFICE_VBA_MCP_INSTALL_DIR) { $env:OFFICE_VBA_MCP_INSTALL_DIR } else { Join-Path $Root "bin" }
$BaseUrl = if ($env:OFFICE_VBA_MCP_RELEASE_BASE_URL) { $env:OFFICE_VBA_MCP_RELEASE_BASE_URL } else { "https://github.com/miclip/office-vba-mcp/releases/latest/download" }
$Asset = "office-vba-mcp-windows-amd64.exe"
$Destination = Join-Path $DestDir "office-vba-mcp.exe"
$Temporary = "$Destination.download"

New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
try {
    Invoke-WebRequest -Uri "$BaseUrl/$Asset" -OutFile $Temporary
    Move-Item -Force $Temporary $Destination
} finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $Temporary
}

Write-Host "Installed: $Destination"
$PreviousBinary = $env:OFFICE_VBA_MCP
$env:OFFICE_VBA_MCP = $Destination
try {
    & (Join-Path $Root "scripts/office-vba.ps1") doctor
    exit $LASTEXITCODE
} finally {
    $env:OFFICE_VBA_MCP = $PreviousBinary
}
