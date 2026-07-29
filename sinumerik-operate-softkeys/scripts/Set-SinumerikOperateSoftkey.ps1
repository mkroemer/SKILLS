<#
.SYNOPSIS
Applies a reviewed, ownership-tracked Operate softkey plan on the IPC.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PlanPath,
    [string]$MotionControlRoot = 'C:\ProgramData\Siemens\MotionControl',
    [string]$OwnershipRoot = 'C:\ProgramData\SinumerikOperateSoftkeys'
)

$ErrorActionPreference = 'Stop'

function Get-IniSection {
    param([string]$Content, [string]$Section)
    $pattern = '(?ms)^\[' + [regex]::Escape($Section) + '\]\s*$.*?(?=^\[|\z)'
    $match = [regex]::Match($Content, $pattern)
    if ($match.Success) { return $match.Value }
    return $null
}

function Get-IniEntry {
    param([string]$Content, [string]$Section, [string]$Key)
    $sectionText = Get-IniSection $Content $Section
    if (-not $sectionText) { return $null }
    $match = [regex]::Match($sectionText, '(?m)^' + [regex]::Escape($Key) + '\s*=\s*(.*)$')
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return $null
}

function Set-IniEntry {
    param([string]$Content, [string]$Section, [string]$Key, [string]$Value)
    $sectionPattern = '(?ms)^\[' + [regex]::Escape($Section) + '\]\s*$.*?(?=^\[|\z)'
    $match = [regex]::Match($Content, $sectionPattern)
    $line = "$Key=$Value"
    if (-not $match.Success) { return $Content.TrimEnd() + "`r`n`r`n[$Section]`r`n$line`r`n" }
    $sectionText = $match.Value
    $keyPattern = '(?m)^' + [regex]::Escape($Key) + '\s*=.*$'
    if ([regex]::IsMatch($sectionText, $keyPattern)) {
        $sectionText = [regex]::Replace($sectionText, $keyPattern, [Text.RegularExpressions.MatchEvaluator]{ param($ignored) $line }, 1)
    }
    else { $sectionText = $sectionText.TrimEnd() + "`r`n$line`r`n" }
    return $Content.Remove($match.Index, $match.Length).Insert($match.Index, $sectionText)
}

function Remove-IniEntry {
    param([string]$Content, [string]$Section, [string]$Key)
    $sectionPattern = '(?ms)^\[' + [regex]::Escape($Section) + '\]\s*$.*?(?=^\[|\z)'
    $match = [regex]::Match($Content, $sectionPattern)
    if (-not $match.Success) { return $Content }
    $updated = [regex]::Replace($match.Value, '(?m)^' + [regex]::Escape($Key) + '\s*=.*(?:\r?\n)?', '', 1)
    return $Content.Remove($match.Index, $match.Length).Insert($match.Index, $updated)
}

function Remove-IniSection {
    param([string]$Content, [string]$Section)
    return [regex]::Replace($Content, '(?ms)^\[' + [regex]::Escape($Section) + '\]\s*$.*?(?=^\[|\z)', '')
}

