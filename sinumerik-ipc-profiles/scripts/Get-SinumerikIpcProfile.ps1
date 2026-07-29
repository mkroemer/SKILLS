[CmdletBinding()]
param(
    [string]$Name,
    [string]$ConfigPath,
    [switch]$List
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SinumerikIpcProfiles.psm1') -Force

if ($List) {
    Get-SinumerikIpcProfileNames -ConfigPath $ConfigPath
}
else {
    Resolve-SinumerikIpcProfile -Name $Name -ConfigPath $ConfigPath
}
