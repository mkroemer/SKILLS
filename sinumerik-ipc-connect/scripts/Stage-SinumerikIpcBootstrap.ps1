<#
.SYNOPSIS
Stages profile-approved SINUMERIK IPC bootstrap files over SMB when WinRM transport is closed.
#>
[CmdletBinding()]
param(
    [string]$Profile,
    [string]$ConfigPath,
    [string]$ProfileModulePath,
    [string]$ComputerName,
    [string]$UserName,
    [ValidateRange(1, 65535)]
    [int]$WinRmPort = 5985,
    [string]$SourceRoot = (Get-Location).Path,
    [string]$RemoteRoot,
    [string[]]$Shares,
    [pscredential]$Credential,
    [string]$CredentialStore = (Join-Path $env:LOCALAPPDATA 'SinumerikSkills\WinRM'),
    [switch]$AllowRecoveryRestage
)

$ErrorActionPreference = 'Stop'
$computerWasBound = $PSBoundParameters.ContainsKey('ComputerName')
$userWasBound = $PSBoundParameters.ContainsKey('UserName')
$portWasBound = $PSBoundParameters.ContainsKey('WinRmPort')
$rootWasBound = $PSBoundParameters.ContainsKey('RemoteRoot')
$sharesWereBound = $PSBoundParameters.ContainsKey('Shares')

if ([string]::IsNullOrWhiteSpace($ProfileModulePath)) {
    $ProfileModulePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\sinumerik-ipc-profiles\scripts\SinumerikIpcProfiles.psm1'))
}
if (-not (Test-Path -LiteralPath $ProfileModulePath -PathType Leaf)) { throw 'sinumerik-ipc-profiles is required for bootstrap staging.' }
Import-Module $ProfileModulePath -Force
$profileData = Resolve-SinumerikIpcProfile -Name $Profile -ConfigPath $ConfigPath
if (-not $profileData.bootstrap) { throw "Profile '$($profileData.__profileName)' does not define bootstrap settings." }

if (-not $computerWasBound) { $ComputerName = [string]$profileData.computerName }
if (-not $userWasBound -and $profileData.accounts.administrator) { $UserName = [string]$profileData.accounts.administrator }
if (-not $portWasBound -and $profileData.winrm.port) { $WinRmPort = [int]$profileData.winrm.port }
if (-not $rootWasBound) { $RemoteRoot = [string]$profileData.bootstrap.remoteRoot }
if (-not $sharesWereBound -and $profileData.bootstrap.shares) { $Shares = @($profileData.bootstrap.shares) }

if ([string]::IsNullOrWhiteSpace($ComputerName)) { throw 'The profile does not define computerName.' }
if ([string]::IsNullOrWhiteSpace($UserName)) { $UserName = (Read-Host 'IPC administrator account').Trim() }
if ([string]::IsNullOrWhiteSpace($RemoteRoot)) { throw 'The profile does not define bootstrap.remoteRoot.' }
$remoteMatch = [regex]::Match($RemoteRoot, '^(?<drive>[A-Za-z]):\\(?<relative>.+)$')
if (-not $remoteMatch.Success) { throw 'bootstrap.remoteRoot must be an absolute drive path below the drive root.' }
if (-not $Shares -or $Shares.Count -eq 0) {
    $driveLetter = $remoteMatch.Groups['drive'].Value.ToUpperInvariant()
    $Shares = @($driveLetter, "$driveLetter`$")
}

