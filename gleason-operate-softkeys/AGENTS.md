# Agent note: generic Operate softkey management

1. Follow `docs/operate-softkeys.md`; only the ProgramData OEM `cfg` and
   `ico\ico1024` paths are active configuration targets.
2. Use `gleason-winrm-connect` as `GLEASON` first. SMB is a transport-closed
   staging fallback, not an authentication bypass and not direct `C$` editing.
3. Prompt for label, logo, and IPC program. Never infer a program/window title,
   compile language resources, or reuse another softkey's IDs or icon.
4. Preserve entries 1–8, allocate IDs only from 500–999 and positions 9–64,
   require ownership manifests for update/delete, and refuse drift/collisions.
5. Back up every touched file, verify copied hashes, use replace/rollback, and
   retain backups until interactive validation succeeds.
6. Never edit `compat\user\OEMFRAME.INI`; do not alter application-specific
   OEMFrame sections without separate reviewed evidence.
7. Never start/restart Operate or Siemens-dependent code through WinRM/session
   0. The operator performs restart and validation in the HMI session.
8. Automated tests must use temporary roots and must not contact an IPC.
