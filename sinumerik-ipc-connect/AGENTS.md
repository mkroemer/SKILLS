# Agent note: SINUMERIK IPC connection skill

This folder contains client-side connection/bootstrap helpers. Keep these
rules when maintaining it:

1. Store credentials only as current-user/current-machine DPAPI-protected
   `PSCredential` CLIXML below `%LOCALAPPDATA%\SinumerikSkills\WinRM`, and only
   after successful WinRM authentication. Never store credentials in a profile
   or repository.
2. Resolve account names and roles from `sinumerik-ipc-profiles`; do not
   hardcode organization accounts or change remote authorization policy.
3. Stage only the selected profile's reviewed file mappings below an explicit
   source root. Verify SHA-256 after SMB or interactive transfer.
4. Do not use broad firewall rules, `Enable-PSRemoting`, `TrustedHosts=*`,
   plaintext secrets, or setup-state deletion. A reviewed HTTP listener must
   already exist.
5. WinRM may configure or inspect the interactive task, but must never host
   Siemens-dependent code. Runtime remains in the logged-on HMI session.
6. Keep all probes read-only until the user explicitly chooses exact-IP client
   trust configuration or approved bootstrap staging.
7. Generate bootstrap commands from structured profile fields. Never evaluate
   arbitrary command text from profile JSON.
8. Validate changes with PowerShell parser checks and offline tests. Do not
   contact an IPC during automated tests.
