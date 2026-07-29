<#
.SYNOPSIS
Prompts for a generic Operate softkey and applies it through WinRM or stages it through SMB.
#>
[CmdletBinding()]
param(
    [string]$ComputerName,
    [ValidateSet('Inspect', 'Add', 'Update', 'Delete')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'
$skillRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
$connectionScript = Join-Path $repoRoot '.opencode\skills\gleason-winrm-connect\scripts\Connect-GleasonWinRM.ps1'
$applyScript = Join-Path $PSScriptRoot 'Set-GleasonOperateSoftkey.ps1'

function Read-DefaultValue {
    param([string]$Prompt, [string]$Default)
    $value = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value.Trim()
}

function New-PlanFile {
    param([Collections.IDictionary]$Plan, [string]$Directory)
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $path = Join-Path $Directory 'softkey-plan.json'
    $Plan | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

if (-not (Test-Path -LiteralPath $connectionScript -PathType Leaf)) { throw "WinRM skill helper is missing: $connectionScript" }
if (-not (Test-Path -LiteralPath $applyScript -PathType Leaf)) { throw "Softkey apply helper is missing: $applyScript" }
if (-not $ComputerName) { $ComputerName = Read-DefaultValue 'IPC host or IPv4 address' '192.168.214.241' }
if (-not $Action) { $Action = Read-DefaultValue 'Action (Inspect/Add/Update/Delete)' 'Inspect' }
if ($Action -notin @('Inspect', 'Add', 'Update', 'Delete')) { throw "Unsupported action '$Action'." }

$plan = [ordered]@{ action = $Action }
$localLogo = $null
if ($Action -ne 'Inspect') {
    $label = Read-Host 'Softkey label / machine-safe area ID (letters, digits, underscore; no spaces)'
    if ($label -notmatch '^[A-Za-z][A-Za-z0-9_]{0,63}$') { throw 'The label is not a machine-safe area ID. Localized labels require reviewed language resources.' }
    $plan.label = $label
}
if ($Action -in @('Add', 'Update')) {
    $localLogo = Read-Host 'Local transparent PNG logo path'
    if (-not (Test-Path -LiteralPath $localLogo -PathType Leaf)) { throw "Logo not found: $localLogo" }
    if ([IO.Path]::GetExtension($localLogo) -ine '.png') { throw 'Logo must be a PNG file.' }
    $plan.program = Read-Host 'Absolute program .exe path on the IPC'
    $plan.arguments = Read-Host 'Program arguments (optional; no double quotes)'
    $plan.window_name = Read-DefaultValue 'Exact managed window title' $label
    if ($plan.program.Contains('"') -or $plan.arguments.Contains('"') -or $plan.window_name.Contains('"')) { throw 'Program, arguments, and window title must not contain double quotes.' }
}

Write-Host ''
Write-Host 'Proposed Operate softkey plan:' -ForegroundColor Cyan
$plan | ConvertTo-Json -Depth 5 | Write-Host
if ($Action -ne 'Inspect') {
    $confirmation = Read-Host "Type APPLY to $Action '$($plan.label)'"
    if ($confirmation -cne 'APPLY') { throw 'Softkey change was not confirmed.' }
}

$transactionId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$localStage = Join-Path $env:TEMP "gleason-softkey-$transactionId"
New-Item -ItemType Directory -Path $localStage -Force | Out-Null
try {
    $winRmReachable = Test-NetConnection -ComputerName $ComputerName -Port 5985 -InformationLevel Quiet
    if ($winRmReachable) {
        $connection = & $connectionScript -ComputerName $ComputerName -UserName GLEASON
        $session = $connection.Session
        if (-not $session) { throw 'The WinRM skill did not return a verified session.' }
        if (-not $connection.RemoteIdentity.IsAdministrator) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue; throw 'The verified GLEASON WinRM identity is not an IPC administrator.' }
        $remoteStage = "D:\OEM\Temp\OperateSoftkeys\$transactionId"
        try {
            Invoke-Command -Session $session -ArgumentList $remoteStage -ScriptBlock { param($path) New-Item -ItemType Directory -Path $path -Force | Out-Null }
            Copy-Item -LiteralPath $applyScript -ToSession $session -Destination (Join-Path $remoteStage 'Set-GleasonOperateSoftkey.ps1') -Force
            if ($localLogo) {
                $remoteLogo = Join-Path $remoteStage 'logo.png'
                Copy-Item -LiteralPath $localLogo -ToSession $session -Destination $remoteLogo -Force
                $plan.logo_path = $remoteLogo
            }
            $planPath = New-PlanFile -Plan $plan -Directory $localStage
            Copy-Item -LiteralPath $planPath -ToSession $session -Destination (Join-Path $remoteStage 'softkey-plan.json') -Force
            $hashes = @(
                [pscustomobject]@{ Name = 'Set-GleasonOperateSoftkey.ps1'; Hash = (Get-FileHash -LiteralPath $applyScript -Algorithm SHA256).Hash },
                [pscustomobject]@{ Name = 'softkey-plan.json'; Hash = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash }
            )
            if ($localLogo) { $hashes += [pscustomobject]@{ Name = 'logo.png'; Hash = (Get-FileHash -LiteralPath $localLogo -Algorithm SHA256).Hash } }
            $remoteHashes = Invoke-Command -Session $session -ArgumentList $remoteStage, ($hashes.Name -join '|') -ScriptBlock {
                param($stage, $nameList)
                foreach ($name in ($nameList -split '\|')) { [pscustomobject]@{ Name = $name; Hash = (Get-FileHash -LiteralPath (Join-Path $stage $name) -Algorithm SHA256).Hash } }
            }
            foreach ($expected in $hashes) {
                $actual = $remoteHashes | Where-Object Name -eq $expected.Name
                if (-not $actual -or $actual.Hash -ne $expected.Hash) { throw "WinRM staging hash mismatch for $($expected.Name)." }
            }
            Invoke-Command -Session $session -ArgumentList $remoteStage -ScriptBlock {
                param($stage)
                & (Join-Path $stage 'Set-GleasonOperateSoftkey.ps1') -PlanPath (Join-Path $stage 'softkey-plan.json')
            }
        }
        finally {
            if ($session) {
                Invoke-Command -Session $session -ArgumentList $remoteStage -ScriptBlock { param($path) Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue } -ErrorAction SilentlyContinue
                Remove-PSSession -Session $session -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        if (-not (Test-NetConnection -ComputerName $ComputerName -Port 445 -InformationLevel Quiet)) {
            throw "WinRM and SMB are unreachable on '$ComputerName'. Repair the approved management path; no configuration was staged."
        }
        $credential = Get-Credential -UserName GLEASON -Message "Enter the GLEASON SMB credential for $ComputerName"
        if (-not $credential) { throw 'Credential entry was cancelled.' }
        $account = (($credential.UserName -split '\\')[-1] -split '@')[0]
        if ($account -ine 'GLEASON') { throw "SMB credential must use GLEASON, not '$($credential.UserName)'." }
        $errors = @()
        $staged = $false
        foreach ($share in @('D', 'D$')) {
            $drive = 'S' + [guid]::NewGuid().ToString('N').Substring(0, 7)
            try {
                New-PSDrive -Name $drive -PSProvider FileSystem -Root "\\$ComputerName\$share" -Credential $credential -ErrorAction Stop | Out-Null
                $remoteStage = "$drive`:\OEM\Temp\OperateSoftkeys\$transactionId"
                New-Item -ItemType Directory -Path $remoteStage -Force | Out-Null
                Copy-Item -LiteralPath $applyScript -Destination (Join-Path $remoteStage 'Set-GleasonOperateSoftkey.ps1') -Force
                if ($localLogo) { Copy-Item -LiteralPath $localLogo -Destination (Join-Path $remoteStage 'logo.png') -Force; $plan.logo_path = "D:\OEM\Temp\OperateSoftkeys\$transactionId\logo.png" }
                $planPath = New-PlanFile -Plan $plan -Directory $localStage
                Copy-Item -LiteralPath $planPath -Destination (Join-Path $remoteStage 'softkey-plan.json') -Force
                foreach ($file in @('Set-GleasonOperateSoftkey.ps1', 'softkey-plan.json') + $(if ($localLogo) { 'logo.png' })) {
                    $source = if ($file -eq 'Set-GleasonOperateSoftkey.ps1') { $applyScript } elseif ($file -eq 'logo.png') { $localLogo } else { $planPath }
                    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath (Join-Path $remoteStage $file) -Algorithm SHA256).Hash) { throw "Hash mismatch for $file." }
                }
                $staged = $true
                break
            }
            catch { $errors += "${share}: $($_.Exception.Message)" }
            finally { Remove-PSDrive -Name $drive -Force -ErrorAction SilentlyContinue }
        }
        if (-not $staged) { throw "SMB staging failed: $($errors -join ' | ')" }
        $ipcStage = "D:\OEM\Temp\OperateSoftkeys\$transactionId"
        Write-Host 'WinRM is unavailable. Files were hash-verified through SMB.' -ForegroundColor Yellow
        Write-Host 'Through VNC, open an elevated PowerShell on the IPC and run:' -ForegroundColor Yellow
        Write-Host "& '$ipcStage\Set-GleasonOperateSoftkey.ps1' -PlanPath '$ipcStage\softkey-plan.json'; if (`$?) { Remove-Item -LiteralPath '$ipcStage' -Recurse -Force }"
    }
}
finally {
    Remove-Item -LiteralPath $localStage -Recurse -Force -ErrorAction SilentlyContinue
}

if ($Action -ne 'Inspect') {
    Write-Host 'Restart SINUMERIK Operate only from the interactive HMI session, then verify all existing and new softkeys.' -ForegroundColor Yellow
}
