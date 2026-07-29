---
name: sinumerik-ipc-profiles
description: Resolve and validate reusable, non-secret SINUMERIK IPC profiles containing machine hostnames or IPs, account names, WinRM settings, bootstrap metadata, runtime probes, and Operate paths. Use when SINUMERIK IPC skills should share predefined machine settings, select a named machine profile, initialize a local profile file, or avoid hardcoded organization-specific defaults.
---

# SINUMERIK IPC Profiles

Use one shared profile for connection, bootstrap, runtime diagnosis, and
Operate configuration. Keep passwords and all other secrets out of profile
files.

## Profile resolution

Install this skill beside the consuming SINUMERIK skills. Resolve profiles in
this order:

1. explicit `-ConfigPath`;
2. `SINUMERIK_IPC_CONFIG`;
3. `.sinumerik\ipc-profiles.json` below the current project;
4. `%APPDATA%\SinumerikSkills\ipc-profiles.json`.

Select `-Profile <name>`, otherwise use `defaultProfile`. If no default is set,
accept the only profile or require an explicit name.

Use the resolver module rather than parsing profile JSON independently:

```powershell
Import-Module '.\.agents\skills\sinumerik-ipc-profiles\scripts\SinumerikIpcProfiles.psm1'
$profile = Resolve-SinumerikIpcProfile -Name 'example-ipc'
```

## Configuration rules

- Store hostnames/IPs, account names, ports, paths, task/process names, and
  approved bootstrap file mappings.
- Never store passwords, credentials, tokens, API keys, secure strings, or
  other secrets. The resolver rejects common secret-bearing property names.
- Keep organization-specific values in a preset or local profile file, not in
  generic skill logic.
- Treat profile files as operational configuration: review changes and keep
  internal machine inventories in an appropriately restricted location.
- Let explicit command parameters override profile values.

## Presets

Use `examples/ipc-profiles.example.json` as the neutral template. Use
`examples/gleason.ipc-profiles.example.json` only for the documented Gleason
defaults. Neither file contains passwords.

Initialize the current Windows user's profile file:

```powershell
& '.\.agents\skills\sinumerik-ipc-profiles\scripts\Initialize-SinumerikIpcProfiles.ps1' `
  -Preset Gleason
```

Review the installed file before contacting a machine. Add one named profile
per distinct IPC or network configuration.

## Bootstrap commands

Generate the local elevated bootstrap command only from the selected profile's
reviewed `bootstrap.entryScript` and `bootstrap.entryArguments`. Expand profile
placeholders through `New-SinumerikIpcBootstrapCommand`; do not evaluate
arbitrary command text from JSON.

Read `AGENTS.md` before changing the module or profile schema.
