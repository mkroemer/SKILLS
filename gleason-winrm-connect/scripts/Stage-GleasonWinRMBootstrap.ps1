<#
.SYNOPSIS
Stages the approved scoped IPC setup files over SMB when WinRM is unavailable.
#>
[CmdletBinding()]
param(
    [string]$ComputerName,
    [string]$RemoteRoot = 'OEM\Adapter',
    [ValidateSet('GLEASON')]
    [string]$UserName = 'GLEASON',
    [switch]$AllowRecoveryRestage
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))

if (-not $ComputerName) {
    $ComputerName = Read-Host 'IPC host or IPv4 address [192.168.214.241]'
    if ([string]::IsNullOrWhiteSpace($ComputerName)) { $ComputerName = '192.168.214.241' }
}

$sources = @(
    [pscustomobject]@{
        Source = Join-Path $repoRoot 'scripts\setup_gleason_ipc.ps1'
        Destination = 'setup_gleason_ipc.ps1'
    },
    [pscustomobject]@{
        Source = Join-Path $repoRoot 'scripts\Gleason.IpcSetup.psm1'
        Destination = 'Gleason.IpcSetup.psm1'
    },
    [pscustomobject]@{
        Source = Join-Path $PSScriptRoot 'run_gleason_ipc_setup.cmd'
        Destination = 'run_gleason_ipc_setup.cmd'
    }
)

foreach ($item in $sources) {
    if (-not (Test-Path -LiteralPath $item.Source -PathType Leaf)) {
        throw "Required approved source file is missing: $($item.Source)"
    }
}

if (Test-NetConnection -ComputerName $ComputerName -Port 5985 -InformationLevel Quiet) {
    throw "TCP 5985 is already reachable on '$ComputerName'. Diagnose authentication with Connect-GleasonWinRM.ps1 instead of restaging bootstrap files."
}
if (-not (Test-NetConnection -ComputerName $ComputerName -Port 445 -InformationLevel Quiet)) {
    throw "Neither WinRM nor SMB is reachable on '$ComputerName'. Use New-GleasonWinRMVncPaste.ps1 and VNC, or correct the approved machine-network path."
}

$credential = Get-Credential -UserName $UserName -Message "Enter the GLEASON SMB credential for $ComputerName"
if (-not $credential) { throw 'Credential entry was cancelled.' }
$credentialAccount = (($credential.UserName -split '\\')[-1] -split '@')[0]
if ($credentialAccount -ine $UserName) {
    throw "Credential account '$($credential.UserName)' does not match required account '$UserName'."
}

$errors = @()
$completed = $false
foreach ($share in @('D', 'D$')) {
    $driveName = 'G' + [guid]::NewGuid().ToString('N').Substring(0, 7)
    try {
        New-PSDrive -Name $driveName -PSProvider FileSystem -Root "\\$ComputerName\$share" -Credential $credential -ErrorAction Stop | Out-Null
        $destinationRoot = "$driveName`:\$RemoteRoot"
        New-Item -ItemType Directory -Path $destinationRoot -Force -ErrorAction Stop | Out-Null

        $setupState = Join-Path $destinationRoot 'gleason_ipc_setup_state.json'
        $revertScript = Join-Path $destinationRoot 'revert_gleason_ipc_setup.ps1'
        if (-not $AllowRecoveryRestage -and (
            (Test-Path -LiteralPath $setupState -PathType Leaf) -or
            (Test-Path -LiteralPath $revertScript -PathType Leaf)
        )) {
            throw 'Existing bootstrap state was found. Verify/reconcile it first; use -AllowRecoveryRestage only for a specifically approved recovery.'
        }

        foreach ($item in $sources) {
            $destination = Join-Path $destinationRoot $item.Destination
            Copy-Item -LiteralPath $item.Source -Destination $destination -Force -ErrorAction Stop
            $sourceHash = (Get-FileHash -LiteralPath $item.Source -Algorithm SHA256).Hash
            $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
            if ($sourceHash -ne $destinationHash) { throw "SHA-256 mismatch after copying $($item.Destination)." }
            [pscustomobject]@{ Share = $share; Destination = "D:\$RemoteRoot\$($item.Destination)"; SHA256 = $sourceHash }
        }

        $completed = $true
        break
    }
    catch {
        $errors += "${share}: $($_.Exception.Message)"
    }
    finally {
        Remove-PSDrive -Name $driveName -Force -ErrorAction SilentlyContinue
    }
}

if (-not $completed) {
    throw "SMB was reachable but staging failed: $($errors -join ' | '). Generate a VNC block with New-GleasonWinRMVncPaste.ps1."
}

Write-Host 'Staging and SHA-256 verification succeeded.' -ForegroundColor Green
Write-Host 'Through VNC, open an elevated CMD on the IPC and run:' -ForegroundColor Yellow
Write-Host '  D:\OEM\Adapter\run_gleason_ipc_setup.cmd'
