---
name: ipc-smb-winrm-bootstrap
description: Classify, bootstrap, verify, diagnose, or recover remote administration and collector deployment on a Siemens SINUMERIK ONE IPC using SMB, elevated local PowerShell, WinRM, and the approved Gleason deployment scripts. Use for new IPC preparation, approved setup-file staging, restricted WinRM access, ports 445/5985/8765, interactive collector task diagnosis, URLACL or credential failures, and deciding whether bootstrap, deployment, or runtime repair is required.
---

# IPC SMB and WinRM Bootstrap

Classify the failed layer before changing the IPC. Keep these execution boundaries separate:

1. **Elevated IPC bootstrap** - run locally on the IPC as an administrator.
2. **Administrator deployment** - use WinRM for release deployment and task configuration.
3. **Interactive Siemens runtime** - start the collector only through the approved interactive scheduled task in the logged-on HMI/operator session.

Never start Siemens-dependent collector code directly inside a WinRM session.

## Defaults and required inputs

Use repository-approved values when they differ from these defaults:

```powershell
$ipcIp = '192.168.214.241'
$laptopIp = '192.168.214.252'
$adapterRootRemote = 'D:\OEM\Adapter'
$adminShareRoot = "\\$ipcIp\D$"
$winrmPort = 5985
$collectorPort = 8765
$collectorBaseUri = "http://$ipcIp`:$collectorPort"
$collectorTaskName = 'Gleason Collector Interactive Start'
$collectorProcessName = 'Gleason_Collector.exe'
$allowRecoveryRestage = $false
```

Before elevated setup, confirm:

- approved IPC IPv4 address;
- IPC network-interface index;
- narrow management host or subnet allowed through the firewall;
- authorized IPC administrator credential;
- repository root containing `scripts/setup_gleason_ipc.ps1`, `scripts/Gleason.IpcSetup.psm1`, `build.ps1`, and `deploy.ps1`.

Use credentials only through the approved secret channel. Never print, embed, log, or document passwords. Require pre-commissioning credential rotation before commissioning.

## Required report

Always report these states independently:

| Layer | Evidence |
|---|---|
| Network | TCP 445, 5985, and 8765 |
| Bootstrap | WinRM session, setup-state marker/status, revert script |
| Deployment | `active-release.json`, interactive task |
| Runtime | collector process/session, `/health`, `/snapshot` |

Report the first failed layer and the next justified action. Do not claim completion without a successful verification command.

## Safety rules

- Do not rerun bootstrap merely because deployment or runtime is unhealthy.
- Do not delete setup state to force a clean run.
- Do not set `TrustedHosts` to `*`.
- Do not widen firewall or URLACL scope automatically.
- Do not reconstruct setup scripts from documentation, snippets, or chat output.
- Do not manually copy application releases when `deploy.ps1` is available.
- Do not assume a fixed HMI/operator session ID unless the repository explicitly requires one.
- Do not classify every WinRM session failure as failed IPC bootstrap.

# Phase 1: Classify the current state

## 1. Probe ports without credentials

```powershell
$networkState = [pscustomobject]@{
    Ping = Test-Connection -ComputerName $ipcIp -Count 2 -Quiet
    SMB445 = Test-NetConnection -ComputerName $ipcIp -Port 445 -InformationLevel Quiet
    WinRM5985 = Test-NetConnection -ComputerName $ipcIp -Port $winrmPort -InformationLevel Quiet
    Collector8765 = Test-NetConnection -ComputerName $ipcIp -Port $collectorPort -InformationLevel Quiet
}

$networkState
```

Ping failure alone is not decisive because ICMP may be blocked.

## 2. Probe collector HTTP separately

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

$healthProbe = Test-HttpEndpoint -Uri "$collectorBaseUri/health"
$healthProbe
```

A closed or unhealthy collector does not prove bootstrap failure. It may mean no deployment, a failed interactive start, a collector exit, or an adapter problem.

## 3. Classify WinRM separately from credentials and client trust

Only request the administrator credential when TCP 5985 is reachable.

