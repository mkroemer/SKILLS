$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$TargetRoot = if ($env:AGENT_SKILLS_DIR) { $env:AGENT_SKILLS_DIR } else { Join-Path $HOME ".agents\skills" }
$Target = Join-Path $TargetRoot "office-vba"

New-Item -ItemType Directory -Force -Path $TargetRoot | Out-Null
if (Test-Path $Target) {
    throw "Target already exists: $Target"
}

Copy-Item -Recurse -Path $Root -Destination $Target
Write-Host "Installed skill: $Target"
