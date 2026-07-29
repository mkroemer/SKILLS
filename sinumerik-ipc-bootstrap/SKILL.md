---
name: sinumerik-ipc-bootstrap
description: Classify, bootstrap, verify, diagnose, or recover remote administration, deployment, and optional interactive runtime on a SINUMERIK IPC using named machine profiles, SMB staging, elevated local PowerShell, and WinRM. Use for new IPC preparation, setup-file staging, restricted WinRM access, bootstrap markers, scheduled-task or process diagnosis, URLACL or credential failures, and deciding whether network, bootstrap, deployment, or runtime repair is required.
---

# SINUMERIK IPC Bootstrap

Classify the first failed layer before changing an IPC. Keep these boundaries
separate:

1. **Network** - probe without credentials.
2. **Elevated IPC bootstrap** - execute locally as an administrator.
3. **Administrator deployment** - use WinRM for approved file and task
   configuration.
4. **Interactive Siemens runtime** - start Siemens-dependent applications only
   through the approved interactive mechanism in the logged-on HMI session.

Never start Siemens-dependent runtime directly inside WinRM/session 0.

## Load the machine profile

Read `sinumerik-ipc-profiles` and resolve the selected profile:

```powershell
Import-Module '.\.agents\skills\sinumerik-ipc-profiles\scripts\SinumerikIpcProfiles.psm1'
$profile = Resolve-SinumerikIpcProfile -Name '<profile-name>'
```

Use these profile sections only when present:

- `computerName`, `accounts`, and `winrm`;
- `management`;
- `bootstrap`;
- `runtime`;
- `operate`.

Let confirmed explicit inputs override profile values. Never store a password
in the profile.

## Required report

Report these states independently:

| Layer | Evidence |
|---|---|
| Network | ICMP context plus TCP 445, configured WinRM port, and optional runtime port |
| WinRM access | transport state, authentication classification, verified remote identity |
| Bootstrap | configured state marker/status and revert marker |
| Deployment | project-defined active release and interactive task evidence |
| Runtime | configured process/session, task result, health, and data endpoint |

Report the first failed layer and the next justified action. Do not claim
completion without successful evidence for that layer.

## Safety rules

- Do not rerun bootstrap merely because deployment or runtime is unhealthy.
- Do not delete setup state or revert markers to force a clean run.
- Do not set `TrustedHosts` to `*`.
- Do not widen firewall, URLACL, or management-network scope automatically.
- Do not reconstruct setup scripts from documentation, snippets, or memory.
- Do not manually copy application releases when the consuming project has an
  approved deployment procedure.
- Do not assume a fixed HMI session ID unless the consuming project explicitly
  requires one.
- Treat reachable WinRM with failed authentication as an access problem, not
  permission to stage bootstrap files.
- Use `-AllowRecoveryRestage` only for a diagnosed and explicitly approved
  recovery; it never authorizes deleting state.

# Phase 1: Classify without changing the IPC

## Probe network ports

```powershell
$target = [string]$profile.computerName
$winrmPort = if ($profile.winrm.port) { [int]$profile.winrm.port } else { 5985 }
$runtimePort = if ($profile.runtime.port) { [int]$profile.runtime.port } else { $null }

$network = [ordered]@{
    Ping = Test-Connection -ComputerName $target -Count 2 -Quiet
    SMB = Test-NetConnection -ComputerName $target -Port 445 -InformationLevel Quiet
    WinRM = Test-NetConnection -ComputerName $target -Port $winrmPort -InformationLevel Quiet
}
if ($runtimePort) {
    $network.Runtime = Test-NetConnection -ComputerName $target -Port $runtimePort -InformationLevel Quiet
}
[pscustomobject]$network
```

Ping failure alone is not decisive because ICMP may be blocked. A closed
runtime port does not prove bootstrap failure.

## Classify WinRM

Only request a credential when the configured WinRM port is reachable:

```powershell
& '.\.agents\skills\sinumerik-ipc-connect\scripts\Connect-SinumerikIpc.ps1' `
  -Profile $profile.__profileName `
  -ConfigPath $profile.__configPath `
  -Role administrator
