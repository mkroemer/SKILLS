<#
.SYNOPSIS
Creates a verified SINUMERIK IPC WinRM session with optional profile defaults and DPAPI credential reuse.
#>
[CmdletBinding()]
param(
    [string]$Profile,
    [string]$ConfigPath,
    [string]$ProfileModulePath,
    [string]$ComputerName,
    [string]$Role,
    [string]$UserName,
    [ValidateRange(1, 65535)]
    [int]$Port = 5985,
    [ValidateSet('Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos')]
    [string]$Authentication = 'Negotiate',
    [switch]$UseSsl,
    [string]$CredentialStore = (Join-Path $env:LOCALAPPDATA 'SinumerikSkills\WinRM'),
    [switch]$NoCredentialStore,
    [switch]$ForgetCredential,
    [switch]$ConfigureTrustedHost,
    [switch]$EnterSession
)

$ErrorActionPreference = 'Stop'
$explicitProfileRequest = $PSBoundParameters.ContainsKey('Profile') -or $PSBoundParameters.ContainsKey('ConfigPath')
$computerNameWasBound = $PSBoundParameters.ContainsKey('ComputerName')
$roleWasBound = $PSBoundParameters.ContainsKey('Role')
$userNameWasBound = $PSBoundParameters.ContainsKey('UserName')
$portWasBound = $PSBoundParameters.ContainsKey('Port')
$authenticationWasBound = $PSBoundParameters.ContainsKey('Authentication')
$useSslWasBound = $PSBoundParameters.ContainsKey('UseSsl')

function Import-ProfileModule {
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($ProfileModulePath)) { $candidates += $ProfileModulePath }
    $candidates += [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\sinumerik-ipc-profiles\scripts\SinumerikIpcProfiles.psm1'))
    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            Import-Module $candidate -Force
            return $true
        }
    }
    if ($explicitProfileRequest) { throw 'sinumerik-ipc-profiles is required when -Profile or -ConfigPath is used.' }
    return $false
}

function Get-CredentialPath {
    param([string]$HostName, [string]$Account, [string]$Store)
    $leaf = (($HostName + '-' + $Account) -replace '[^A-Za-z0-9_.-]', '_') + '.credential.xml'
    return Join-Path $Store $leaf
}

function Get-AccountLeaf {
    param([string]$Account)
    return ((($Account -split '\\')[-1]) -split '@')[0]
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
        Set-Item -Path $path -Value ((@($entries + $HostName) | Select-Object -Unique) -join ',') -Force -ErrorAction Stop
    }
    [pscustomobject]@{
        PreviousTrustedHosts = $previous
        CurrentTrustedHosts = [string](Get-Item -Path $path).Value
    }
}

$profileData = $null
if (Import-ProfileModule) {
    $profileData = Resolve-SinumerikIpcProfile -Name $Profile -ConfigPath $ConfigPath -AllowMissing:(-not $explicitProfileRequest)
}
if ($profileData) {
    if (-not $computerNameWasBound) { $ComputerName = [string]$profileData.computerName }
    if (-not $roleWasBound -and -not $userNameWasBound) { $Role = [string]$profileData.defaultRole }
    if (-not $portWasBound -and $profileData.winrm.port) { $Port = [int]$profileData.winrm.port }
    if (-not $authenticationWasBound -and $profileData.winrm.authentication) { $Authentication = [string]$profileData.winrm.authentication }
    if (-not $useSslWasBound -and $profileData.winrm.useSsl) { $UseSsl = [bool]$profileData.winrm.useSsl }
}

if ([string]::IsNullOrWhiteSpace($ComputerName)) { $ComputerName = (Read-Host 'IPC host or IPv4 address').Trim() }
if ([string]::IsNullOrWhiteSpace($ComputerName)) { throw 'IPC host or IPv4 address is required.' }