$sourceRootFull = [IO.Path]::GetFullPath($SourceRoot).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
) + [IO.Path]::DirectorySeparatorChar
$copies = @()
foreach ($mapping in @($profileData.bootstrap.files)) {
    $sourceRelative = [string]$mapping.source
    $destinationRelative = [string]$mapping.destination
    if ([string]::IsNullOrWhiteSpace($sourceRelative) -or [string]::IsNullOrWhiteSpace($destinationRelative)) {
        throw 'Every bootstrap file mapping requires source and destination.'
    }
    if ([IO.Path]::IsPathRooted($destinationRelative) -or $destinationRelative -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Unsafe bootstrap destination: $destinationRelative"
    }
    $source = [IO.Path]::GetFullPath((Join-Path $sourceRootFull $sourceRelative))
    if (-not $source.StartsWith($sourceRootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Bootstrap source escapes SourceRoot: $sourceRelative"
    }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Approved bootstrap source is missing: $source" }
    $copies += [pscustomobject]@{ Source = $source; Destination = $destinationRelative }
}
if ($copies.Count -eq 0) { throw 'The selected profile contains no bootstrap files.' }

if (Test-NetConnection -ComputerName $ComputerName -Port $WinRmPort -InformationLevel Quiet) {
    throw "TCP $WinRmPort is already reachable on '$ComputerName'. Diagnose authentication with Connect-SinumerikIpc.ps1 instead of restaging bootstrap files."
}
if (-not (Test-NetConnection -ComputerName $ComputerName -Port 445 -InformationLevel Quiet)) {
    throw "Neither WinRM nor SMB is reachable on '$ComputerName'. Generate an interactive paste block or repair the approved network path."
}
if (-not $Credential) {
    $credentialLeaf = (($ComputerName + '-' + $UserName) -replace '[^A-Za-z0-9_.-]', '_') + '.credential.xml'
    $credentialPath = Join-Path $CredentialStore $credentialLeaf
    if (Test-Path -LiteralPath $credentialPath -PathType Leaf) {
        try {
            $savedCredential = Import-Clixml -LiteralPath $credentialPath
            if ($savedCredential -isnot [pscredential]) { throw 'The file does not contain a PSCredential.' }
            $Credential = $savedCredential
        }
        catch {
            Write-Warning "The protected WinRM credential could not be reused for SMB: $($_.Exception.Message)"
        }
    }
}
if (-not $Credential) {
    $Credential = Get-Credential -UserName $UserName -Message "Enter the approved SMB credential for $ComputerName"
    if (-not $Credential) { throw 'Credential entry was cancelled.' }
}
$credentialAccount = ((($Credential.UserName -split '\\')[-1]) -split '@')[0]
$selectedAccount = ((($UserName -split '\\')[-1]) -split '@')[0]
if ($credentialAccount -ine $selectedAccount) {
    throw "Credential account '$($Credential.UserName)' does not match selected account '$UserName'."
}

$relativeRoot = $remoteMatch.Groups['relative'].Value.Trim('\')
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

$errors = @()
$completed = $false
foreach ($share in $Shares) {
    $driveName = 'I' + [guid]::NewGuid().ToString('N').Substring(0, 7)
    try {
        New-PSDrive -Name $driveName -PSProvider FileSystem -Root "\\$ComputerName\$share" -Credential $Credential -ErrorAction Stop | Out-Null
        $destinationRoot = Join-Path "$driveName`:\" $relativeRoot
        New-Item -ItemType Directory -Path $destinationRoot -Force -ErrorAction Stop | Out-Null
        if (-not $AllowRecoveryRestage -and (
            (Test-Path -LiteralPath (Join-Path $destinationRoot $stateName) -PathType Leaf) -or
            (Test-Path -LiteralPath (Join-Path $destinationRoot $revertName) -PathType Leaf)
        )) {
            throw 'Existing bootstrap state was found. Verify/reconcile it first; use -AllowRecoveryRestage only for an approved recovery.'
        }

        foreach ($copy in $copies) {
            $destination = Join-Path $destinationRoot $copy.Destination
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $copy.Source -Destination $destination -Force -ErrorAction Stop
            $sourceHash = (Get-FileHash -LiteralPath $copy.Source -Algorithm SHA256).Hash
            $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
            if ($sourceHash -ne $destinationHash) { throw "SHA-256 mismatch after copying $($copy.Destination)." }
            [pscustomobject]@{ Share = $share; Destination = (Join-Path $RemoteRoot $copy.Destination); SHA256 = $sourceHash }
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
if (-not $completed) { throw "SMB was reachable but staging failed: $($errors -join ' | ')." }

$command = New-SinumerikIpcBootstrapCommand -Profile $profileData
Write-Host 'Staging and SHA-256 verification succeeded.' -ForegroundColor Green
Write-Host 'Through the approved interactive method, open an elevated PowerShell on the IPC and run:' -ForegroundColor Yellow
Write-Host '  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force'
Write-Host "  $command"
