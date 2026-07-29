[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$skillRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $skillRoot
$profileSkill = Join-Path $repoRoot 'sinumerik-ipc-profiles'
$configSource = Join-Path $profileSkill 'examples\ipc-profiles.example.json'
$profileModule = Join-Path $profileSkill 'scripts\SinumerikIpcProfiles.psm1'
$pasteScript = Join-Path $skillRoot 'scripts\New-SinumerikIpcBootstrapPaste.ps1'
$connectScript = Join-Path $skillRoot 'scripts\Connect-SinumerikIpc.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('sinumerik-ipc-connect-test-' + [guid]::NewGuid().ToString('N'))

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

try {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'scripts') -Force | Out-Null
    $configPath = Join-Path $testRoot 'profiles.json'
    Copy-Item -LiteralPath $configSource -Destination $configPath
    [IO.File]::WriteAllText((Join-Path $testRoot 'scripts\setup_ipc.ps1'), "param()`r`n", (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $testRoot 'scripts\IpcSetup.psm1'), '', (New-Object Text.UTF8Encoding($false)))

    $outputPath = Join-Path $testRoot 'paste.txt'
    & $pasteScript -Profile example-ipc -ConfigPath $configPath -ProfileModulePath $profileModule -SourceRoot $testRoot -OutputPath $outputPath
    $content = [IO.File]::ReadAllText($outputPath)
    Assert-True ($content.Contains('setup_ipc.ps1')) 'The paste block should contain the approved entry script.'
    Assert-True ($content.Contains('192.0.2.10')) 'The paste block should contain the configured target.'
    Assert-True ($content.Contains('SHA-256 mismatch')) 'The paste block should verify staged hashes.'

    $credentialStore = Join-Path $testRoot 'credentials'
    & $connectScript -Profile example-ipc -ConfigPath $configPath -ProfileModulePath $profileModule -CredentialStore $credentialStore -ForgetCredential
    Assert-True (-not (Test-Path -LiteralPath $credentialStore)) 'ForgetCredential should not contact the IPC or create a credential store.'

    Write-Host 'SINUMERIK IPC connection tests passed.' -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