if ([string]::IsNullOrWhiteSpace($UserName) -and $profileData -and $profileData.accounts) {
    if ([string]::IsNullOrWhiteSpace($Role)) {
        $roles = @($profileData.accounts.PSObject.Properties | ForEach-Object { $_.Name })
        Write-Host 'Configured IPC accounts:' -ForegroundColor Cyan
        for ($index = 0; $index -lt $roles.Count; $index++) {
            $account = $profileData.accounts.PSObject.Properties[$roles[$index]].Value
            Write-Host "  $($index + 1). $($roles[$index]) ($account)"
        }
        $selection = Read-Host 'Selection [1]'
        if ([string]::IsNullOrWhiteSpace($selection)) { $selection = '1' }
        if ($selection -notmatch '^\d+$' -or [int]$selection -lt 1 -or [int]$selection -gt $roles.Count) {
            throw "Unsupported account selection '$selection'."
        }
        $Role = $roles[[int]$selection - 1]
    }
    $roleProperty = $profileData.accounts.PSObject.Properties | Where-Object Name -eq $Role | Select-Object -First 1
    if (-not $roleProperty) { throw "Role '$Role' is not defined in profile '$($profileData.__profileName)'." }
    $UserName = [string]$roleProperty.Value
}
if ([string]::IsNullOrWhiteSpace($UserName)) { $UserName = (Read-Host 'IPC account name').Trim() }
if ([string]::IsNullOrWhiteSpace($UserName)) { throw 'IPC account name is required.' }

if ($ConfigureTrustedHost) {
    $trustChange = Add-ExactTrustedHost -HostName $ComputerName
    Write-Host "TrustedHosts now contains only its prior entries plus '$ComputerName'." -ForegroundColor Yellow
    $trustChange
}

$credentialPath = Get-CredentialPath -HostName $ComputerName -Account $UserName -Store $CredentialStore
if ($ForgetCredential) {
    if (Test-Path -LiteralPath $credentialPath -PathType Leaf) {
        Remove-Item -LiteralPath $credentialPath -Force
        Write-Host "Removed the protected credential for $UserName@$ComputerName."
    }
    else {
        Write-Host "No protected credential exists for $UserName@$ComputerName."
    }
    return
}

if (-not (Test-NetConnection -ComputerName $ComputerName -Port $Port -InformationLevel Quiet)) {
    throw "TCP $Port is not reachable on '$ComputerName'. Do not prompt for a WinRM password yet. Use Stage-SinumerikIpcBootstrap.ps1 only when approved bootstrap is required."
}

function Open-VerifiedSession {
    param([pscredential]$Credential)
    if ((Get-AccountLeaf $Credential.UserName) -ine (Get-AccountLeaf $UserName)) {
        throw "Credential account '$($Credential.UserName)' does not match selected account '$UserName'."
    }
    $parameters = @{
        ComputerName = $ComputerName
        Port = $Port
        Credential = $Credential
        Authentication = $Authentication
        ErrorAction = 'Stop'
    }
    if ($UseSsl) { $parameters.UseSSL = $true }
    $candidate = New-PSSession @parameters
    try {
        $remoteRoot = if ($profileData -and $profileData.bootstrap) { [string]$profileData.bootstrap.remoteRoot } else { $null }
        $stateFile = if ($profileData -and $profileData.bootstrap) { [string]$profileData.bootstrap.stateFile } else { $null }
        $revertFile = if ($profileData -and $profileData.bootstrap) { [string]$profileData.bootstrap.revertScript } else { $null }
        $identity = Invoke-Command -Session $candidate -ArgumentList $remoteRoot, $stateFile, $revertFile -ErrorAction Stop -ScriptBlock {
            param($root, $stateName, $revertName)
            $current = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object Security.Principal.WindowsPrincipal($current)
            [pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                UserName = $current.Name
                IsAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                SetupStateExists = if ($root -and $stateName) { Test-Path -LiteralPath (Join-Path $root $stateName) -PathType Leaf } else { $null }
                RevertScriptExists = if ($root -and $revertName) { Test-Path -LiteralPath (Join-Path $root $revertName) -PathType Leaf } else { $null }
            }
        }
        if ((Get-AccountLeaf $identity.UserName) -ine (Get-AccountLeaf $UserName)) {
            throw "Remote identity '$($identity.UserName)' does not match selected account '$UserName'."
        }
        return [pscustomobject]@{ Session = $candidate; Identity = $identity }
    }
    catch {
        Remove-PSSession -Session $candidate -ErrorAction SilentlyContinue
        throw
    }
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
        $temporaryPath = "$credentialPath.$([guid]::NewGuid().ToString('N')).tmp"
        try {
            $credential | Export-Clixml -LiteralPath $temporaryPath -Force
            Move-Item -LiteralPath $temporaryPath -Destination $credentialPath -Force
        }
        finally {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
        Write-Host "Saved a DPAPI-protected credential for the current Windows user and machine." -ForegroundColor Green
    }
}

$result = [pscustomobject]@{
    Profile = if ($profileData) { $profileData.__profileName } else { $null }
    ComputerName = $ComputerName
    Role = $Role
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