```

Classify the exact outcome:

| Classification | Meaning | Next action |
|---|---|---|
| `TransportClosed` | listener, firewall, routing, or bootstrap unavailable | Consider approved SMB/local bootstrap |
| `ClientTrustOrAuthenticationConfiguration` | IPC may be configured; client cannot authenticate by address | Add only the exact target to `TrustedHosts`, then retry |
| `CredentialOrAuthorizationFailure` | transport works; credential or authorization is wrong | Correct access; do not bootstrap |
| `SessionFailureUnclassified` | transport works but the cause is unresolved | Preserve the exact error and diagnose |
| `SessionVerified` | remote administration works | Inspect bootstrap, deployment, and runtime independently |

Use `-ConfigureTrustedHost` only after evidence identifies exact-host client
trust as the problem.

## Inspect configured remote evidence

Use the verified connection's `Session`. Do not guess marker, task, process, or
log names:

```powershell
$connection = & '.\.agents\skills\sinumerik-ipc-connect\scripts\Connect-SinumerikIpc.ps1' `
  -Profile $profile.__profileName -ConfigPath $profile.__configPath -Role administrator
$session = $connection.Session

$remoteRoot = [string]$profile.bootstrap.remoteRoot
$stateName = [string]$profile.bootstrap.stateFile
$revertName = [string]$profile.bootstrap.revertScript
$runtime = $profile.runtime

try {
    Invoke-Command -Session $session -ArgumentList $remoteRoot, $stateName, $revertName, $runtime -ScriptBlock {
        param($root, $stateFile, $revertFile, $runtimeConfig)

        $statePath = if ($root -and $stateFile) { Join-Path $root $stateFile } else { $null }
        $stateStatus = $null
        $stateError = $null
        if ($statePath -and (Test-Path -LiteralPath $statePath -PathType Leaf)) {
            try {
                $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
                $stateStatus = [string]$state.status
            }
            catch { $stateError = $_.Exception.Message }
        }

        $processes = @()
        if ($runtimeConfig.processName) {
            $processes = @(Get-CimInstance Win32_Process -Filter "Name='$($runtimeConfig.processName)'" -ErrorAction SilentlyContinue)
        }

        $task = $null
        $taskInfo = $null
        if ($runtimeConfig.taskName) {
            try {
                $task = Get-ScheduledTask -TaskName $runtimeConfig.taskName -ErrorAction Stop
                $taskInfo = Get-ScheduledTaskInfo -InputObject $task -ErrorAction Stop
            }
            catch {}
        }

        [pscustomobject]@{
            ComputerName = $env:COMPUTERNAME
            WinRMService = (Get-Service WinRM).Status.ToString()
            BootstrapRootExists = if ($root) { Test-Path -LiteralPath $root -PathType Container } else { $null }
            SetupStateExists = if ($statePath) { Test-Path -LiteralPath $statePath -PathType Leaf } else { $null }
            SetupStateStatus = $stateStatus
            SetupStateReadError = $stateError
            RevertScriptExists = if ($root -and $revertFile) { Test-Path -LiteralPath (Join-Path $root $revertFile) -PathType Leaf } else { $null }
            ActiveReleaseExists = if ($root -and $runtimeConfig.activeReleaseFile) { Test-Path -LiteralPath (Join-Path $root $runtimeConfig.activeReleaseFile) -PathType Leaf } else { $null }
            RuntimeProcessExists = $processes.Count -gt 0
            RuntimeProcessIds = @($processes | Select-Object -ExpandProperty ProcessId)
            RuntimeSessionIds = @($processes | Select-Object -ExpandProperty SessionId)
            RuntimeTaskExists = $null -ne $task
            RuntimeTaskState = if ($task) { [string]$task.State } else { $null }
            RuntimeTaskLastResult = if ($taskInfo) { $taskInfo.LastTaskResult } else { $null }
        }
    }
}
finally {
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
}
```

Marker absence can indicate partial state or drift; it is not automatic
permission to rerun setup.

# Phase 2: Stage approved bootstrap files

Use SMB only when WinRM transport is closed and local bootstrap or recovery
requires staging:

```powershell
& '.\.agents\skills\sinumerik-ipc-connect\scripts\Stage-SinumerikIpcBootstrap.ps1' `
  -Profile $profile.__profileName `
  -ConfigPath $profile.__configPath `
  -SourceRoot '<reviewed-consuming-project-root>'
```

The helper must:

- copy only `bootstrap.files`;
- constrain sources below `SourceRoot`;
- constrain destinations below `bootstrap.remoteRoot`;
- refuse configured state/revert markers unless recovery restaging is approved;
- compare SHA-256 after every copy;
- print the structured profile-generated local command.

If SMB is unavailable, generate the same reviewed payload for an approved
interactive transfer:

```powershell
& '.\.agents\skills\sinumerik-ipc-connect\scripts\New-SinumerikIpcBootstrapPaste.ps1' `
  -Profile $profile.__profileName `
  -ConfigPath $profile.__configPath `
  -SourceRoot '<reviewed-consuming-project-root>'
```

# Phase 3: Run bootstrap locally and elevated

Run only the exact command generated from `bootstrap.entryScript` and
`bootstrap.entryArguments`. Confirm target, interface index when required, and
the narrow management host/subnet before execution.

Preserve setup output, state, and the exact error. Do not continue to deployment
until a fresh verified WinRM session and the configured markers establish
bootstrap success.

# Phase 4: Deploy through the consuming project

Use the consuming project's reviewed build and deployment procedure. Do not
infer filenames such as `deploy.ps1` or manually construct a release.

Verify project-defined deployment evidence, such as:

- active release metadata;
- immutable release files;
- an interactive scheduled task;
- the expected task action and principal.

WinRM may configure or request the interactive task, but must not host the
Siemens-dependent runtime.

# Phase 5: Verify optional runtime

Skip runtime HTTP probes when the profile has no `runtime` section.

```powershell
function Test-HttpEndpoint {
    param([Parameter(Mandatory)][string]$Uri)
    try {
        $response = Invoke-RestMethod -Uri $Uri -TimeoutSec 5 -ErrorAction Stop
        [pscustomobject]@{ Uri = $Uri; Success = $true; Response = $response; Error = $null }
    }
    catch {
        [pscustomobject]@{ Uri = $Uri; Success = $false; Response = $null; Error = $_.Exception.Message }
    }
}

$scheme = if ($profile.runtime.useSsl) { 'https' } else { 'http' }
$baseUri = "${scheme}://$($profile.computerName):$($profile.runtime.port)"
[pscustomobject]@{
    RuntimeTcp = Test-NetConnection -ComputerName $profile.computerName -Port $profile.runtime.port -InformationLevel Quiet
    Health = if ($profile.runtime.healthPath) { Test-HttpEndpoint "$baseUri$($profile.runtime.healthPath)" } else { $null }
    Data = if ($profile.runtime.snapshotPath) { Test-HttpEndpoint "$baseUri$($profile.runtime.snapshotPath)" } else { $null }
}
```

Healthy transport with an unhealthy data endpoint indicates application,
adapter, Siemens-session, configuration, or data-availability problems, not
bootstrap failure.

# Troubleshooting order

Stop when the first failed layer is established:

1. **TCP 445 closed and staging is required:** check cabling, VLAN, approved
   client addressing, or SMB policy.
2. **Configured WinRM port closed:** diagnose listener, firewall, routing, or
   bootstrap.
3. **WinRM open; client trust failure:** add only the exact target, then retry.
4. **WinRM open; access denied:** correct credential or authorization.
5. **Setup state unreadable or failed:** preserve it and use the approved local
   reconcile/revert procedure.
6. **URLACL access denied:** compare configured loopback and external URLACLs
   with the approved runtime identity; do not broaden them by default.
7. **Task exists but no process exists:** inspect task result, action, launcher
   logs, and the logged-on HMI session.
8. **Process runs in the wrong session:** repair interactive task/session
   targeting; never start it through WinRM.
9. **Health works but data fails:** diagnose adapter configuration, Siemens data
   availability, and runtime integration.

Record timestamps, exact commands, observed status, relevant paths,
task/session details, and staged-file hashes. Never record credentials or
secrets.
