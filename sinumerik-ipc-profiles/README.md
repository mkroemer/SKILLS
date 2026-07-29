# SINUMERIK IPC Profiles

Human-facing guide for the `sinumerik-ipc-profiles` Agent Skill.

## What it does

This skill provides one profile format for the other SINUMERIK IPC skills. A
named profile can hold:

- IPC hostname or IP address;
- administrator and operator account names;
- WinRM port, HTTPS, and authentication settings;
- optional engineering-client address and approved management scope;
- approved bootstrap paths, file mappings, markers, and arguments;
- optional runtime port, process, task, endpoint, and log settings;
- SINUMERIK Operate configuration and staging paths.

Profile files must not contain passwords or other secrets. WinRM credentials
remain in the protected credential store managed by `sinumerik-ipc-connect`.

## Install

```powershell
New-Item -ItemType Directory -Force '.agents\skills' | Out-Null
Copy-Item -Recurse `
  '<path-to-SKILLS>\sinumerik-ipc-profiles' `
  '.agents\skills\sinumerik-ipc-profiles'
```

Install this skill beside `sinumerik-ipc-connect`,
`sinumerik-ipc-bootstrap`, and `sinumerik-operate-softkeys`.

## Initialize a profile file

Neutral template:

```powershell
& '.\.agents\skills\sinumerik-ipc-profiles\scripts\Initialize-SinumerikIpcProfiles.ps1' `
  -Preset Generic
```

Gleason preset:

```powershell
& '.\.agents\skills\sinumerik-ipc-profiles\scripts\Initialize-SinumerikIpcProfiles.ps1' `
  -Preset Gleason
```

The default destination is:

```text
%APPDATA%\SinumerikSkills\ipc-profiles.json
```

Existing files are never overwritten unless `-Force` is supplied. Review the
file and add one named entry for every required IPC. The included Gleason
preset contains the defaults that were previously hardcoded in the skills, but
no passwords. It retains the former Gleason softkey ownership root so existing
ownership manifests remain addressable; change that field deliberately when a
new namespace is required.

For a shared project configuration, store the file at:

```text
<project>\.sinumerik\ipc-profiles.json
```

For another controlled location, set `SINUMERIK_IPC_CONFIG` or pass
`-ConfigPath`.

## Resolve or list profiles

```powershell
& '.\.agents\skills\sinumerik-ipc-profiles\scripts\Get-SinumerikIpcProfile.ps1' `
  -List
```

```powershell
& '.\.agents\skills\sinumerik-ipc-profiles\scripts\Get-SinumerikIpcProfile.ps1' `
  -Name 'gleason-standard'
```

The resolver rejects unsupported schema versions, missing targets, invalid
ports, and properties named like common secret containers.

## Safety

- Do not store passwords, credential exports, tokens, keys, or secure strings
  in these files.
- Treat a real machine inventory as internal operational information even
  though it contains no credentials.
- Do not silently copy an organization preset into a public project.
- Review bootstrap file mappings and arguments before local elevated execution.

## Verification

Run the offline profile test:

```powershell
& '.\.agents\skills\sinumerik-ipc-profiles\tests\Test-SinumerikIpcProfiles.ps1'
```

The test uses temporary files and does not contact an IPC.

## Agent and maintainer documentation

- [`SKILL.md`](SKILL.md) - agent workflow and safety boundaries.
- [`AGENTS.md`](AGENTS.md) - schema and maintenance requirements.
- [`examples/ipc-profiles.example.json`](examples/ipc-profiles.example.json) - neutral template.
- [`examples/gleason.ipc-profiles.example.json`](examples/gleason.ipc-profiles.example.json) - optional Gleason preset.
