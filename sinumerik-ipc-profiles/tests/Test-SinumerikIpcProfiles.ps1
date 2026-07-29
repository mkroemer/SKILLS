[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$skillRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $skillRoot 'scripts\SinumerikIpcProfiles.psm1'
$examplePath = Join-Path $skillRoot 'examples\ipc-profiles.example.json'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('sinumerik-ipc-profiles-test-' + [guid]::NewGuid().ToString('N'))

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $configPath = Join-Path $testRoot 'profiles.json'
    Copy-Item -LiteralPath $examplePath -Destination $configPath
    Import-Module $modulePath -Force

    $profile = Resolve-SinumerikIpcProfile -ConfigPath $configPath
    Assert-True ($profile.__profileName -eq 'example-ipc') 'The default profile should resolve.'
    Assert-True ($profile.computerName -eq '192.0.2.10') 'The profile target should resolve.'
    Assert-True ((Get-SinumerikIpcProfileNames -ConfigPath $configPath) -contains 'example-ipc') 'Profile listing should include the example.'

    $command = New-SinumerikIpcBootstrapCommand -Profile $profile
    Assert-True ($command.Contains("setup_ipc.ps1")) 'The bootstrap command should contain the entry script.'
    Assert-True ($command.Contains("192.0.2.10")) 'The bootstrap command should expand the target placeholder.'
    Assert-True ($command.Contains("192.0.2.0/24")) 'The bootstrap command should expand the management scope.'

    $invalidPath = Join-Path $testRoot 'invalid.json'
    [IO.File]::WriteAllText(
        $invalidPath,
        '{"schemaVersion":1,"profiles":{"bad":{"computerName":"192.0.2.11","password":"not-allowed"}}}',
        (New-Object Text.UTF8Encoding($false))
    )
    $rejected = $false
    try { Resolve-SinumerikIpcProfile -ConfigPath $invalidPath | Out-Null }
    catch { $rejected = $_.Exception.Message -match 'Secret-bearing property' }
    Assert-True $rejected 'Secret-bearing fields should be rejected.'

    Write-Host 'SINUMERIK IPC profile tests passed.' -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
