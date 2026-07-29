$ErrorActionPreference = 'Stop'

function Get-SinumerikIpcConfigCandidates {
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:SINUMERIK_IPC_CONFIG)) {
        $candidates += $env:SINUMERIK_IPC_CONFIG
    }
    $candidates += Join-Path (Get-Location).Path '.sinumerik\ipc-profiles.json'
    if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $candidates += Join-Path $env:APPDATA 'SinumerikSkills\ipc-profiles.json'
    }
    return @($candidates | Where-Object { $_ } | Select-Object -Unique)
}

function Find-SinumerikIpcConfig {
    [CmdletBinding()]
    param(
        [string]$ConfigPath,
        [switch]$AllowMissing
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
            throw "SINUMERIK IPC profile file not found: $ConfigPath"
        }
        return (Resolve-Path -LiteralPath $ConfigPath).Path
    }

    foreach ($candidate in Get-SinumerikIpcConfigCandidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    if ($AllowMissing) { return $null }
    throw 'No SINUMERIK IPC profile file was found. Pass -ConfigPath, set SINUMERIK_IPC_CONFIG, or initialize the current-user profile file.'
}

function Assert-NoSecretProfileFields {
    param(
        [Parameter(Mandatory)]$Value,
        [string]$Path = '$'
    )

    if ($null -eq $Value -or $Value -is [string] -or $Value.GetType().IsValueType) { return }
    if ($Value -is [Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            if ([string]$key -match '(?i)^(password|credential|credentials|secret|token|api[_-]?key|private[_-]?key|securestring)$') {
                throw "Secret-bearing property '$Path.$key' is not allowed in an IPC profile."
            }
            Assert-NoSecretProfileFields -Value $Value[$key] -Path "$Path.$key"
        }
        return
    }
    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
        $index = 0
        foreach ($item in $Value) {
            Assert-NoSecretProfileFields -Value $item -Path "$Path[$index]"
            $index++
        }
        return
    }
    foreach ($property in $Value.PSObject.Properties) {
        if ($property.Name -match '(?i)^(password|credential|credentials|secret|token|api[_-]?key|private[_-]?key|securestring)$') {
            throw "Secret-bearing property '$Path.$($property.Name)' is not allowed in an IPC profile."
        }
        Assert-NoSecretProfileFields -Value $property.Value -Path "$Path.$($property.Name)"
    }
}

function Read-SinumerikIpcProfileConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConfigPath)

    $text = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop
    try {
        $config = $text | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Invalid SINUMERIK IPC profile JSON in '$ConfigPath': $($_.Exception.Message)"
    }
    Assert-NoSecretProfileFields -Value $config
    if ([int]$config.schemaVersion -ne 1) {
        throw "Unsupported SINUMERIK IPC profile schema version '$($config.schemaVersion)'."
    }
    if (-not $config.profiles -or $config.profiles.PSObject.Properties.Count -eq 0) {
        throw "The profile file '$ConfigPath' contains no profiles."
    }
    return $config
}

function Get-SinumerikIpcProfileNames {
    [CmdletBinding()]
    param([string]$ConfigPath)

    $resolvedPath = Find-SinumerikIpcConfig -ConfigPath $ConfigPath
    $config = Read-SinumerikIpcProfileConfig -ConfigPath $resolvedPath
    return @($config.profiles.PSObject.Properties | ForEach-Object { $_.Name })
}

