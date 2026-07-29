<#
.SYNOPSIS
Builds an interactive clipboard block from profile-approved SINUMERIK IPC bootstrap files.
#>
[CmdletBinding()]
param(
    [string]$Profile,
    [string]$ConfigPath,
    [string]$ProfileModulePath,
    [string]$SourceRoot = (Get-Location).Path,
    [string]$OutputPath = (Join-Path $env:TEMP 'sinumerik-ipc-bootstrap-paste.txt'),
    [switch]$AllowRecoveryRestage
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProfileModulePath)) {
    $ProfileModulePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\sinumerik-ipc-profiles\scripts\SinumerikIpcProfiles.psm1'))
}
if (-not (Test-Path -LiteralPath $ProfileModulePath -PathType Leaf)) { throw 'sinumerik-ipc-profiles is required to generate the bootstrap block.' }
Import-Module $ProfileModulePath -Force
$profileData = Resolve-SinumerikIpcProfile -Name $Profile -ConfigPath $ConfigPath
if (-not $profileData.bootstrap) { throw "Profile '$($profileData.__profileName)' does not define bootstrap settings." }

function ConvertTo-SingleQuotedLiteral {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

$sourceRootFull = [IO.Path]::GetFullPath($SourceRoot).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
) + [IO.Path]::DirectorySeparatorChar
$entries = foreach ($mapping in @($profileData.bootstrap.files)) {
    $sourceRelative = [string]$mapping.source
    $destination = [string]$mapping.destination
    if ([IO.Path]::IsPathRooted($destination) -or $destination -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Unsafe bootstrap destination: $destination"
    }
    $source = [IO.Path]::GetFullPath((Join-Path $sourceRootFull $sourceRelative))
    if (-not $source.StartsWith($sourceRootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Bootstrap source escapes SourceRoot: $sourceRelative"
    }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Approved bootstrap source is missing: $source" }
    [pscustomobject]@{
        Name = $destination
        Base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($source))
        SHA256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    }
}
if (@($entries).Count -eq 0) { throw 'The selected profile contains no bootstrap files.' }

$entryText = (@($entries) | ForEach-Object {
    "    @{ Name = $(ConvertTo-SingleQuotedLiteral $_.Name); SHA256 = '$($_.SHA256)'; Base64 = '$($_.Base64)' }"
}) -join ",`r`n"
$remoteRootLiteral = ConvertTo-SingleQuotedLiteral ([string]$profileData.bootstrap.remoteRoot)
$stateName = [string]$profileData.bootstrap.stateFile
$revertName = [string]$profileData.bootstrap.revertScript
if ([string]::IsNullOrWhiteSpace($stateName) -or [string]::IsNullOrWhiteSpace($revertName)) {
    throw 'bootstrap.stateFile and bootstrap.revertScript are required for safe restaging.'
}
foreach ($marker in @($stateName, $revertName)) {
    if ([IO.Path]::IsPathRooted($marker) -or $marker -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Unsafe bootstrap marker path: $marker"
    }
}
$stateLiteral = ConvertTo-SingleQuotedLiteral $stateName
$revertLiteral = ConvertTo-SingleQuotedLiteral $revertName
$bootstrapCommand = New-SinumerikIpcBootstrapCommand -Profile $profileData
$allowRecovery = $AllowRecoveryRestage.IsPresent.ToString().ToLowerInvariant()

$content = @"
`$ErrorActionPreference = 'Stop'
`$root = $remoteRootLiteral
New-Item -ItemType Directory -Path `$root -Force | Out-Null
`$allowRecoveryRestage = `$$allowRecovery
`$setupState = Join-Path `$root $stateLiteral
`$revertScript = Join-Path `$root $revertLiteral
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
    New-Item -ItemType Directory -Path (Split-Path -Parent `$path) -Force | Out-Null
    [IO.File]::WriteAllBytes(`$path, [Convert]::FromBase64String(`$file.Base64))
    `$actual = (Get-FileHash -LiteralPath `$path -Algorithm SHA256).Hash
    if (`$actual -ne `$file.SHA256) { throw "SHA-256 mismatch for `$path" }
}
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
$bootstrapCommand
"@

$parent = Split-Path -Parent $OutputPath
if ([string]::IsNullOrWhiteSpace($parent)) { $parent = (Get-Location).Path }
New-Item -ItemType Directory -Path $parent -Force | Out-Null
[IO.File]::WriteAllText($OutputPath, $content, (New-Object Text.UTF8Encoding($false)))

Write-Host "Created interactive bootstrap block: $OutputPath" -ForegroundColor Green
Write-Host "Review profile '$($profileData.__profileName)', file hashes, and the generated command before pasting it into an elevated PowerShell window on the IPC." -ForegroundColor Yellow
