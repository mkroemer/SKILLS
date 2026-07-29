<#
.SYNOPSIS
Exercises the softkey apply helper against an isolated temporary configuration tree.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$applyScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Set-SinumerikOperateSoftkey.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Write-Utf8WithoutBom {
    param([string]$Path, [string]$Content)
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

function Write-Plan {
    param([string]$Path, [Collections.IDictionary]$Plan)
    Write-Utf8WithoutBom -Path $Path -Content ($Plan | ConvertTo-Json -Depth 5)
}

if (-not (Test-Path -LiteralPath $applyScript -PathType Leaf)) { throw "Apply helper not found: $applyScript" }

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('sinumerik-operate-softkeys-test-' + [guid]::NewGuid().ToString('N'))
$motionRoot = Join-Path $testRoot 'MotionControl'
$ownershipRoot = Join-Path $testRoot 'Ownership'
$configRoot = Join-Path $motionRoot 'oem\sinumerik\hmi\cfg'
$iconRoot = Join-Path $motionRoot 'oem\sinumerik\hmi\ico\ico1024'
$systemPath = Join-Path $configRoot 'systemconfiguration.ini'
$menuPath = Join-Path $configRoot 'slamconfig.ini'
$programPath = Join-Path $testRoot 'Example.exe'
$iconSource = Join-Path $testRoot 'icon.png'
$planPath = Join-Path $testRoot 'plan.json'

try {
    New-Item -ItemType Directory -Path $configRoot, $iconRoot -Force | Out-Null
    Write-Utf8WithoutBom -Path $systemPath -Content "[processes]`r`n`r`n[areas]`r`n"
    Write-Utf8WithoutBom -Path $menuPath -Content "[Main]`r`nSoftkeyPosition=1`r`n"
    [IO.File]::WriteAllBytes($programPath, [byte[]]@(0))
    [IO.File]::WriteAllBytes(
        $iconSource,
        [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
    )

    Write-Plan -Path $planPath -Plan ([ordered]@{
        action = 'Add'
        label = 'TestArea'
        logo_path = $iconSource
        program = $programPath
        arguments = ''
        window_name = 'Test Area'
    })
    $added = & $applyScript -PlanPath $planPath -MotionControlRoot $motionRoot -OwnershipRoot $ownershipRoot
    Assert-True ($added.ProcessKey -eq 'PROC500') 'Add should allocate PROC500 in an empty configuration.'
    Assert-True ($added.AreaKey -eq 'AREA500') 'Add should allocate AREA500 in an empty configuration.'
    Assert-True ($added.Position -eq 9) 'Add should preserve positions 1-8 and allocate position 9.'

    $systemText = [IO.File]::ReadAllText($systemPath)
    $menuText = [IO.File]::ReadAllText($menuPath)
    Assert-True ($systemText -match '(?m)^PROC500=process:=ManagedSoftkey_TestArea,') 'Managed process entry is missing.'
    Assert-True ($systemText -match '(?m)^AREA500=name:=TestArea, process:=ManagedSoftkey_TestArea$') 'Managed area entry is missing.'
    Assert-True ($menuText -match '(?ms)^\[TestArea\].*?^SoftkeyPosition=9$') 'Managed menu section is missing.'
    Assert-True (Test-Path -LiteralPath (Join-Path $iconRoot 'TestArea_softkey.png') -PathType Leaf) 'Managed icon is missing.'

    $manifestPath = Join-Path $ownershipRoot 'entries\TestArea.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    Assert-True ($manifest.owner -eq 'sinumerik-operate-softkeys') 'Ownership marker is missing.'

    Write-Plan -Path $planPath -Plan ([ordered]@{ action = 'Inspect' })
    $inspection = & $applyScript -PlanPath $planPath -MotionControlRoot $motionRoot -OwnershipRoot $ownershipRoot
    Assert-True ($inspection.ManagedSoftkeys.Count -eq 1) 'Inspect should return the managed softkey.'
    Assert-True ($inspection.OccupiedPositions -contains 9) 'Inspect should report the managed position.'

    Write-Plan -Path $planPath -Plan ([ordered]@{
        action = 'Update'
        label = 'TestArea'
        logo_path = $iconSource
        program = $programPath
        arguments = '--mode test'
        window_name = 'Updated Test Area'
    })
    $updated = & $applyScript -PlanPath $planPath -MotionControlRoot $motionRoot -OwnershipRoot $ownershipRoot
    Assert-True ($updated.Position -eq 9) 'Update should preserve the allocated position.'
    Assert-True ([IO.File]::ReadAllText($systemPath).Contains('--mode test')) 'Update should write the reviewed arguments.'

    Write-Plan -Path $planPath -Plan ([ordered]@{ action = 'Delete'; label = 'TestArea' })
    $deleted = & $applyScript -PlanPath $planPath -MotionControlRoot $motionRoot -OwnershipRoot $ownershipRoot
    Assert-True ($deleted.Action -eq 'Delete') 'Delete should report the completed action.'
    Assert-True (-not (Test-Path -LiteralPath $manifestPath)) 'Delete should remove the ownership manifest.'
    Assert-True (-not ([IO.File]::ReadAllText($systemPath) -match '(?m)^(PROC500|AREA500)=')) 'Delete should remove owned system entries.'
    Assert-True (-not ([IO.File]::ReadAllText($menuPath) -match '(?m)^\[TestArea\]$')) 'Delete should remove the owned menu section.'

    Write-Host 'SINUMERIK Operate softkey lifecycle test passed.' -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
