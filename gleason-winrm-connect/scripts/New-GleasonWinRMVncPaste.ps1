<#
.SYNOPSIS
Builds a VNC clipboard block from the repository-approved scoped setup files.
#>
[CmdletBinding()]
param(
    [string]$IpcIp = '192.168.214.241',
    [string]$RemoteAddress = '192.168.214.0/24',
    [string]$OutputPath = (Join-Path $env:TEMP 'gleason-winrm-vnc-bootstrap.txt'),
    [switch]$AllowRecoveryRestage
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
$files = @(
    [pscustomobject]@{ Name = 'setup_gleason_ipc.ps1'; Path = Join-Path $repoRoot 'scripts\setup_gleason_ipc.ps1' },
    [pscustomobject]@{ Name = 'Gleason.IpcSetup.psm1'; Path = Join-Path $repoRoot 'scripts\Gleason.IpcSetup.psm1' }
)

$encodedEntries = foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file.Path -PathType Leaf)) { throw "Missing approved setup file: $($file.Path)" }
    [pscustomobject]@{
        Name = $file.Name
        Base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.Path))
        SHA256 = (Get-FileHash -LiteralPath $file.Path -Algorithm SHA256).Hash
    }
}

$entryText = ($encodedEntries | ForEach-Object {
    "    @{ Name = '$($_.Name)'; SHA256 = '$($_.SHA256)'; Base64 = '$($_.Base64)' }"
}) -join ",`r`n"

$content = @"
`$ErrorActionPreference = 'Stop'
`$root = 'D:\OEM\Adapter'
New-Item -ItemType Directory -Path `$root -Force | Out-Null
`$allowRecoveryRestage = `$$($AllowRecoveryRestage.IsPresent.ToString().ToLowerInvariant())
`$setupState = Join-Path `$root 'gleason_ipc_setup_state.json'
`$revertScript = Join-Path `$root 'revert_gleason_ipc_setup.ps1'
if (-not `$allowRecoveryRestage -and (
    (Test-Path -LiteralPath `$setupState -PathType Leaf) -or
    (Test-Path -LiteralPath `$revertScript -PathType Leaf)
)) {
    throw 'Existing bootstrap state was found. Verify/reconcile it instead of overwriting setup files.'
}
`$files = @(
$entryText
)
foreach (`$file in `$files) {
    `$path = Join-Path `$root `$file.Name
    [IO.File]::WriteAllBytes(`$path, [Convert]::FromBase64String(`$file.Base64))
    `$actual = (Get-FileHash -LiteralPath `$path -Algorithm SHA256).Hash
    if (`$actual -ne `$file.SHA256) { throw "SHA-256 mismatch for `$path" }
}
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& (Join-Path `$root 'setup_gleason_ipc.ps1') -IpcIp '$IpcIp' -RemoteAddress '$RemoteAddress'
"@

$parent = Split-Path -Parent $OutputPath
if ([string]::IsNullOrWhiteSpace($parent)) { $parent = (Get-Location).Path }
if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
[IO.File]::WriteAllText($OutputPath, $content, (New-Object Text.UTF8Encoding($false)))

Write-Host "Created VNC clipboard block: $OutputPath" -ForegroundColor Green
Write-Host "Review IpcIp '$IpcIp' and RemoteAddress '$RemoteAddress', then paste the entire file into an elevated PowerShell window on the IPC."
