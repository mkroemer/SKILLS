[CmdletBinding()]
param(
    [ValidateSet('Generic', 'Gleason')]
    [string]$Preset = 'Generic',
    [string]$DestinationPath,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($DestinationPath)) {
    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        throw 'APPDATA is unavailable. Pass -DestinationPath explicitly.'
    }
    $DestinationPath = Join-Path $env:APPDATA 'SinumerikSkills\ipc-profiles.json'
}

$sourceName = if ($Preset -eq 'Gleason') { 'gleason.ipc-profiles.example.json' } else { 'ipc-profiles.example.json' }
$sourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) "examples\$sourceName"
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Preset file not found: $sourcePath" }
if ((Test-Path -LiteralPath $DestinationPath) -and -not $Force) {
    throw "Profile file already exists: $DestinationPath. Review it or pass -Force to replace it."
}

$parent = Split-Path -Parent $DestinationPath
if ([string]::IsNullOrWhiteSpace($parent)) { $parent = (Get-Location).Path }
New-Item -ItemType Directory -Path $parent -Force | Out-Null
Copy-Item -LiteralPath $sourcePath -Destination $DestinationPath -Force

Import-Module (Join-Path $PSScriptRoot 'SinumerikIpcProfiles.psm1') -Force
$profile = Resolve-SinumerikIpcProfile -ConfigPath $DestinationPath
Write-Host "Initialized SINUMERIK IPC profiles from the $Preset preset: $DestinationPath" -ForegroundColor Green
Write-Host "Default profile: $($profile.__profileName). Review all machine and account values before use." -ForegroundColor Yellow
