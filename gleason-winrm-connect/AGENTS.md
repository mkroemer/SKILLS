# Agent note: Gleason WinRM connection skill

This folder contains client-side connection/bootstrap helpers. Keep these
rules when maintaining it:

1. Store credentials only as current-user/current-machine DPAPI-protected
   `PSCredential` CLIXML below `%LOCALAPPDATA%\Gleason\WinRM`, and only after a
   successful WinRM authentication. Never store credentials in this folder.
2. Keep account choices limited to `AUDUSER` and `GLEASON`. Do not change group
   membership or authorization policy; `GLEASON` is the expected administrator
   and `AUDUSER` remains the interactive operator.
3. Stage only the repository's current `scripts\setup_gleason_ipc.ps1` and
   `scripts\Gleason.IpcSetup.psm1`. Verify SHA-256 after SMB or VNC transfer.
4. Do not use broad firewall rules, `Enable-PSRemoting`, `TrustedHosts=*`,
   plaintext secrets, or setup-state deletion. A reviewed HTTP listener must
   already exist.
5. WinRM may configure or inspect the interactive task, but must never host
   Siemens-dependent code. Runtime remains in the logged-on HMI session.
6. Keep all probes read-only until the user explicitly chooses exact-IP client
   trust configuration or approved bootstrap staging.
7. Validate changes with PowerShell parser checks and offline Pester tests. Do
   not contact an IPC during automated tests.
