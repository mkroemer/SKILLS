# SINUMERIK IPC Bootstrap

Human-facing guide for the `sinumerik-ipc-bootstrap` Agent Skill.

## What it does

This instruction-focused skill classifies and guides:

1. network reachability;
2. WinRM authentication and client trust;
3. elevated local IPC bootstrap;
4. administrator deployment;
5. optional interactive runtime health.

It prevents unnecessary bootstrap reruns when the actual failure is a
credential, deployment, scheduled-task, process-session, URLACL, application,
or adapter problem.

## Requirements

- A Windows engineering or service workstation with PowerShell.
- [`sinumerik-ipc-profiles`](../sinumerik-ipc-profiles/) with a reviewed
  machine profile.
- [`sinumerik-ipc-connect`](../sinumerik-ipc-connect/) for connection and
  staging helpers.
- An authorized IPC administrator credential supplied through the secure
  PowerShell prompt or protected credential store.
- Approved local interactive access for elevated bootstrap execution.
- A consuming project containing every file listed in the selected profile's
  `bootstrap.files`.

The skill does not bundle project-specific bootstrap or deployment software.

## Install

```powershell
New-Item -ItemType Directory -Force '.agents\skills' | Out-Null
Copy-Item -Recurse '<path-to-SKILLS>\sinumerik-ipc-profiles' '.agents\skills\sinumerik-ipc-profiles'
Copy-Item -Recurse '<path-to-SKILLS>\sinumerik-ipc-connect' '.agents\skills\sinumerik-ipc-connect'
Copy-Item -Recurse '<path-to-SKILLS>\sinumerik-ipc-bootstrap' '.agents\skills\sinumerik-ipc-bootstrap'
```

## Use

Example requests:

```text
Use sinumerik-ipc-bootstrap with profile example-ipc to classify the IPC without changing it.
```

```text
Use sinumerik-ipc-bootstrap to determine whether this is a network, WinRM access, bootstrap, deployment, or runtime failure.
```

```text
Use sinumerik-ipc-bootstrap to stage the selected profile's approved setup files after verifying WinRM transport is closed.
```

## Required workflow

1. Resolve the selected profile.
2. Probe network ports without credentials.
3. Classify WinRM transport, trust, authentication, and authorization.
4. Inspect configured bootstrap, deployment, and runtime evidence through a
   verified session.
5. Stage only profile-approved files when WinRM transport is closed.
6. Run the structured profile-generated command locally and elevated.
7. Reconnect and verify bootstrap before deployment.
8. Use the consuming project's approved deployment procedure.
9. Verify optional runtime only in the interactive HMI session.

## Safety

- Never store or print passwords.
- Never use `TrustedHosts=*`.
- Never delete setup state to force a rerun.
- Never broaden firewall or URLACL scope automatically.
- Never infer bootstrap file, marker, process, task, or log names.
- Never start Siemens-dependent runtime through WinRM/session 0.
- Never claim a layer is healthy without its corresponding evidence.

## Verification and reporting

Report network, WinRM access, bootstrap, deployment, and runtime separately.
State the first failed layer, its evidence, and the next justified action.

See [`SKILL.md`](SKILL.md) for the complete procedure and decision tables.
