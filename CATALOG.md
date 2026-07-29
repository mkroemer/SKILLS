# Skill catalog and repository installation

This repository can be consumed in two ways:

1. as an OpenCode V2 HTTP skill catalog;
2. as a normal Git repository from which an agent or human installs one selected skill.

## OpenCode V2 HTTP catalog

The catalog base URL is:

```text
https://raw.githubusercontent.com/mkroemer/SKILLS/main/
```

The base contains [`index.json`](index.json). OpenCode downloads each listed file from:

```text
<catalog-base>/<skill-name>/<file>
```

Add the catalog to a project `opencode.json` or `opencode.jsonc`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "skills": [
    "https://raw.githubusercontent.com/mkroemer/SKILLS/main/"
  ]
}
```

The same entry can be added to the user's global OpenCode configuration. The arrays are additive, so a project can use this catalog together with local skill directories.

OpenCode caches catalog files. A catalog entry's `version` must change whenever any file delivered for that skill changes.

### Catalog limitations

The catalog makes skill instructions and supporting files available to OpenCode. It does not remove a skill's runtime or host-project requirements.

In particular:

- `office-vba` still needs its platform runtime; follow its README or run the included installer;
- `gleason-winrm-connect` needs reviewed setup files from the consuming project for bootstrap staging;
- `gleason-operate-softkeys` currently requires both Gleason skills under the consuming project's `.opencode/skills` directory for its complete scripted workflow;
- `ipc-smb-winrm-bootstrap` depends on approved bootstrap and deployment files from its consuming project.

Read the selected skill's `README.md` before executing scripts.

## Install from the Git repository

An agent with Git and filesystem access can install a named skill from the repository URL without catalog support.

The safe generic workflow is:

1. clone the repository into a temporary or managed source directory;
2. read the root `README.md`, the selected skill's `README.md`, `SKILL.md`, and any local `AGENTS.md`;
3. install only the requested skill into the appropriate project-local or global skill directory;
4. install only the runtime dependencies documented by that skill;
5. run the documented verification command;
6. do not perform the skill's operational task merely as part of installation.

Example prompt for an agent:

```text
Install the office-vba skill from https://github.com/mkroemer/SKILLS.
Read the repository and skill documentation first. Install only that skill and
its documented runtime dependencies into the appropriate Agent Skills location.
Verify the installation, but do not inspect, modify, or run macros in any Office
file as part of installation.
```

For a project-local portable installation, place the selected directory at:

```text
<project>/.agents/skills/<skill-name>
```

For a global portable installation, place it at:

```text
~/.agents/skills/<skill-name>
```

Use the client-specific location documented by the skill when its scripts require one.

## Trust and update policy

Treat skill scripts as executable code. Review changes before updating an installed skill, preserve skill-specific safety requirements, and avoid running installers from untrusted forks. The catalog points to the `main` branch; consumers that require reproducibility should use a reviewed commit or maintain a pinned internal mirror.
