---
name: sinumerik-ipc-connect
description: Connect to a configured SINUMERIK IPC through WinRM with verified account identity and optional DPAPI-protected credential reuse, or stage approved profile-defined bootstrap files through SMB or an interactive paste block when WinRM transport is closed. Use for SINUMERIK IPC login, named IPC profiles, saved Windows credentials, exact-host trust configuration, approved bootstrap staging, or first-connection recovery.
---

# SINUMERIK IPC Connection

Use named profiles from `sinumerik-ipc-profiles` or supply explicit connection
parameters. Never embed passwords or improvise firewall changes.

## Boundaries

- Resolve hostnames/IPs, account roles, ports, paths, and approved bootstrap
  files from the selected profile. Let explicit parameters override it.
- A credential is stored only after `New-PSSession` authenticates successfully.
  The CLIXML secret is protected by Windows DPAPI for the current user and
  machine under `%LOCALAPPDATA%\SinumerikSkills\WinRM`, never in a profile or
  repository.
- Verify that the authenticated account matches the selected profile account.
  Do not assume the operator account is an administrator.
- Never print, log, commit, or place passwords in command arguments.
- Never run Siemens-dependent application or controller code in WinRM/session
  0.
- Do not create broad firewall rules, use `TrustedHosts=*`, call
  `Enable-PSRemoting`, delete setup state, or replace the approved setup module.

## Connect

```powershell
& '.\.agents\skills\sinumerik-ipc-connect\scripts\Connect-SinumerikIpc.ps1' `
  -Profile 'example-ipc'
```

The script resolves the selected role and account, reuses a saved credential
when possible, retries with a secure prompt after authentication failure,
verifies the remote identity, and returns a live `Session`. Add `-EnterSession`
for an interactive prompt.

Useful options:

```powershell
# Select a configured role.
& '.\.agents\skills\sinumerik-ipc-connect\scripts\Connect-SinumerikIpc.ps1' `
  -Profile 'example-ipc' -Role administrator -EnterSession

# Authenticate without retaining the newly entered credential.
& '.\.agents\skills\sinumerik-ipc-connect\scripts\Connect-SinumerikIpc.ps1' `
  -Profile 'example-ipc' -Role operator -NoCredentialStore

# Remove the protected credential for this host/account.
& '.\.agents\skills\sinumerik-ipc-connect\scripts\Connect-SinumerikIpc.ps1' `
  -Profile 'example-ipc' -Role administrator -ForgetCredential
```

If IP-based Negotiate authentication reports a client trust error, rerun from
an elevated local PowerShell with `-ConfigureTrustedHost`. This adds only the
selected IPC address and preserves existing entries.

## WinRM transport unavailable

First confirm the configured WinRM port is closed. A failed login with an open
WinRM port is a
credential/authorization problem and is **not** a reason to bootstrap.

Stage only the files listed in the selected profile, resolving their source
paths below the reviewed consuming-project root:

```powershell
& '.\.agents\skills\sinumerik-ipc-connect\scripts\Stage-SinumerikIpcBootstrap.ps1' `
  -Profile 'example-ipc' -SourceRoot $PWD
```

If SMB cannot be used, generate an exact clipboard block from those same
reviewed files:

```powershell
& '.\.agents\skills\sinumerik-ipc-connect\scripts\New-SinumerikIpcBootstrapPaste.ps1' `
  -Profile 'example-ipc' -SourceRoot $PWD
```

Paste the generated block into an **elevated PowerShell** window through the
approved interactive method. It writes and hash-verifies the approved setup
files before invoking the structured profile-defined entry script. Review the
target and management scope first. Both fallback helpers stop when configured
setup/revert markers are present. Use
`-AllowRecoveryRestage` only for a diagnosed and specifically approved recovery;
it never authorizes deleting or resetting setup state.

## Verification and reporting

After setup, reconnect with the configured administrator role. Report network,
authenticated identity, bootstrap markers, deployment, and optional runtime
health independently. Do not call a layer successful without its configured
evidence.

Read `AGENTS.md` in this skill directory before changing these scripts.