function Get-Sha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Write-AtomicText {
    param([string]$Path, [string]$Content)
    $temporary = Join-Path (Split-Path -Parent $Path) ('.' + [IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $replaceBackup = "$temporary.replace-backup"
    try {
        [IO.File]::WriteAllText($temporary, $Content, (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::Replace($temporary, $Path, $replaceBackup) }
        else { Move-Item -LiteralPath $temporary -Destination $Path }
    }
    finally { Remove-Item -LiteralPath $temporary, $replaceBackup -Force -ErrorAction SilentlyContinue }
}

function Copy-AtomicFile {
    param([string]$Source, [string]$Destination)
    $temporary = Join-Path (Split-Path -Parent $Destination) ('.' + [IO.Path]::GetFileName($Destination) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $replaceBackup = "$temporary.replace-backup"
    try {
        Copy-Item -LiteralPath $Source -Destination $temporary -Force
        if (Test-Path -LiteralPath $Destination -PathType Leaf) { [IO.File]::Replace($temporary, $Destination, $replaceBackup) }
        else { Move-Item -LiteralPath $temporary -Destination $Destination }
    }
    finally { Remove-Item -LiteralPath $temporary, $replaceBackup -Force -ErrorAction SilentlyContinue }
}

function Assert-OwnedState {
    param($Manifest, [string]$SystemText, [string]$MenuText, [string]$IconPath)
    if ($Manifest.area_id -notmatch '^[A-Za-z][A-Za-z0-9_]{0,63}$' -or $Manifest.process_key -notmatch '^PROC(?:[5-9][0-9]{2})$' -or $Manifest.area_key -notmatch '^AREA(?:[5-9][0-9]{2})$' -or $Manifest.icon_name -ne "$($Manifest.area_id)_softkey.png") { throw 'Ownership manifest is invalid; refusing to use it.' }
    if ((Get-IniEntry $SystemText 'processes' $Manifest.process_key) -ne $Manifest.process_value) { throw 'Owned process entry has drifted; refusing to overwrite it.' }
    if ((Get-IniEntry $SystemText 'areas' $Manifest.area_key) -ne $Manifest.area_value) { throw 'Owned area entry has drifted; refusing to overwrite it.' }
    $currentMenu = Get-IniSection $MenuText $Manifest.area_id
    if (-not $currentMenu -or $currentMenu.Trim() -ne ([string]$Manifest.menu_section).Trim()) { throw 'Owned menu section has drifted; refusing to overwrite it.' }
    if ((Get-Sha256 $IconPath) -ne $Manifest.icon_sha256) { throw 'Owned icon has drifted; refusing to overwrite it.' }
}

if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) { throw "Plan not found: $PlanPath" }
$plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
$action = [string]$plan.action
if ($action -notin @('Inspect', 'Add', 'Update', 'Delete')) { throw "Unsupported action '$action'." }
if ($MotionControlRoot -eq 'C:\ProgramData\Siemens\MotionControl') {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Operate softkey changes require an IPC administrator.' }
}

$configRoot = Join-Path $MotionControlRoot 'oem\sinumerik\hmi\cfg'
$systemPath = Join-Path $configRoot 'systemconfiguration.ini'
$menuPath = Join-Path $configRoot 'slamconfig.ini'
$iconRoot = Join-Path $MotionControlRoot 'oem\sinumerik\hmi\ico\ico1024'
$entriesRoot = Join-Path $OwnershipRoot 'entries'
$backupRoot = Join-Path $OwnershipRoot 'backups'
foreach ($required in @($systemPath, $menuPath, $iconRoot)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required Operate path is missing: $required" }
}

$systemText = [IO.File]::ReadAllText($systemPath)
$menuText = [IO.File]::ReadAllText($menuPath)
if ($action -eq 'Inspect') {
    $positions = @([regex]::Matches($menuText, '(?mi)^SoftkeyPosition\s*=\s*(\d+)\s*$') | ForEach-Object { [int]$_.Groups[1].Value })
    $managed = if (Test-Path -LiteralPath $entriesRoot) { @(Get-ChildItem -LiteralPath $entriesRoot -Filter '*.json' -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json }) } else { @() }
    [pscustomobject]@{ SystemConfiguration = $systemPath; MenuConfiguration = $menuPath; OccupiedPositions = $positions; ManagedSoftkeys = $managed }
    return
}

$areaId = [string]$plan.label
if ($areaId -notmatch '^[A-Za-z][A-Za-z0-9_]{0,63}$') { throw 'Label must be a machine-safe area ID: letters, digits, underscore; no spaces.' }
$manifestPath = Join-Path $entriesRoot "$areaId.json"
$manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json } else { $null }

if ($action -eq 'Add' -and $manifest) { throw "Softkey '$areaId' is already managed; use Update." }
if ($action -in @('Update', 'Delete') -and -not $manifest) { throw "No ownership manifest exists for '$areaId'; refusing $action." }

if ($manifest) {
    $iconPath = Join-Path $iconRoot $manifest.icon_name
    Assert-OwnedState $manifest $systemText $menuText $iconPath
}

if ($action -in @('Add', 'Update')) {
    $program = [string]$plan.program
    $logoSource = [string]$plan.logo_path
    if (-not [IO.Path]::IsPathRooted($program) -or [IO.Path]::GetExtension($program) -ine '.exe') { throw 'Program must be an absolute IPC .exe path.' }
    if (-not (Test-Path -LiteralPath $program -PathType Leaf)) { throw "Program does not exist on the IPC: $program" }
    if (-not (Test-Path -LiteralPath $logoSource -PathType Leaf)) { throw "Staged PNG logo is missing: $logoSource" }
    $signature = [IO.File]::ReadAllBytes($logoSource)
    if ($signature.Length -lt 8 -or [BitConverter]::ToString($signature, 0, 8) -ne '89-50-4E-47-0D-0A-1A-0A') { throw 'Logo is not a valid PNG file.' }
}

if ($action -eq 'Add') {
    if (Get-IniSection $menuText $areaId) { throw "Menu section '$areaId' already exists." }
    $processName = "ManagedSoftkey_$areaId"
    if ($systemText -match ('(?mi)^PROC\d+\s*=.*\bprocess:=' + [regex]::Escape($processName) + '(?:,|\s*$)')) { throw "Process name '$processName' already exists outside this skill's ownership." }
    if ($systemText -match ('(?mi)^AREA\d+\s*=.*\bname:=' + [regex]::Escape($areaId) + '(?:,|\s*$)')) { throw "Area name '$areaId' already exists outside this skill's ownership." }
    $number = 500..999 | Where-Object { -not (Get-IniEntry $systemText 'processes' "PROC$_") -and -not (Get-IniEntry $systemText 'areas' "AREA$_") } | Select-Object -First 1
    if (-not $number) { throw 'No free matching PROC/AREA number exists from 500 through 999.' }
    $occupied = New-Object 'System.Collections.Generic.HashSet[int]'
    [regex]::Matches($menuText, '(?mi)^SoftkeyPosition\s*=\s*(\d+)\s*$') | ForEach-Object { [void]$occupied.Add([int]$_.Groups[1].Value) }
    $position = 9..64 | Where-Object { -not $occupied.Contains($_) } | Select-Object -First 1
    if (-not $position) { throw 'No free Operate softkey position exists from 9 through 64.' }
    $manifest = [pscustomobject]@{ owner = 'sinumerik-operate-softkeys'; area_id = $areaId; process_key = "PROC$number"; area_key = "AREA$number"; process_name = $processName; position = $position; icon_name = "${areaId}_softkey.png" }
}

$iconPath = Join-Path $iconRoot $manifest.icon_name
if ($action -eq 'Add' -and (Test-Path -LiteralPath $iconPath -PathType Leaf)) { throw "Icon target already exists outside this skill's ownership: $iconPath" }
$transaction = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$backup = Join-Path $backupRoot "$areaId\$transaction"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item -LiteralPath $systemPath -Destination (Join-Path $backup 'systemconfiguration.ini') -Force
Copy-Item -LiteralPath $menuPath -Destination (Join-Path $backup 'slamconfig.ini') -Force
if (Test-Path -LiteralPath $iconPath -PathType Leaf) { Copy-Item -LiteralPath $iconPath -Destination (Join-Path $backup 'icon.png') -Force }
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $backup 'manifest.json') -Force }

