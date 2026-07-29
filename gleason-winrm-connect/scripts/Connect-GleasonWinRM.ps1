<#
.SYNOPSIS
Creates a verified Gleason IPC WinRM session with optional DPAPI credential reuse.
#>
[CmdletBinding()]
param(
    [string]$ComputerName,
    [ValidateSet('AUDUSER', 'GLEASON')]
    [string]$UserName,
    [int]$Port = 5985,
    [string]$CredentialStore = (Join-Path $env:LOCALAPPDATA 'Gleason\WinRM'),
    [switch]$NoCredentialStore,
    [switch]$ForgetCredential,
    [switch]$ConfigureTrustedHost,
    [switch]$EnterSession
)

$ErrorActionPreference = 'Stop'

function Read-DefaultValue {
    param([string]$Prompt, [string]$Default)

    $value = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value.Trim()
}

function Select-GleasonUser {
    Write-Host 'Select the IPC account:' -ForegroundColor Cyan
    Write-Host '  1. GLEASON  (administrator; setup/deployment)'
    Write-Host '  2. AUDUSER  (interactive HMI/operator; no elevation assumed)'
    $selection = Read-Host 'Selection [1]'
    if ([string]::IsNullOrWhiteSpace($selection) -or $selection -eq '1') { return 'GLEASON' }
    if ($selection -eq '2') { return 'AUDUSER' }
    throw "Unsupported account selection '$selection'."
}

function Get-CredentialPath {
    param([string]$HostName, [string]$Account, [string]$Store)

    $leaf = (($HostName + '-' + $Account) -replace '[^A-Za-z0-9_.-]', '_') + '.credential.xml'
    return Join-Path $Store $leaf
}

function Assert-SelectedAccount {
    param([pscredential]$Credential)

    $account = ($Credential.UserName -split '\\')[-1]
    $account = ($account -split '@')[0]
    if ($account -ine $UserName) {
        throw "Credential account '$($Credential.UserName)' does not match selected account '$UserName'."
    }
}

function Add-ExactTrustedHost {
    param([string]$HostName)

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw '-ConfigureTrustedHost requires an elevated local PowerShell window.'
    }

    Start-Service WinRM
    $path = 'WSMan:\localhost\Client\TrustedHosts'
    $previous = [string](Get-Item -Path $path -ErrorAction Stop).Value
    $entries = @($previous -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($entries -notcontains $HostName) {
        $updated = (@($entries + $HostName) | Select-Object -Unique) -join ','
        Set-Item -Path $path -Value $updated -Force -ErrorAction Stop
    }

    [pscustomobject]@{
        PreviousTrustedHosts = $previous
        CurrentTrustedHosts = [string](Get-Item -Path $path).Value
    }
}

function Open-VerifiedSession {
    param([pscredential]$Credential)

    Assert-SelectedAccount -Credential $Credential
    $newSessionParameters = @{
        ComputerName = $ComputerName
        Port = $Port
        Credential = $Credential
        Authentication = 'Negotiate'
        ErrorAction = 'Stop'
    }
    $candidate = New-PSSession @newSessionParameters
    try {
        $identity = Invoke-Command -Session $candidate -ErrorAction Stop -ScriptBlock {
            [pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                UserName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
                IsAdministrator = (New-Object Security.Principal.WindowsPrincipal(
                    [Security.Principal.WindowsIdentity]::GetCurrent()
                )).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                SetupStateExists = Test-Path -LiteralPath 'D:\OEM\Adapter\gleason_ipc_setup_state.json' -PathType Leaf
                RevertScriptExists = Test-Path -LiteralPath 'D:\OEM\Adapter\revert_gleason_ipc_setup.ps1' -PathType Leaf
            }
        }
        $remoteAccount = (($identity.UserName -split '\\')[-1] -split '@')[0]
        if ($remoteAccount -ine $UserName) {
            throw "Remote identity '$($identity.UserName)' does not match selected account '$UserName'."
        }
        return [pscustomobject]@{ Session = $candidate; Identity = $identity }
    }
    catch {
        Remove-PSSession -Session $candidate -ErrorAction SilentlyContinue
        throw
    }
}

if (-not $ComputerName) { $ComputerName = Read-DefaultValue 'IPC host or IPv4 address' '192.168.214.241' }
if (-not $UserName) { $UserName = Select-GleasonUser }

if ($ConfigureTrustedHost) {
    $trustChange = Add-ExactTrustedHost -HostName $ComputerName
    Write-Host "TrustedHosts now contains only its prior entries plus '$ComputerName'." -ForegroundColor Yellow
    $trustChange
}

$credentialPath = Get-CredentialPath -HostName $ComputerName -Account $UserName -Store $CredentialStore
if ($ForgetCredential) {
    if (Test-Path -LiteralPath $credentialPath -PathType Leaf) {
        Remove-Item -LiteralPath $credentialPath -Force
        Write-Host "Removed protected credential: $credentialPath"
    }
    else {
        Write-Host "No protected credential exists for $UserName@$ComputerName."
    }
    return
}

if (-not (Test-NetConnection -ComputerName $ComputerName -Port $Port -InformationLevel Quiet)) {
    throw "TCP $Port is not reachable on '$ComputerName'. Do not prompt for a WinRM password yet. Use Stage-GleasonWinRMBootstrap.ps1 only if approved bootstrap is required."
}

$opened = $null
$usedSavedCredential = $false
if (Test-Path -LiteralPath $credentialPath -PathType Leaf) {
    try {
        $savedCredential = Import-Clixml -LiteralPath $credentialPath
        if ($savedCredential -isnot [pscredential]) { throw 'The file does not contain a PSCredential.' }
        $opened = Open-VerifiedSession -Credential $savedCredential
        $usedSavedCredential = $true
    }
    catch {
        Write-Warning "The saved credential could not authenticate: $($_.Exception.Message)"
        Write-Warning 'The protected file was retained. A successful prompted login will replace it.'
    }
}

if (-not $opened) {
    $credential = Get-Credential -UserName $UserName -Message "Enter the $UserName WinRM credential for $ComputerName"
    if (-not $credential) { throw 'Credential entry was cancelled.' }
    $opened = Open-VerifiedSession -Credential $credential

    if (-not $NoCredentialStore) {
        New-Item -ItemType Directory -Path $CredentialStore -Force | Out-Null
        $temporaryCredentialPath = "$credentialPath.$([guid]::NewGuid().ToString('N')).tmp"
        try {
            $credential | Export-Clixml -LiteralPath $temporaryCredentialPath -Force
            Move-Item -LiteralPath $temporaryCredentialPath -Destination $credentialPath -Force
        }
        finally {
            Remove-Item -LiteralPath $temporaryCredentialPath -Force -ErrorAction SilentlyContinue
        }
        Write-Host "Saved a DPAPI-protected credential for the current Windows user and machine: $credentialPath" -ForegroundColor Green
    }
}

$result = [pscustomobject]@{
    ComputerName = $ComputerName
    Account = $UserName
    UsedSavedCredential = $usedSavedCredential
    CredentialStored = (-not $NoCredentialStore) -and (Test-Path -LiteralPath $credentialPath -PathType Leaf)
    RemoteIdentity = $opened.Identity
    Session = $opened.Session
}

Write-Host "Verified WinRM as $($opened.Identity.UserName) on $($opened.Identity.ComputerName)." -ForegroundColor Green
if ($EnterSession) {
    try { Enter-PSSession -Session $opened.Session }
    finally { Remove-PSSession -Session $opened.Session -ErrorAction SilentlyContinue }
}
else {
    $result
}
