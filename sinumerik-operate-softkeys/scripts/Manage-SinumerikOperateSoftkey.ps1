<#
.SYNOPSIS
Prompts for a managed SINUMERIK Operate softkey and applies it through WinRM or stages it through SMB.
#>
[CmdletBinding()]
param(
    [string]$ComputerName,
    [ValidateSet('Inspect', 'Add', 'Update', 'Delete')]
    [string]$Action,
    [System.Management.Automation.PSCredential]$Credential,
    [ValidateRange(1, 65535)]
    [int]$WinRmPort = 5985,
    [switch]$UseSsl,
    [string]$RemoteStagingRoot = 'D:\OEM\Temp\OperateSoftkeys',
    [string]$MotionControlRoot = 'C:\ProgramData\Siemens\MotionControl',
    [string]$OwnershipRoot = 'C:\ProgramData\SinumerikOperateSoftkeys'
)

$ErrorActionPreference = 'Stop'
$applyScript = Join-Path $PSScriptRoot 'Set-SinumerikOperateSoftkey.ps1'

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

function ConvertTo-SingleQuotedLiteral {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

if (-not (Test-Path -LiteralPath $applyScript -PathType Leaf)) { throw "Softkey apply helper is missing: $applyScript" }
if (-not $ComputerName) { $ComputerName = (Read-Host 'IPC host or IPv4 address').Trim() }
if ([string]::IsNullOrWhiteSpace($ComputerName)) { throw 'IPC host or IPv4 address is required.' }
if (-not $Action) { $Action = Read-DefaultValue 'Action (Inspect/Add/Update/Delete)' 'Inspect' }
if ($Action -notin @('Inspect', 'Add', 'Update', 'Delete')) { throw "Unsupported action '$Action'." }
$stagingRootMatch = [regex]::Match($RemoteStagingRoot, '^(?<drive>[A-Za-z]):\\(?<relative>.+)$')
if (-not $stagingRootMatch.Success) { throw 'RemoteStagingRoot must be an absolute drive path below the drive root.' }
if (-not [IO.Path]::IsPathRooted($MotionControlRoot) -or -not [IO.Path]::IsPathRooted($OwnershipRoot)) { throw 'MotionControlRoot and OwnershipRoot must be absolute paths.' }

$plan = [ordered]@{ action = $Action }
$localLogo = $null
if ($Action -ne 'Inspect') {
    $label = Read-Host 'Softkey label / machine-safe area ID (letters, digits, underscore; no spaces)'
    if ($label -notmatch '^[A-Za-z][A-Za-z0-9_]{0,63}$') { throw 'The label is not a machine-safe area ID. Localized labels require reviewed language resources.' }
    $plan.label = $label
}
if ($Action -in @('Add', 'Update')) {
    $localLogo = Read-Host 'Local PNG icon path'
    if (-not (Test-Path -LiteralPath $localLogo -PathType Leaf)) { throw "Icon not found: $localLogo" }
    if ([IO.Path]::GetExtension($localLogo) -ine '.png') { throw 'Icon must be a PNG file.' }
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
$localStage = Join-Path $env:TEMP "sinumerik-operate-softkey-$transactionId"
New-Item -ItemType Directory -Path $localStage -Force | Out-Null
try {
    $winRmReachable = Test-NetConnection -ComputerName $ComputerName -Port $WinRmPort -InformationLevel Quiet
    if ($winRmReachable) {
        if (-not $Credential) {
            $Credential = Get-Credential -Message "Enter an approved IPC administrator credential for $ComputerName"
            if (-not $Credential) { throw 'Credential entry was cancelled.' }
        }
        $sessionParameters = @{
            ComputerName = $ComputerName
            Credential = $Credential
            Port = $WinRmPort
            ErrorAction = 'Stop'
        }
        if ($UseSsl) { $sessionParameters.UseSSL = $true }

        $session = $null
        try {
            $session = New-PSSession @sessionParameters
            $remoteIdentity = Invoke-Command -Session $session -ScriptBlock {
                $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
                $principal = New-Object Security.Principal.WindowsPrincipal($identity)
                [pscustomobject]@{
                    User = $identity.Name
                    ComputerName = $env:COMPUTERNAME
                    IsAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                }
            }
            if (-not $remoteIdentity.IsAdministrator) { throw "The verified remote identity '$($remoteIdentity.User)' is not an IPC administrator." }

            $remoteStage = Join-Path $RemoteStagingRoot $transactionId
            Invoke-Command -Session $session -ArgumentList $remoteStage -ScriptBlock {
                param($path)
                New-Item -ItemType Directory -Path $path -Force | Out-Null
            }
            $remoteApplyScript = Join-Path $remoteStage 'Set-SinumerikOperateSoftkey.ps1'
            Copy-Item -LiteralPath $applyScript -ToSession $session -Destination $remoteApplyScript -Force
            if ($localLogo) {
                $remoteLogo = Join-Path $remoteStage 'icon.png'
                Copy-Item -LiteralPath $localLogo -ToSession $session -Destination $remoteLogo -Force
                $plan.logo_path = $remoteLogo
            }
            $planPath = New-PlanFile -Plan $plan -Directory $localStage
            Copy-Item -LiteralPath $planPath -ToSession $session -Destination (Join-Path $remoteStage 'softkey-plan.json') -Force

            $hashes = @(
                [pscustomobject]@{ Name = 'Set-SinumerikOperateSoftkey.ps1'; Hash = (Get-FileHash -LiteralPath $applyScript -Algorithm SHA256).Hash },
                [pscustomobject]@{ Name = 'softkey-plan.json'; Hash = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash }
            )
            if ($localLogo) { $hashes += [pscustomobject]@{ Name = 'icon.png'; Hash = (Get-FileHash -LiteralPath $localLogo -Algorithm SHA256).Hash } }
            $remoteHashes = Invoke-Command -Session $session -ArgumentList $remoteStage, ($hashes.Name -join '|') -ScriptBlock {
                param($stage, $nameList)
                foreach ($name in ($nameList -split '\|')) {
                    [pscustomobject]@{
                        Name = $name
                        Hash = (Get-FileHash -LiteralPath (Join-Path $stage $name) -Algorithm SHA256).Hash
                    }
                }
            }
            foreach ($expected in $hashes) {
                $actual = $remoteHashes | Where-Object Name -eq $expected.Name
                if (-not $actual -or $actual.Hash -ne $expected.Hash) { throw "WinRM staging hash mismatch for $($expected.Name)." }
            }

            Invoke-Command -Session $session -ArgumentList $remoteStage, $MotionControlRoot, $OwnershipRoot -ScriptBlock {
                param($stage, $motionRoot, $ownershipRoot)
                & (Join-Path $stage 'Set-SinumerikOperateSoftkey.ps1') `
                    -PlanPath (Join-Path $stage 'softkey-plan.json') `
                    -MotionControlRoot $motionRoot `
                    -OwnershipRoot $ownershipRoot
            }
        }
        catch {
            throw "WinRM is reachable but authentication, authorization, staging, or execution failed. Do not fall back to SMB: $($_.Exception.Message)"
        }
        finally {
            if ($session) {
                if ($remoteStage) {
                    Invoke-Command -Session $session -ArgumentList $remoteStage -ScriptBlock {
                        param($path)
                        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
                    } -ErrorAction SilentlyContinue
                }
                Remove-PSSession -Session $session -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        if (-not (Test-NetConnection -ComputerName $ComputerName -Port 445 -InformationLevel Quiet)) {
            throw "WinRM and SMB are unreachable on '$ComputerName'. Repair the approved management path; no configuration was staged."
        }
        if (-not $Credential) {
            $Credential = Get-Credential -Message "Enter an approved IPC administrator credential for SMB staging on $ComputerName"
            if (-not $Credential) { throw 'Credential entry was cancelled.' }
        }

        $driveLetter = $stagingRootMatch.Groups['drive'].Value.ToUpperInvariant()
        $relativeStagingRoot = $stagingRootMatch.Groups['relative'].Value.Trim('\')
        $shareCandidates = @($driveLetter, "$driveLetter`$")
        $errors = @()
        $staged = $false
        foreach ($share in $shareCandidates) {
            $drive = 'S' + [guid]::NewGuid().ToString('N').Substring(0, 7)
            try {
                New-PSDrive -Name $drive -PSProvider FileSystem -Root "\\$ComputerName\$share" -Credential $Credential -ErrorAction Stop | Out-Null
                $mappedStage = Join-Path "$drive`:\" (Join-Path $relativeStagingRoot $transactionId)
                New-Item -ItemType Directory -Path $mappedStage -Force | Out-Null
                Copy-Item -LiteralPath $applyScript -Destination (Join-Path $mappedStage 'Set-SinumerikOperateSoftkey.ps1') -Force
                if ($localLogo) {
                    Copy-Item -LiteralPath $localLogo -Destination (Join-Path $mappedStage 'icon.png') -Force
                    $plan.logo_path = Join-Path (Join-Path $RemoteStagingRoot $transactionId) 'icon.png'
                }
                $planPath = New-PlanFile -Plan $plan -Directory $localStage
                Copy-Item -LiteralPath $planPath -Destination (Join-Path $mappedStage 'softkey-plan.json') -Force
                foreach ($file in @('Set-SinumerikOperateSoftkey.ps1', 'softkey-plan.json') + $(if ($localLogo) { 'icon.png' })) {
                    $source = if ($file -eq 'Set-SinumerikOperateSoftkey.ps1') { $applyScript } elseif ($file -eq 'icon.png') { $localLogo } else { $planPath }
                    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath (Join-Path $mappedStage $file) -Algorithm SHA256).Hash) { throw "Hash mismatch for $file." }
                }
                $staged = $true
                break
            }
            catch {
                $errors += "${share}: $($_.Exception.Message)"
            }
            finally {
                Remove-PSDrive -Name $drive -Force -ErrorAction SilentlyContinue
            }
        }
        if (-not $staged) { throw "SMB staging failed: $($errors -join ' | ')" }

        $ipcStage = Join-Path $RemoteStagingRoot $transactionId
        $applyLiteral = ConvertTo-SingleQuotedLiteral (Join-Path $ipcStage 'Set-SinumerikOperateSoftkey.ps1')
        $planLiteral = ConvertTo-SingleQuotedLiteral (Join-Path $ipcStage 'softkey-plan.json')
        $motionLiteral = ConvertTo-SingleQuotedLiteral $MotionControlRoot
        $ownershipLiteral = ConvertTo-SingleQuotedLiteral $OwnershipRoot
        $stageLiteral = ConvertTo-SingleQuotedLiteral $ipcStage
        Write-Host 'WinRM is unavailable. Files were hash-verified through SMB.' -ForegroundColor Yellow
        Write-Host 'Through the approved interactive remote desktop method, open an elevated PowerShell on the IPC and run:' -ForegroundColor Yellow
        Write-Host "& $applyLiteral -PlanPath $planLiteral -MotionControlRoot $motionLiteral -OwnershipRoot $ownershipLiteral; if (`$?) { Remove-Item -LiteralPath $stageLiteral -Recurse -Force }"
    }
}
finally {
    Remove-Item -LiteralPath $localStage -Recurse -Force -ErrorAction SilentlyContinue
}

if ($Action -ne 'Inspect') {
    Write-Host 'Restart SINUMERIK Operate only from the interactive HMI session, then verify all existing and changed softkeys.' -ForegroundColor Yellow
}
