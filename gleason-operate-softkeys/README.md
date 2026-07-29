# Gleason Operate Softkeys

Human-facing guide for the `gleason-operate-softkeys` Agent Skill.

## What it does

This skill manages generic SINUMERIK Operate OEM operating-area softkeys. It can:

- inspect skill-owned softkeys;
- add a new softkey from a machine-safe label, transparent PNG, and IPC executable path;
- update an existing owned softkey;
- delete an existing owned softkey;
- apply a reviewed change through WinRM or stage it through SMB for local execution.

For the existing application-specific `GleasonVPC` integration, use the versioned collector installation procedure in the consuming project's `docs/operate-softkeys.md` rather than this generic helper.

## Requirements

- A Windows workstation with PowerShell.
- A SINUMERIK Operate IPC reachable through the approved management network.
- The companion [`gleason-winrm-connect`](../gleason-winrm-connect/) skill.
- An authorized `GLEASON` administrator credential.
- The consuming project's reviewed `docs/operate-softkeys.md`.
- For add/update: a local transparent PNG logo, the absolute `.exe` path on the IPC, and the exact managed window title.
- VNC access when WinRM is closed and SMB staging must be executed locally.

The orchestrator currently resolves the connection helper at:

```text
<project-root>\.opencode\skills\gleason-winrm-connect\scripts\Connect-GleasonWinRM.ps1
```

Therefore both skills must be installed project-locally under `.opencode\skills` for the complete workflow. A global-only or `.agents`-only installation will not satisfy this hardcoded companion path.

## Install in a consuming project

From the project root:

```powershell
New-Item -ItemType Directory -Force '.opencode\skills' | Out-Null
Copy-Item -Recurse `
  '<path-to-SKILLS>\gleason-winrm-connect' `
  '.opencode\skills\gleason-winrm-connect'
Copy-Item -Recurse `
  '<path-to-SKILLS>\gleason-operate-softkeys' `
  '.opencode\skills\gleason-operate-softkeys'
```

Review the consuming project's `docs\operate-softkeys.md` before contacting an IPC.

## Run the orchestrator

```powershell
& '.\.opencode\skills\gleason-operate-softkeys\scripts\Manage-GleasonOperateSoftkey.ps1'
```

The script prompts for the IPC address and one of these actions:

- `Inspect`
- `Add`
- `Update`
- `Delete`

For add or update, provide:

1. a label/area ID containing only letters, digits, and `_`, with no spaces;
2. a local transparent PNG file;
3. an absolute executable path on the IPC;
4. optional program arguments;
5. the exact managed window title.

Review the generated JSON plan and type `APPLY` only when every value is correct.

Labels with spaces or translated text require separately reviewed `TextId`, `TextFile`, `TextContext`, and compiled language resources. The generic helper rejects these cases instead of producing incomplete localization.

## Transport behavior

The orchestrator tries the verified `GLEASON` WinRM connection first.

- If TCP 5985 is reachable but authentication fails, correct the access problem. SMB is not an authentication bypass.
- If TCP 5985 is closed and TCP 445 is reachable, the helper stages the apply script, plan, and logo under a unique transaction directory in `D:\OEM\Temp\OperateSoftkeys`.
- Staged files are SHA-256 checked. An administrator must run the exact printed command locally through VNC.
- If neither WinRM nor SMB is reachable, no configuration is staged.

## Managed configuration

The IPC helper is limited to these paths:

```text
C:\ProgramData\Siemens\MotionControl\oem\sinumerik\hmi\cfg\systemconfiguration.ini
C:\ProgramData\Siemens\MotionControl\oem\sinumerik\hmi\cfg\slamconfig.ini
C:\ProgramData\Siemens\MotionControl\oem\sinumerik\hmi\ico\ico1024
```

It reserves matching `PROC`/`AREA` IDs from 500–999 and softkey positions from 9–64. Positions 1–8 and unrelated OEM entries are preserved. Ownership manifests and timestamped backups are stored under:

```text
C:\ProgramData\Gleason\OperateSoftkeys
```

Update and delete operations require the ownership manifest and exact current values. Drift or collisions cause a refusal rather than an overwrite.

## Safety boundaries

- Do not infer the executable path, arguments, window title, label, or logo.
- Do not edit `compat\user\OEMFRAME.INI` through this generic skill.
- Do not reuse another integration's IDs, icon, or ownership metadata.
- Do not bypass an authentication failure with direct share editing.
- Do not start or restart SINUMERIK Operate or Siemens-dependent programs through WinRM/session 0.
- Keep transaction backups until the operator completes interactive validation.

## Verification

After a successful write, restart SINUMERIK Operate from the logged-on HMI session and verify:

1. existing OEM keys remain intact;
2. the new or changed key is in the intended position;
3. the icon is correct;
4. the intended executable opens;
5. the managed window is embedded or handled as expected;
6. no configuration warning is displayed.

## Agent and maintainer documentation

- [`SKILL.md`](SKILL.md) — agent workflow and operational boundaries.
- [`AGENTS.md`](AGENTS.md) — maintenance requirements for the scripts.
