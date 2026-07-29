# Agent note: generic Operate softkey management

1. Limit active configuration targets to the ProgramData OEM `cfg` and
   `ico\ico1024` paths unless a separately reviewed change expands the scope.
2. Verify a user-supplied administrator credential through WinRM first. Use SMB
   only when WinRM transport is closed, only for staging, and never as an
   authentication bypass or direct ProgramData editing method.
3. Prompt for the target, label, icon, IPC program, and window title. Never
   infer them, compile language resources, or reuse another softkey's IDs,
   icon, process name, or ownership metadata.
4. Preserve entries 1–8, allocate IDs only from 500–999 and positions 9–64,
   require ownership manifests for update/delete, and refuse drift/collisions.
5. Back up every touched file, verify copied hashes, use replace/rollback, and
   retain backups until interactive validation succeeds.
6. Never edit `compat\user\OEMFRAME.INI`; do not alter application-specific
   OEMFrame sections without separate reviewed evidence.
7. Never start or restart Operate or Siemens-dependent code through
   WinRM/session 0. Require restart and validation in the interactive HMI
   session.
8. Keep account names, IPC addresses, project paths, and organization names out
   of defaults and source code.
9. Run automated tests only against temporary roots; never contact an IPC.
