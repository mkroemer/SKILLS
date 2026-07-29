---
name: sinumerik-operate-softkeys
description: Inspect, add, update, or delete ownership-tracked SINUMERIK Operate OEM operating-area softkeys using a PNG icon and IPC executable, with guarded WinRM application or hash-verified SMB staging. Use for Operate softkeys, ProgramData OEM menus, systemconfiguration.ini, slamconfig.ini, or managed softkey configuration on any supported SINUMERIK IPC.
---

# SINUMERIK Operate Softkeys

Manage only softkeys owned by this skill. Preserve unrelated OEM integrations.

## Required workflow

1. Confirm the target IPC, approved administrator account, Operate version,
   live configuration paths, and maintenance window.
2. Inspect before changing an unfamiliar IPC.
3. Run the client orchestrator from the consuming project:

   ```powershell
   & '.\.agents\skills\sinumerik-operate-softkeys\scripts\Manage-SinumerikOperateSoftkey.ps1'
   ```

4. Select `Inspect`, `Add`, `Update`, or `Delete`.
5. For add/update, obtain these inputs from the user rather than guessing:
   - machine-safe label/area ID (letters, digits, `_`; no spaces);
   - local PNG icon;
   - absolute program `.exe` path on the IPC;
   - optional program arguments and exact managed window title.
6. Enter the approved administrator credential through the secure PowerShell
   credential prompt or pass a `PSCredential`; never put a password in a
   command, plan, log, or repository.
7. Review the displayed plan and obtain explicit confirmation.
8. After a successful write, tell the operator to restart SINUMERIK Operate
   from the interactive HMI session and verify existing keys, position, icon,
   launched window, and absence of configuration warnings.

Labels containing spaces or translations require approved `TextId`,
`TextFile`, `TextContext`, and compiled Qt/Siemens language resources. This
generic helper intentionally rejects spaces rather than creating incomplete
localization.

## Connection order

Try the configured WinRM endpoint first. Verify the authenticated remote
identity is an administrator before staging or executing anything. Treat an
open WinRM endpoint with failed authentication as an access problem: correct
the credential, authorization, HTTPS, or host trust configuration and do not
bypass it with SMB.

When the configured WinRM port is closed, use SMB 445 only to stage the
reviewed helper, JSON plan, and icon under the configured staging root, which
defaults to:

```text
D:\OEM\Temp\OperateSoftkeys\<transaction-id>
```

Derive the drive-root share candidates from the staging root, try the named
share before its administrative share, and verify SHA-256 after each copy. Do
not edit ProgramData over a share. Through the approved interactive remote
desktop method, have an administrator run the exact printed command locally on
the IPC. Remove only that transaction's staging directory after successful
execution. If neither WinRM nor SMB is available, stop and repair the approved
management path.

## Owned configuration and safety

The IPC helper navigates only these live paths:

```text
C:\ProgramData\Siemens\MotionControl\oem\sinumerik\hmi\cfg\systemconfiguration.ini
C:\ProgramData\Siemens\MotionControl\oem\sinumerik\hmi\cfg\slamconfig.ini
C:\ProgramData\Siemens\MotionControl\oem\sinumerik\hmi\ico\ico1024
```

Allocate an unused matching `PROC`/`AREA` number from 500–999 and the first
free softkey position from 9–64. Preserve positions 1–8 and unrelated OEM
entries. Store ownership manifests and timestamped backups below:

```text
C:\ProgramData\SinumerikOperateSoftkeys
```

Pass `-OwnershipRoot` explicitly to manage entries created under another
approved namespace; never migrate or adopt existing entries implicitly.
Require the manifest and exact current owned values for update/delete. Refuse
collisions or drift instead of overwriting another integration. Use
same-directory temporary files and replacement; trigger rollback from the
transaction backup on failure. Retain backups until interactive verification.

Do not modify `compat\user\OEMFRAME.INI`, language resources, or
application-specific OEMFrame settings. Add those only through a separately
reviewed application-specific change based on Siemens Find Window evidence.

## Runtime boundary

Use WinRM and SMB only to inspect, stage, or apply configuration. Do not start
or restart Operate, adapters, the controller, or any Siemens-dependent program
through WinRM/session 0. Restart Operate and perform functional validation only
in the interactive HMI session. Read this skill's `AGENTS.md` before
maintaining its scripts.