try {
    if ($action -in @('Add', 'Update')) {
        $arguments = ([string]$plan.arguments).Trim()
        $commandLine = if ($arguments) { "$($plan.program) $arguments" } else { [string]$plan.program }
        if ($commandLine.Contains('"') -or ([string]$plan.window_name).Contains('"')) { throw 'Program arguments and window title must not contain double quotes.' }
        $processValue = "process:=$($manifest.process_name), cmdline:=`"$commandLine`", oemframe:=true, deferred:=true, windowname:=`"$($plan.window_name)`""
        $areaValue = "name:=$areaId, process:=$($manifest.process_name)"
        $menuSection = "[$areaId]`r`nAccessLevel=7`r`nPicture=$($manifest.icon_name)`r`nSoftkeyPosition=$($manifest.position)`r`n"
        $systemText = Set-IniEntry $systemText 'processes' $manifest.process_key $processValue
        $systemText = Set-IniEntry $systemText 'areas' $manifest.area_key $areaValue
        $menuText = (Remove-IniSection $menuText $areaId).TrimEnd() + "`r`n`r`n$menuSection"
        Copy-AtomicFile -Source $plan.logo_path -Destination $iconPath
        $manifest | Add-Member -NotePropertyName process_value -NotePropertyValue $processValue -Force
        $manifest | Add-Member -NotePropertyName area_value -NotePropertyValue $areaValue -Force
        $manifest | Add-Member -NotePropertyName menu_section -NotePropertyValue $menuSection -Force
        $manifest | Add-Member -NotePropertyName icon_sha256 -NotePropertyValue (Get-Sha256 $iconPath) -Force
        $manifest | Add-Member -NotePropertyName program -NotePropertyValue ([string]$plan.program) -Force
        $manifest | Add-Member -NotePropertyName updated_utc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
        Write-AtomicText $systemPath $systemText
        Write-AtomicText $menuPath $menuText
        New-Item -ItemType Directory -Path $entriesRoot -Force | Out-Null
        Write-AtomicText $manifestPath ($manifest | ConvertTo-Json -Depth 5)
    }
    else {
        $systemText = Remove-IniEntry $systemText 'processes' $manifest.process_key
        $systemText = Remove-IniEntry $systemText 'areas' $manifest.area_key
        $menuText = Remove-IniSection $menuText $areaId
        Write-AtomicText $systemPath $systemText
        Write-AtomicText $menuPath $menuText
        Remove-Item -LiteralPath $iconPath -Force
        Remove-Item -LiteralPath $manifestPath -Force
    }
}
catch {
    $failure = $_
    Copy-Item -LiteralPath (Join-Path $backup 'systemconfiguration.ini') -Destination $systemPath -Force
    Copy-Item -LiteralPath (Join-Path $backup 'slamconfig.ini') -Destination $menuPath -Force
    if (Test-Path -LiteralPath (Join-Path $backup 'icon.png')) { Copy-Item -LiteralPath (Join-Path $backup 'icon.png') -Destination $iconPath -Force } else { Remove-Item -LiteralPath $iconPath -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath (Join-Path $backup 'manifest.json')) { New-Item -ItemType Directory -Path $entriesRoot -Force | Out-Null; Copy-Item -LiteralPath (Join-Path $backup 'manifest.json') -Destination $manifestPath -Force } else { Remove-Item -LiteralPath $manifestPath -Force -ErrorAction SilentlyContinue }
    throw "Softkey transaction failed and rollback was attempted: $($failure.Exception.Message)"
}

[pscustomobject]@{ Action = $action; Label = $areaId; ProcessKey = $manifest.process_key; AreaKey = $manifest.area_key; Position = $manifest.position; Backup = $backup; RestartOperateInteractively = $true }