function Resolve-SinumerikIpcProfile {
    [CmdletBinding()]
    param(
        [Alias('Profile')]
        [string]$Name,
        [string]$ConfigPath,
        [switch]$AllowMissing
    )

    $resolvedPath = Find-SinumerikIpcConfig -ConfigPath $ConfigPath -AllowMissing:$AllowMissing
    if (-not $resolvedPath) { return $null }
    $config = Read-SinumerikIpcProfileConfig -ConfigPath $resolvedPath

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = [string]$config.defaultProfile
        if ([string]::IsNullOrWhiteSpace($Name)) {
            $names = @($config.profiles.PSObject.Properties | ForEach-Object { $_.Name })
            if ($names.Count -eq 1) { $Name = $names[0] }
            else { throw "Profile selection is required. Available profiles: $($names -join ', ')." }
        }
    }

    $profileProperty = $config.profiles.PSObject.Properties | Where-Object Name -eq $Name | Select-Object -First 1
    if (-not $profileProperty) {
        $names = @($config.profiles.PSObject.Properties | ForEach-Object { $_.Name })
        throw "SINUMERIK IPC profile '$Name' was not found. Available profiles: $($names -join ', ')."
    }
    $profile = $profileProperty.Value
    if ([string]::IsNullOrWhiteSpace([string]$profile.computerName)) {
        throw "Profile '$Name' does not define computerName."
    }
    if ($profile.winrm -and $profile.winrm.port) {
        $port = [int]$profile.winrm.port
        if ($port -lt 1 -or $port -gt 65535) { throw "Profile '$Name' has an invalid WinRM port." }
    }
    if ($profile.winrm -and $profile.winrm.authentication) {
        $allowedAuthentication = @('Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos')
        $authentication = [string]$profile.winrm.authentication
        if ($authentication -notin $allowedAuthentication) {
            throw "Profile '$Name' has an unsupported WinRM authentication method."
        }
    }
    if ($profile.runtime -and $profile.runtime.port) {
        $port = [int]$profile.runtime.port
        if ($port -lt 1 -or $port -gt 65535) { throw "Profile '$Name' has an invalid runtime port." }
    }

    $profile | Add-Member -NotePropertyName __profileName -NotePropertyValue $Name -Force
    $profile | Add-Member -NotePropertyName __configPath -NotePropertyValue $resolvedPath -Force
    return $profile
}

function Get-SinumerikIpcProfileValue {
    param(
        [Parameter(Mandatory)]$Profile,
        [Parameter(Mandatory)][string]$Path
    )

    $value = $Profile
    foreach ($segment in ($Path -split '\.')) {
        if ($null -eq $value) { return $null }
        $property = $value.PSObject.Properties | Where-Object Name -eq $segment | Select-Object -First 1
        if (-not $property) { return $null }
        $value = $property.Value
    }
    return $value
}

function Expand-SinumerikIpcProfileValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Profile,
        [AllowEmptyString()]
        [string]$Value
    )

    return [regex]::Replace($Value, '\{([A-Za-z0-9_.]+)\}', {
        param($match)
        $resolved = Get-SinumerikIpcProfileValue -Profile $Profile -Path $match.Groups[1].Value
        if ($null -eq $resolved) {
            throw "Profile placeholder '$($match.Value)' could not be resolved."
        }
        return [string]$resolved
    })
}

function ConvertTo-PowerShellSingleQuotedLiteral {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function New-SinumerikIpcBootstrapCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Profile)

    if (-not $Profile.bootstrap) { throw "Profile '$($Profile.__profileName)' does not define bootstrap settings." }
    $remoteRoot = [string]$Profile.bootstrap.remoteRoot
    $entryScript = [string]$Profile.bootstrap.entryScript
    if ([string]::IsNullOrWhiteSpace($remoteRoot) -or [string]::IsNullOrWhiteSpace($entryScript)) {
        throw 'bootstrap.remoteRoot and bootstrap.entryScript are required.'
    }
    if ($remoteRoot -notmatch '^[A-Za-z]:\\.+') {
        throw 'bootstrap.remoteRoot must be an absolute drive path below the drive root.'
    }
    if ([IO.Path]::IsPathRooted($entryScript) -or $entryScript -match '(^|[\\/])\.\.([\\/]|$)') {
        throw 'bootstrap.entryScript must be a safe path relative to bootstrap.remoteRoot.'
    }

    $entryPath = Join-Path $remoteRoot $entryScript
    $parts = @()
    $parts += '& ' + (ConvertTo-PowerShellSingleQuotedLiteral $entryPath)
    if ($Profile.bootstrap.entryArguments) {
        foreach ($argument in $Profile.bootstrap.entryArguments.PSObject.Properties) {
            if ($argument.Name -notmatch '^[A-Za-z][A-Za-z0-9]*$') {
                throw "Invalid bootstrap argument name '$($argument.Name)'."
            }
            if ($argument.Value -is [bool]) {
                if ($argument.Value) { $parts += "-$($argument.Name)" }
                continue
            }
            $expanded = Expand-SinumerikIpcProfileValue -Profile $Profile -Value ([string]$argument.Value)
            $parts += "-$($argument.Name) " + (ConvertTo-PowerShellSingleQuotedLiteral $expanded)
        }
    }
    return ($parts -join ' ')
}

Export-ModuleMember -Function `
    Find-SinumerikIpcConfig, `
    Get-SinumerikIpcProfileNames, `
    Resolve-SinumerikIpcProfile, `
    Expand-SinumerikIpcProfileValue, `
    New-SinumerikIpcBootstrapCommand
