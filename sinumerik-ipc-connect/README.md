# SINUMERIK IPC Connection

Human-facing guide for the `sinumerik-ipc-connect` Agent Skill.

## What it does

This skill provides guarded PowerShell helpers for:

- connecting to a named or explicitly supplied SINUMERIK IPC through WinRM;
- resolving account roles and transport settings from a shared IPC profile;
- retaining a credential only after successful authentication;
- entering an interactive PowerShell session when explicitly requested;
- adding one exact IPC address to the local WinRM trusted-host list when required;
- staging profile-approved IPC bootstrap files through SMB when WinRM transport is closed;
- generating an interactive paste block when SMB staging is unavailable.

It separates transport failures from credential and authorization failures. An
open WinRM endpoint with failed authentication is not a reason to rerun
bootstrap.

## Requirements

- A Windows workstation with PowerShell.
- Network access to the target IPC.
- An authorized account defined in the selected profile or supplied explicitly.
- The companion [`sinumerik-ipc-profiles`](../sinumerik-ipc-profiles/) skill when using named profiles.
- An approved interactive remote method for local elevated bootstrap execution.
- A reviewed source root containing every file mapped by the selected profile.

## Install for an Agent Skills consumer

Project-local portable installation:

```powershell
New-Item -ItemType Directory -Force '.agents\skills' | Out-Null
Copy-Item -Recurse `
  '<path-to-SKILLS>\sinumerik-ipc-profiles' `
  '.agents\skills\sinumerik-ipc-profiles'
Copy-Item -Recurse `
  '<path-to-SKILLS>\sinumerik-ipc-connect' `
  '.agents\skills\sinumerik-ipc-connect'
```

The scripts also work when both skills are installed as siblings under another
supported Agent Skills location.

## Connect through WinRM

From the consuming project root:

```powershell
& '.\.agents\skills\sinumerik-ipc-connect\scripts\Connect-SinumerikIpc.ps1' `
  -Profile 'example-ipc'
```

Select a configured role and enter the remote session:

```powershell
& '.\.agents\skills\sinumerik-ipc-connect\scripts\Connect-SinumerikIpc.ps1' `
  -Profile 'example-ipc' -Role administrator -EnterSession
```

Authenticate without storing a newly entered credential:

```powershell
& '.\.agents\skills\sinumerik-ipc-connect\scripts\Connect-SinumerikIpc.ps1' `
  -Profile 'example-ipc' -Role operator `
  -NoCredentialStore
```

Remove the protected credential for one host/account pair:

```powershell
& '.\.agents\skills\sinumerik-ipc-connect\scripts\Connect-SinumerikIpc.ps1' `
  -Profile 'example-ipc' -Role administrator `
  -ForgetCredential
```

Credentials are stored only after a successful `New-PSSession`
authentication. The CLIXML credential is protected by Windows DPAPI for the
current user and machine under `%LOCALAPPDATA%\SinumerikSkills\WinRM`; it is
never stored in the profile or repository.

After initializing the optional Gleason preset, use
`-Profile 'gleason-standard'`. When that profile remains the default, the
`-Profile` parameter can be omitted.

Credentials previously stored under `%LOCALAPPDATA%\Gleason\WinRM` are not
adopted automatically. Reconnect once with the generic skill to create the new
protected entry, then remove obsolete files only after the new connection is
verified.

## When WinRM transport is closed

First verify that the configured WinRM port is actually closed. If
authentication fails while the port is reachable, correct the credential or
authorization problem instead of using the bootstrap path.

Stage the approved setup files over SMB:

```powershell
& '.\.agents\skills\sinumerik-ipc-connect\scripts\Stage-SinumerikIpcBootstrap.ps1' `
  -Profile 'example-ipc' -SourceRoot $PWD
```

After successful staging and SHA-256 verification, run the exact printed
commands in an elevated PowerShell window on the IPC. The staging helper reuses
an existing protected WinRM credential for the same host/account when
available; it never stores a newly entered SMB credential.

When SMB cannot be used, generate the reviewed interactive clipboard block:

```powershell
& '.\.agents\skills\sinumerik-ipc-connect\scripts\New-SinumerikIpcBootstrapPaste.ps1' `
  -Profile 'example-ipc' -SourceRoot $PWD
```

Review the target, management network, file hashes, and generated command
before pasting it into an elevated PowerShell window on the IPC.

## Safety boundaries

- Do not print, log, commit, or pass passwords as command-line arguments.
- Do not grant a configured operator account administrator rights.
- Do not use `TrustedHosts=*`, broad firewall rules, or `Enable-PSRemoting`.
- Do not delete setup-state or revert markers to force another bootstrap.
- Do not run Siemens-dependent application or controller code inside
  WinRM/session 0.
- Use `-AllowRecoveryRestage` only for a diagnosed and explicitly approved recovery.

## Verification

Run the offline profile, paste-generation, and credential-removal test before
using changed helpers:

```powershell
& '.\.agents\skills\sinumerik-ipc-connect\tests\Test-SinumerikIpcConnect.ps1'
```

The test uses temporary files and does not contact an IPC.

After setup or credential correction, reconnect with the configured
administrator role and report these layers separately:

1. TCP reachability for SMB, configured WinRM, and optional runtime ports.
2. Authenticated WinRM identity.
3. Configured setup-state and revert markers.
4. Optional active release and scheduled task.
5. Optional runtime endpoint health.

Do not describe bootstrap, deployment, or runtime as successful without evidence for the corresponding layer.

## Agent and maintainer documentation

- [`SKILL.md`](SKILL.md) — agent workflow and operational boundaries.
- [`AGENTS.md`](AGENTS.md) — maintenance requirements for these scripts.
- [`tests/Test-SinumerikIpcConnect.ps1`](tests/Test-SinumerikIpcConnect.ps1) - offline helper integration test.
