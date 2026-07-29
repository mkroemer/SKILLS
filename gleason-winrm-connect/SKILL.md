---
name: gleason-winrm-connect
description: Connect to the Gleason IPC through WinRM as AUDUSER or GLEASON, prompt for and securely retain credentials after successful authentication, or stage the approved scoped IPC bootstrap through SMB/VNC when WinRM is unavailable. Use for WinRM login, saved IPC credentials, AUDUSER/GLEASON access, or first-connection recovery.
---

# Gleason WinRM Connection

Use the scripts in this skill instead of embedding passwords or improvising
firewall changes. Run all client scripts from the repository root.

## Boundaries

- `GLEASON` is the expected administrator identity for setup and deployment.
- `AUDUSER` is the interactive HMI/operator identity. Test it only when that
  access is specifically required; do not grant it administrator rights.
- A credential is stored only after `New-PSSession` authenticates successfully.
  The CLIXML secret is protected by Windows DPAPI for the current user and
  machine and is stored under `%LOCALAPPDATA%\Gleason\WinRM`, never in the repo.
- Never print, log, commit, or place passwords in command arguments.
- Never run Siemens-dependent collector/controller code in WinRM/session 0.
- Do not create broad firewall rules, use `TrustedHosts=*`, call
  `Enable-PSRemoting`, delete setup state, or replace the approved setup module.

## Connect

```powershell
& '.\.opencode\skills\gleason-winrm-connect\scripts\Connect-GleasonWinRM.ps1'
```

The script prompts for the IPC address and `AUDUSER`/`GLEASON`, reuses a saved
credential when possible, retries with a login prompt after authentication
failure, verifies the remote identity, and then returns a result containing the
live `Session`. Add `-EnterSession` for an interactive prompt.

Useful options:

```powershell
# Select the administrator account explicitly.
& '.\.opencode\skills\gleason-winrm-connect\scripts\Connect-GleasonWinRM.ps1' `
  -ComputerName '192.168.214.241' -UserName GLEASON -EnterSession

# Authenticate without retaining the newly entered credential.
& '.\.opencode\skills\gleason-winrm-connect\scripts\Connect-GleasonWinRM.ps1' `
  -UserName AUDUSER -NoCredentialStore

# Remove the protected credential for this host/account.
& '.\.opencode\skills\gleason-winrm-connect\scripts\Connect-GleasonWinRM.ps1' `
  -UserName GLEASON -ForgetCredential
```

If IP-based Negotiate authentication reports a client trust error, rerun from
an elevated local PowerShell with `-ConfigureTrustedHost`. This adds only the
selected IPC address and preserves existing entries.

## WinRM transport unavailable

First confirm TCP 5985 is closed. A failed login with open TCP 5985 is a
credential/authorization problem and is **not** a reason to bootstrap.

Stage the repository-approved setup pair and local CMD launcher over the
approved `D` share (with `D$` as a fallback only when available):

```powershell
& '.\.opencode\skills\gleason-winrm-connect\scripts\Stage-GleasonWinRMBootstrap.ps1'
```

Then use VNC to open an elevated CMD on the IPC and run:

```cmd
D:\OEM\Adapter\run_gleason_ipc_setup.cmd
```

If SMB cannot be used, generate an exact clipboard block from the current
approved repository files:

```powershell
& '.\.opencode\skills\gleason-winrm-connect\scripts\New-GleasonWinRMVncPaste.ps1'
```

Paste the generated block into an **elevated PowerShell** window through VNC.
It writes and hash-verifies the approved setup files under `D:\OEM\Adapter`
before invoking setup. Review the IPC address and management subnet first.
Both fallback helpers stop when existing setup/revert state is present. Use
`-AllowRecoveryRestage` only for a diagnosed and specifically approved recovery;
it never authorizes deleting or resetting setup state.

The setup requires an existing reviewed HTTP WinRM listener. If it reports a
missing listener or conflicting setup state, preserve the exact error and use
the repository recovery procedure; do not broaden configuration manually.

## Verification and reporting

After setup, rerun `Connect-GleasonWinRM.ps1 -UserName GLEASON`. Report these
layers separately: TCP 445/5985/8765, authenticated WinRM identity, setup-state
and revert markers, active release/task, and collector HTTP health. Do not call
bootstrap, deployment, or runtime successful without corresponding evidence.

Read `AGENTS.md` in this skill directory before changing these scripts.
