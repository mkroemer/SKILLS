# SINUMERIK Operate Softkeys

Human-facing guide for the `sinumerik-operate-softkeys` Agent Skill.

## What it does

This skill manages generic SINUMERIK Operate OEM operating-area softkeys. It can:

- inspect skill-owned softkeys;
- add a new softkey from a machine-safe label, transparent PNG, and IPC executable path;
- update an existing owned softkey;
- delete an existing owned softkey;
- apply a reviewed change through WinRM or stage it through SMB for local execution.

It is organization-neutral and does not assume a fixed IPC address, Windows account, companion connection skill, or consuming-project layout.

## Requirements

- A Windows workstation with PowerShell.
- A SINUMERIK Operate IPC reachable through the approved management network.
- An authorized IPC administrator credential entered through PowerShell's secure credential prompt or supplied as a `PSCredential`.
- Confirmed SINUMERIK Operate configuration paths for the target version.
- For add/update: a local PNG icon, the absolute `.exe` path on the IPC, and the exact managed window title.
- An approved interactive remote desktop method when WinRM is closed and SMB staging must be executed locally.

## Install in a consuming project

From the project root:

```powershell
New-Item -ItemType Directory -Force '.agents\skills' | Out-Null
Copy-Item -Recurse `
  '<path-to-SKILLS>\sinumerik-operate-softkeys' `
  '.agents\skills\sinumerik-operate-softkeys'
```

OpenCode-specific `.opencode\skills` placement is also supported because the scripts resolve their helpers relative to their own directory.

## Run the orchestrator

```powershell
& '.\.agents\skills\sinumerik-operate-softkeys\scripts\Manage-SinumerikOperateSoftkey.ps1'
```

The script prompts for the IPC address, action, and administrator credential. It does not persist the credential. You can also pass a credential supplied by an approved secret-management workflow:

```powershell
$credential = Get-Credential
& '.\.agents\skills\sinumerik-operate-softkeys\scripts\Manage-SinumerikOperateSoftkey.ps1' `
  -ComputerName 'ipc-hostname' `
  -Action Inspect `
  -Credential $credential
```

Supported actions are:

- `Inspect`
- `Add`
- `Update`
- `Delete`

For add or update, provide:

1. a label/area ID containing only letters, digits, and `_`, with no spaces;
2. a local PNG file;
3. an absolute executable path on the IPC;
4. optional program arguments;
5. the exact managed window title.

Review the generated JSON plan and type `APPLY` only when every value is correct.

Labels with spaces or translated text require separately reviewed `TextId`, `TextFile`, `TextContext`, and compiled language resources. The generic helper rejects these cases instead of producing incomplete localization.

## Transport behavior

The orchestrator probes the configured WinRM endpoint first and verifies that the authenticated remote identity is an administrator.

- If WinRM is reachable but authentication or authorization fails, correct the access problem. SMB is not an authentication bypass.
- If the configured WinRM port is closed and TCP 445 is reachable, the helper stages the apply script, plan, and icon under a unique transaction directory in `D:\OEM\Temp\OperateSoftkeys`.
- Staged files are SHA-256 checked. An administrator must run the exact printed command locally through the approved interactive remote desktop method.
- If neither WinRM nor SMB is reachable, no configuration is staged.

The defaults support WinRM HTTP on port 5985. Use `-UseSsl -WinRmPort 5986` for an approved HTTPS listener. Use `-RemoteStagingRoot` only when the IPC uses another approved drive-root staging location.

## Managed configuration

The IPC helper is limited to these paths:

```text
C:\ProgramData\Siemens\MotionControl\oem\sinumerik\hmi\cfg\systemconfiguration.ini
C:\ProgramData\Siemens\MotionControl\oem\sinumerik\hmi\cfg\slamconfig.ini
C:\ProgramData\Siemens\MotionControl\oem\sinumerik\hmi\ico\ico1024
```

It reserves matching `PROC`/`AREA` IDs from 500–999 and softkey positions from 9–64. Positions 1–8 and unrelated OEM entries are preserved. Ownership manifests and timestamped backups are stored under:

```text
C:\ProgramData\SinumerikOperateSoftkeys
```

Update and delete operations require the ownership manifest and exact current values. Drift or collisions cause a refusal rather than an overwrite.

Entries created by an older or separately namespaced tool are not adopted automatically. If they have compatible ownership manifests, specify their existing approved root explicitly:

```powershell
& '.\.agents\skills\sinumerik-operate-softkeys\scripts\Manage-SinumerikOperateSoftkey.ps1' `
  -OwnershipRoot 'C:\ProgramData\ExistingOwner\OperateSoftkeys'
```

## Safety boundaries

- Do not infer the executable path, arguments, window title, label, or logo.
- Do not edit `compat\user\OEMFRAME.INI` through this generic skill.
- Do not reuse another integration's IDs, icon, or ownership metadata.
- Do not bypass an authentication failure with direct share editing.
- Do not start or restart SINUMERIK Operate or Siemens-dependent programs through WinRM/session 0.
- Keep transaction backups until the operator completes interactive validation.
- Do not place a password in a command, JSON plan, log, script, or repository.

## Verification

Run the offline lifecycle test on a Windows workstation before using a changed helper:

```powershell
& '.\.agents\skills\sinumerik-operate-softkeys\tests\Test-SinumerikOperateSoftkey.ps1'
```

The test uses an isolated temporary configuration tree and does not contact an IPC.

After a successful write, restart SINUMERIK Operate from the logged-on HMI session and verify:

1. existing OEM keys remain intact;
2. the new or changed key is in the intended position;
3. the icon is correct;
4. the intended executable opens;
5. the managed window is embedded or handled as expected;
6. no configuration warning is displayed.

## Agent and maintainer documentation

- [`SKILL.md`](SKILL.md) - agent workflow and operational boundaries.
- [`AGENTS.md`](AGENTS.md) - maintenance requirements for the scripts.
- [`tests/Test-SinumerikOperateSoftkey.ps1`](tests/Test-SinumerikOperateSoftkey.ps1) - offline add/inspect/update/delete lifecycle test.
