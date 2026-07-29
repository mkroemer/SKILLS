# IPC SMB and WinRM Bootstrap

Human-facing guide for the `ipc-smb-winrm-bootstrap` Agent Skill.

## What it does

This is an instruction-focused skill for preparing, classifying, verifying, diagnosing, and recovering remote administration and collector deployment on a Siemens SINUMERIK ONE IPC.

It keeps four states separate:

1. network reachability;
2. elevated IPC bootstrap;
3. administrator deployment and scheduled-task configuration;
4. interactive Siemens runtime and collector health.

The skill is intended to prevent unnecessary bootstrap reruns when the real failure is authentication, deployment, scheduled-task startup, collector runtime, URLACL configuration, or an adapter dependency.

## Requirements

- A Windows engineering or service workstation with PowerShell.
- An authorized IPC administrator credential supplied through an approved secret channel.
- Confirmed IPC address, interface index, and narrow management host or subnet.
- Approved local/VNC access for elevated bootstrap execution.
- A consuming project containing the reviewed deployment files referenced by the skill, including:

  ```text
  scripts/setup_gleason_ipc.ps1
  scripts/Gleason.IpcSetup.psm1
  build.ps1
  deploy.ps1
  ```

- Network policy permitting only the approved SMB, WinRM, and collector paths.

This skill does not bundle those project-specific bootstrap and deployment files. Install it project-locally in the repository that owns them.

## Install in a consuming project

Portable Agent Skills location:

```powershell
New-Item -ItemType Directory -Force '.agents\skills' | Out-Null
Copy-Item -Recurse `
  '<path-to-SKILLS>\ipc-smb-winrm-bootstrap' `
  '.agents\skills\ipc-smb-winrm-bootstrap'
```

OpenCode-specific placement is also supported:

```powershell
New-Item -ItemType Directory -Force '.opencode\skills' | Out-Null
Copy-Item -Recurse `
  '<path-to-SKILLS>\ipc-smb-winrm-bootstrap' `
  '.opencode\skills\ipc-smb-winrm-bootstrap'
```

The directory containing `SKILL.md` should remain named `ipc-smb-winrm-bootstrap`.

## How to use it

Ask the agent to load the skill before changing the IPC. Example requests:

```text
Use ipc-smb-winrm-bootstrap to classify the current IPC state before making changes.
```

```text
Use ipc-smb-winrm-bootstrap to determine whether this is a network, bootstrap, deployment, or runtime failure.
```

```text
Use ipc-smb-winrm-bootstrap to prepare the approved local bootstrap command after verifying the staged file hashes.
```

The skill provides the required PowerShell probes, classification tables, staging sequence, elevated bootstrap instructions, deployment checks, runtime checks, and recovery boundaries directly in [`SKILL.md`](SKILL.md).

## Required workflow

### 1. Classify without changing the IPC

Probe and report these independently:

| Layer | Typical evidence |
|---|---|
| Network | TCP 445, 5985, and 8765 |
| Bootstrap | authenticated WinRM session, setup-state marker, revert script |
| Deployment | `active-release.json`, interactive scheduled task |
| Runtime | collector process/session, `/health`, `/snapshot` |

A failed ping alone is not decisive. A closed collector port does not prove that bootstrap is missing. A reachable WinRM port with failed authentication is an access problem, not permission to restage setup files.

### 2. Stage only reviewed bootstrap files

Use SMB only when WinRM transport is closed and file staging is justified. Copy the consuming project's approved setup script and module, then compare SHA-256 hashes before local execution.

Do not reconstruct setup code from chat, documentation fragments, or memory.

### 3. Run bootstrap locally and elevated

Bootstrap is executed locally on the IPC, normally through an elevated PowerShell window reached through the approved interactive method. Supply only confirmed values for the IPC address, interface index, and management network scope.

### 4. Deploy through the approved project scripts

After bootstrap verification, use the consuming project's reviewed build and deployment scripts. Do not replace deployment automation with manual release copies.

### 5. Start Siemens-dependent runtime interactively

The collector must run through the approved interactive scheduled task in the logged-on HMI/operator session. WinRM may inspect or configure the task, but it must not host Siemens-dependent collector code in session 0.

## Safety boundaries

- Never print, embed, log, or document passwords.
- Require credential rotation before commissioning when the project policy requires it.
- Do not set `TrustedHosts` to `*`.
- Do not broaden firewall or URLACL scope automatically.
- Do not delete setup state to force a clean bootstrap.
- Do not assume a fixed HMI session ID unless the consuming project explicitly defines one.
- Do not rerun bootstrap merely because deployment or runtime is unhealthy.
- Do not claim success without the corresponding verification evidence.

## Verification and reporting

A completion report must state the first failed layer and the next justified action. Report bootstrap, deployment, and runtime independently rather than collapsing them into a single status.

Successful bootstrap requires a verified WinRM session plus the expected setup-state and revert markers. Successful deployment requires the expected active release and interactive task. Successful runtime requires process/session evidence and healthy collector endpoints.

## Agent documentation

- [`SKILL.md`](SKILL.md) — complete classification, bootstrap, deployment, diagnosis, and recovery procedure.
- [`../AGENTS.md`](../AGENTS.md) — repository-wide documentation and maintenance requirements.