```powershell
$winrmClass = 'TransportClosed'
$winrmError = $null
$remoteState = $null

if ($networkState.WinRM5985) {
    $adminCred = Get-Credential -Message 'Enter an authorized IPC administrator credential'
    $session = $null

    try {
        $session = New-PSSession `
            -ComputerName $ipcIp `
            -Port $winrmPort `
            -Credential $adminCred `
            -Authentication Negotiate `
            -ErrorAction Stop

        $remoteState = Invoke-Command `
            -Session $session `
            -ArgumentList $adapterRootRemote, $collectorProcessName, $collectorTaskName `
            -ErrorAction Stop `
            -ScriptBlock {
                param($root, $processName, $taskName)

                $setupStatePath = Join-Path $root 'gleason_ipc_setup_state.json'
                $setupStatus = $null
                $setupReadError = $null

                if (Test-Path -LiteralPath $setupStatePath -PathType Leaf) {
                    try {
                        $state = Get-Content -LiteralPath $setupStatePath -Raw -ErrorAction Stop |
                            ConvertFrom-Json -ErrorAction Stop
                        $setupStatus = [string]$state.status
                    }
                    catch {
                        $setupReadError = $_.Exception.Message
                    }
                }

                $processes = @(Get-CimInstance Win32_Process -Filter "Name='$processName'" -ErrorAction SilentlyContinue)

                $task = $null
                $taskInfo = $null
                try {
                    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
                    $taskInfo = Get-ScheduledTaskInfo -InputObject $task -ErrorAction Stop
                }
                catch {}

                [pscustomobject]@{
                    ComputerName = $env:COMPUTERNAME
                    WinRMService = (Get-Service WinRM).Status.ToString()
                    AdapterRootExists = Test-Path -LiteralPath $root -PathType Container
                    SetupStateExists = Test-Path -LiteralPath $setupStatePath -PathType Leaf
                    SetupStateStatus = $setupStatus
                    SetupStateReadError = $setupReadError
                    RevertScriptExists = Test-Path -LiteralPath (Join-Path $root 'revert_gleason_ipc_setup.ps1') -PathType Leaf
                    ActiveReleaseExists = Test-Path -LiteralPath (Join-Path $root 'active-release.json') -PathType Leaf
                    CollectorProcessExists = $processes.Count -gt 0
                    CollectorProcessIds = @($processes | Select-Object -ExpandProperty ProcessId)
                    CollectorSessionIds = @($processes | Select-Object -ExpandProperty SessionId)
                    CollectorTaskExists = $null -ne $task
                    CollectorTaskState = if ($task) { [string]$task.State } else { $null }
                    CollectorTaskLastResult = if ($taskInfo) { $taskInfo.LastTaskResult } else { $null }
                }
            }

        $winrmClass = 'SessionVerified'
    }
    catch {
        $winrmError = $_.Exception.Message

        if ($winrmError -match 'TrustedHosts|authentication scheme|WinRM client cannot process|not trusted') {
            $winrmClass = 'ClientTrustOrAuthenticationConfiguration'
        }
        elseif ($winrmError -match 'Access is denied|Unauthorized|user name or password is incorrect|logon failure') {
            $winrmClass = 'CredentialOrAuthorizationFailure'
        }
        else {
            $winrmClass = 'SessionFailureUnclassified'
        }
    }
    finally {
        if ($session) { Remove-PSSession -Session $session }
    }
}

[pscustomobject]@{
    Classification = $winrmClass
    Error = $winrmError
    RemoteState = $remoteState
}
```

Use this decision table:

| Classification | Meaning | Next action |
|---|---|---|
| `TransportClosed` | WinRM listener, firewall, routing, or bootstrap unavailable | Use approved SMB/local bootstrap path |
| `ClientTrustOrAuthenticationConfiguration` | IPC may already be configured; laptop cannot authenticate by IP | Configure exact-IP `TrustedHosts`, then retry |
| `CredentialOrAuthorizationFailure` | Transport works; credential or authorization is wrong | Correct access; do not rerun bootstrap |
| `SessionFailureUnclassified` | Transport works but failure is unresolved | Preserve exact error and diagnose first |
| `SessionVerified` | Remote administration works | Classify bootstrap, deployment, and runtime independently |

Bootstrap is verified only when the WinRM session succeeds and both setup-state and revert-script markers exist. Marker absence indicates partial state or drift, not automatic permission to rerun setup.

# Phase 2: Stage approved bootstrap files when required

Use SMB only when local bootstrap or recovery requires file staging.

If TCP 445 is closed, stop the SMB path and report that cabling, VLAN, laptop addressing, or approved SMB policy must be checked. Do not assert that the laptop IP is the cause unless verified.

Use the administrative `D$` share, not `D`:

```powershell
$adminCred = Get-Credential -Message 'Enter an authorized IPC administrator credential'
$driveName = "IPC$([guid]::NewGuid().ToString('N').Substring(0, 8))"

