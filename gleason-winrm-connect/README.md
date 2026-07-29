# Gleason WinRM Connection

Human-facing guide for the `gleason-winrm-connect` Agent Skill.

## What it does

This skill provides guarded PowerShell helpers for:

- connecting to a Gleason IPC through WinRM as `AUDUSER` or `GLEASON`;
- retaining a credential only after successful authentication;
- entering an interactive PowerShell session when explicitly requested;
- adding one exact IPC address to the local WinRM trusted-host list when required;
- staging the repository-approved IPC bootstrap through SMB when WinRM transport is closed;
- generating a VNC paste block when SMB staging is unavailable.

It separates transport failures from credential and authorization failures. An open TCP 5985 endpoint with failed authentication is not a reason to rerun bootstrap.

## Requirements

- A Windows workstation with PowerShell.
- Network access to the target IPC.
- An authorized `AUDUSER` or `GLEASON` credential.
- VNC access for bootstrap execution when WinRM is unavailable.
- For SMB/VNC bootstrap staging, the consuming project must contain these reviewed files at its repository root:

  ```text
  scripts/setup_gleason_ipc.ps1
  scripts/Gleason.IpcSetup.psm1
  ```

The staging helpers calculate the consuming repository root from the skill's project-local location. Install the skill inside the target project when bootstrap staging is required. A global installation is suitable only for connection operations that do not depend on those project files.

## Install for an Agent Skills consumer

Project-local portable installation:

```powershell
New-Item -ItemType Directory -Force '.agents\skills' | Out-Null
Copy-Item -Recurse `
  '<path-to-SKILLS>\gleason-winrm-connect' `
  '.agents\skills\gleason-winrm-connect'
```

The scripts can also be installed under `.opencode\skills\gleason-winrm-connect`. Use that location when another project helper explicitly resolves the OpenCode-specific path.

## Connect through WinRM

From the consuming project root:

```powershell
& '.\.agents\skills\gleason-winrm-connect\scripts\Connect-GleasonWinRM.ps1'
```

Select the administrator account and enter the remote session:

```powershell
& '.\.agents\skills\gleason-winrm-connect\scripts\Connect-GleasonWinRM.ps1' `
  -ComputerName '192.168.214.241' `
  -UserName GLEASON `
  -EnterSession
```

Authenticate without storing a newly entered credential:

```powershell
& '.\.agents\skills\gleason-winrm-connect\scripts\Connect-GleasonWinRM.ps1' `
  -UserName AUDUSER `
  -NoCredentialStore
```

Remove the protected credential for one host/account pair:

```powershell
& '.\.agents\skills\gleason-winrm-connect\scripts\Connect-GleasonWinRM.ps1' `
  -UserName GLEASON `
  -ForgetCredential
```

Credentials are stored only after a successful `New-PSSession` authentication. The CLIXML credential is protected by Windows DPAPI for the current user and machine under `%LOCALAPPDATA%\Gleason\WinRM`; it is never stored in this repository.

## When WinRM transport is closed

First verify that TCP 5985 is actually closed. If authentication fails while the port is reachable, correct the credential or authorization problem instead of using the bootstrap path.

Stage the approved setup files over SMB:

```powershell
& '.\.agents\skills\gleason-winrm-connect\scripts\Stage-GleasonWinRMBootstrap.ps1'
```

After successful staging and SHA-256 verification, use VNC to open an elevated CMD window on the IPC and run:

```cmd
D:\OEM\Adapter\run_gleason_ipc_setup.cmd
```

When SMB cannot be used, generate the reviewed VNC clipboard block:

```powershell
& '.\.agents\skills\gleason-winrm-connect\scripts\New-GleasonWinRMVncPaste.ps1'
```

Review the IPC address and management network before pasting it into an elevated PowerShell window on the IPC.

## Safety boundaries

- Do not print, log, commit, or pass passwords as command-line arguments.
- Do not grant `AUDUSER` administrator rights.
- Do not use `TrustedHosts=*`, broad firewall rules, or `Enable-PSRemoting`.
- Do not delete setup-state or revert markers to force another bootstrap.
- Do not run Siemens-dependent collector or controller code inside WinRM/session 0.
- Use `-AllowRecoveryRestage` only for a diagnosed and explicitly approved recovery.

## Verification

After setup or credential correction, reconnect as `GLEASON` and report these layers separately:

1. TCP reachability for ports 445, 5985, and 8765.
2. Authenticated WinRM identity.
3. Setup-state and revert markers.
4. Active release and scheduled task.
5. Collector HTTP health.

Do not describe bootstrap, deployment, or runtime as successful without evidence for the corresponding layer.

## Agent and maintainer documentation

- [`SKILL.md`](SKILL.md) — agent workflow and operational boundaries.
- [`AGENTS.md`](AGENTS.md) — maintenance requirements for these scripts.
