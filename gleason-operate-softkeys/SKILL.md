---
name: gleason-operate-softkeys
description: Add, update, inspect, or delete SINUMERIK Operate OEM softkeys by prompting for the label, PNG logo, and IPC program, connecting with gleason-winrm-connect first, and using approved SMB staging when WinRM transport is unavailable. Use for Operate softkey, ProgramData OEM menu, systemconfiguration.ini, or slamconfig.ini changes.
---

# Gleason Operate Softkeys

Use this skill for generic, skill-owned SINUMERIK Operate operating-area
softkeys. For the repository's existing `GleasonVPC` key, prefer the versioned
collector installer documented in `docs/operate-softkeys.md`.

## Required workflow

1. Read `docs/operate-softkeys.md` before changing an IPC.
2. Run the client orchestrator from the repository root:

   ```powershell
   & '.\.opencode\skills\gleason-operate-softkeys\scripts\Manage-GleasonOperateSoftkey.ps1'
   ```

3. Select `Inspect`, `Add`, `Update`, or `Delete`.
4. For add/update, obtain these inputs from the user rather than guessing:
   - machine-safe label/area ID (letters, digits, `_`; no spaces);
   - local transparent PNG logo;
   - absolute program `.exe` path on the IPC;
   - optional program arguments and exact managed window title.
5. Review the displayed plan and obtain explicit confirmation.
6. After a successful write, tell the operator to restart SINUMERIK Operate
   from the interactive HMI session and verify existing keys, position, icon,
   launched window, and absence of configuration warnings.

Labels containing spaces or translations require approved `TextId`,
`TextFile`, `TextContext`, and compiled Qt/Siemens language resources. This
generic helper intentionally rejects spaces rather than creating incomplete
localization.

## Connection order

The orchestrator calls the `gleason-winrm-connect` helper as `GLEASON` first.
It reuses the protected credential only after that helper verifies the remote
identity. An open TCP 5985 endpoint with failed authentication is an access
problem: correct the credential/authorization and do not bypass it with SMB.

When TCP 5985 is closed, the orchestrator uses SMB 445 to stage the reviewed
helper, JSON plan, and logo under:

```text
D:\OEM\Temp\OperateSoftkeys\<transaction-id>
```

It tries the approved `D` share, then `D$` only if available, and verifies
SHA-256 after each copy. It does not assume `C$` or directly edit ProgramData
over a share. Through VNC, an administrator must run the exact printed command
locally on the IPC; successful execution removes that transaction's temporary
staging directory. If neither WinRM nor SMB is available, stop and repair the
approved management path.

## Owned configuration and safety

The IPC helper navigates only these live paths:

```text
C:\ProgramData\Siemens\MotionControl\oem\sinumerik\hmi\cfg\systemconfiguration.ini
C:\ProgramData\Siemens\MotionControl\oem\sinumerik\hmi\cfg\slamconfig.ini
C:\ProgramData\Siemens\MotionControl\oem\sinumerik\hmi\ico\ico1024
```

It allocates an unused matching `PROC`/`AREA` number from 500–999 and the first
free softkey position from 9–64. It preserves positions 1–8 and unrelated OEM
entries. Ownership manifests and timestamped backups are stored below:

```text
C:\ProgramData\Gleason\OperateSoftkeys
```

Update/delete require the manifest and exact current owned values. Refuse
collisions or drift instead of overwriting another integration. Writes use
same-directory temporary files and replacement; failures trigger rollback from
the transaction backup. Backups remain until interactive verification.

This helper does not modify `compat\user\OEMFRAME.INI`, language resources, or
application-specific OEMFrame settings. Add those only through a separately
reviewed application-specific change based on Siemens Find Window evidence.

## Runtime boundary

WinRM and SMB may inspect or write configuration, but must not start/restart
Operate, the collector, adapters, controller, or any Siemens-dependent program.
Operate restart and functional validation happen only in the interactive HMI
session. Read this skill's `AGENTS.md` before maintaining its scripts.