try {
    New-PSDrive `
        -Name $driveName `
        -PSProvider FileSystem `
        -Root $adminShareRoot `
        -Credential $adminCred `
        -ErrorAction Stop | Out-Null

    $adapterRoot = "$driveName`:\OEM\Adapter"
    New-Item -ItemType Directory -Force -Path $adapterRoot -ErrorAction Stop | Out-Null

    $markers = [pscustomobject]@{
        SetupStateExists = Test-Path -LiteralPath (Join-Path $adapterRoot 'gleason_ipc_setup_state.json') -PathType Leaf
        RevertScriptExists = Test-Path -LiteralPath (Join-Path $adapterRoot 'revert_gleason_ipc_setup.ps1') -PathType Leaf
        ActiveReleaseExists = Test-Path -LiteralPath (Join-Path $adapterRoot 'active-release.json') -PathType Leaf
    }
    $markers

    if ($markers.SetupStateExists -and $markers.RevertScriptExists -and -not $allowRecoveryRestage) {
        throw 'Bootstrap markers already exist. Verify or reconcile first. Set $allowRecoveryRestage only for a specifically approved recovery that requires replacing both setup files.'
    }

    $setupScriptSource = Join-Path $PWD 'scripts\setup_gleason_ipc.ps1'
    $setupModuleSource = Join-Path $PWD 'scripts\Gleason.IpcSetup.psm1'

    foreach ($source in @($setupScriptSource, $setupModuleSource)) {
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Missing approved setup file: $source"
        }
    }

    $copies = @(
        [pscustomobject]@{ Source = $setupScriptSource; Destination = Join-Path $adapterRoot 'setup_gleason_ipc.ps1' },
        [pscustomobject]@{ Source = $setupModuleSource; Destination = Join-Path $adapterRoot 'Gleason.IpcSetup.psm1' }
    )

    foreach ($copy in $copies) {
        Copy-Item -LiteralPath $copy.Source -Destination $copy.Destination -Force -ErrorAction Stop

        $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $copy.Source -ErrorAction Stop).Hash
        $destinationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $copy.Destination -ErrorAction Stop).Hash

        if ($sourceHash -ne $destinationHash) {
            throw "Hash mismatch for '$($copy.Destination)'."
        }

        [pscustomobject]@{
            Source = $copy.Source
            Destination = $copy.Destination
            SHA256 = $sourceHash
            Verified = $true
        }
    }
}
finally {
    Remove-PSDrive -Name $driveName -Force -ErrorAction SilentlyContinue
}
```

Set `$allowRecoveryRestage = $true` only when a diagnosed, repository-approved recovery explicitly requires replacing both current setup files. This does not authorize deleting or resetting setup state.

If `D$` is intentionally disabled, do not weaken IPC policy. Use an approved share or local transfer method.

# Phase 3: Run elevated bootstrap locally on the IPC

Supply only confirmed values. Keep `RemoteAddress` limited to the approved management host or subnet.

```text
The approved IPC setup script and module were copied to D:\OEM\Adapter and their SHA-256 hashes match the repository files.

Open an elevated PowerShell terminal locally on the IPC and run:

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& 'D:\OEM\Adapter\setup_gleason_ipc.ps1' `
  -IpcIp '<approved-ipv4>' `
  -InterfaceIndex <approved-interface-index> `
  -RemoteAddress '<approved-management-host-or-subnet>'

Return the completion output or exact error. Deployment must not start until bootstrap verification succeeds.
```

Do not guess the interface index or management scope. If setup fails, diagnose or reconcile it locally before deployment.

# Phase 4: Configure the laptop for IP-based WinRM only when required

Run in elevated PowerShell only after classification identifies a client trust/configuration failure:

```powershell
Start-Service WinRM

$trustedHostsPath = 'WSMan:\localhost\Client\TrustedHosts'
$previousTrustedHosts = (Get-Item -Path $trustedHostsPath).Value
$currentEntries = @(
    $previousTrustedHosts -split ',' |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
)

if ($currentEntries -notcontains $ipcIp) {
    $updatedEntries = (@($currentEntries + $ipcIp) | Select-Object -Unique) -join ','
    Set-Item -Path $trustedHostsPath -Value $updatedEntries -Force
}

[pscustomobject]@{
    PreviousTrustedHosts = $previousTrustedHosts
    CurrentTrustedHosts = (Get-Item -Path $trustedHostsPath).Value
}
```

Preserve the previous value and restore it after commissioning when required by local policy:

```powershell
Set-Item -Path 'WSMan:\localhost\Client\TrustedHosts' -Value $previousTrustedHosts -Force
```

# Phase 5: Verify bootstrap, then deploy

Retry the Phase 1 WinRM inspection. Continue only when the session succeeds and both bootstrap markers exist.

Deploy from the repository root:

```powershell
.\deploy.ps1 -Configuration Release
```

Expected repository responsibilities:

- `build.ps1` performs the Release build;
- `deploy.ps1` opens the administrator WinRM session;
- immutable release content is copied into the release structure;
- `active-release.json` selects the active release;
- `Gleason Collector Interactive Start` invokes `D:\OEM\Adapter\launch\start_collector.ps1`;
- the task is requested to start in the approved logged-on HMI/operator session.

The WinRM session may configure and request the task, but it must not host the collector process.

# Phase 6: Verify runtime health

```powershell
[pscustomobject]@{
    WinRMTcp = Test-NetConnection -ComputerName $ipcIp -Port $winrmPort -InformationLevel Quiet
    CollectorTcp = Test-NetConnection -ComputerName $ipcIp -Port $collectorPort -InformationLevel Quiet
    Health = Test-HttpEndpoint -Uri "$collectorBaseUri/health"
    Snapshot = Test-HttpEndpoint -Uri "$collectorBaseUri/snapshot"
}
```

Interpretation:

- `/health` transport success confirms that the endpoint responds. Inspect the body if the application defines a readiness field.
- `/snapshot` failure with healthy `/health` is an adapter, configuration, Siemens-session, or data-availability problem, not a bootstrap failure.
- TCP 8765 success without HTTP success indicates an application or endpoint problem.

# Phase 7: Diagnose collector failures without crossing the runtime boundary

Never execute `Gleason_Collector.exe` directly through WinRM.

```powershell
$adminCred = Get-Credential -Message 'Enter an authorized IPC administrator credential'
$session = New-PSSession `
    -ComputerName $ipcIp `
    -Port $winrmPort `
    -Credential $adminCred `
    -Authentication Negotiate `
    -ErrorAction Stop

try {
    Invoke-Command `
        -Session $session `
        -ArgumentList $adapterRootRemote, $collectorProcessName, $collectorTaskName, $ipcIp, $collectorPort `
        -ErrorAction Stop `
        -ScriptBlock {
            param($root, $processName, $taskName, $targetIp, $targetPort)

            Get-CimInstance Win32_Process -Filter "Name='$processName'" -ErrorAction SilentlyContinue |
                Select-Object ProcessId, SessionId, ExecutablePath, CommandLine

            try {
                $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
                $taskInfo = Get-ScheduledTaskInfo -InputObject $task -ErrorAction Stop

                [pscustomobject]@{
                    TaskName = $task.TaskName
                    State = $task.State
                    LastRunTime = $taskInfo.LastRunTime
                    LastTaskResult = $taskInfo.LastTaskResult
                    Actions = @($task.Actions | Select-Object Execute, Arguments, WorkingDirectory)
                    Principal = $task.Principal
                }
            }
            catch {
                [pscustomobject]@{ TaskName = $taskName; Error = $_.Exception.Message }
            }

            foreach ($url in @("http://127.0.0.1:$targetPort/", "http://$targetIp`:$targetPort/")) {
                "URLACL: $url"
                netsh http show urlacl url=$url
            }

            Get-Content -LiteralPath (Join-Path $root 'logs\collector.error.log') -Tail 100 -ErrorAction SilentlyContinue
            Get-Content -LiteralPath (Join-Path $root 'logs\collector.output.log') -Tail 100 -ErrorAction SilentlyContinue
        }
}
finally {
    Remove-PSSession -Session $session
}
```

Verify that the collector runs in the logged-on HMI/operator session. A project-defined fixed session ID is an explicit invariant, not a general assumption.

# Troubleshooting order

Stop when the first failed layer is established:

1. **TCP 445 closed and staging is required:** check cabling, VLAN, approved laptop addressing, or SMB policy.
2. **TCP 5985 closed:** listener, firewall, routing, or bootstrap is incomplete.
3. **TCP 5985 open; client trust/configuration failure:** add only the exact IPC IP to `TrustedHosts`, then retry.
4. **TCP 5985 open; access denied:** correct credential or authorization. Do not rerun bootstrap or modify the task.
5. **Setup state unreadable or reports failure:** preserve it and use the repository-approved local reconcile/revert process. Never delete it.
6. **Setup module reports an empty loopback URLACL as unparsable:** stage both current approved setup files, reconcile, and rerun only the scoped setup required by the repository.
7. **`HttpListenerException: Access is denied`:** compare loopback and IPC-address URLACLs with the repository-approved runtime identity. Do not broaden ACLs by default. Confirm active-release configuration contains the required external and loopback API URLs.
8. **Task exists or reports running but no process exists:** inspect task result, action, launcher logs, and the actual logged-on HMI/operator session.
9. **Collector process is in the wrong session:** repair task/session targeting. Do not start it through WinRM.
10. **`/health` works but `/snapshot` fails:** diagnose adapter configuration, Siemens data availability, or runtime integration.

# Documentation updates

When verified facts change, update:

- `AGENTS.md` for durable agent and development instructions;
- `FINDINGS.md` for observed evidence and diagnosed facts;
- `NEXT_STEPS.md` for unresolved blockers and concrete actions.

Record timestamps, exact commands, observed status, relevant paths, task/session details, and staged-file hashes. Never record credentials or secrets. Do not state that bootstrap, deployment, or runtime is complete unless its corresponding verification succeeded.