# Repository instructions

This repository contains reusable Agent Skills. These rules apply to every skill directory unless a more specific `AGENTS.md` adds stricter requirements.

## Skill structure

Each skill is stored in its own directory and must contain:

- `SKILL.md` for agent-facing instructions and metadata;
- `README.md` for human consumers;
- any scripts, references, examples, tests, or assets required by that skill.

The skill directory name and the `name` in `SKILL.md` must remain aligned and use lowercase kebab-case.

## Documentation contract

When adding a skill, the same change must:

1. add the skill's individual `README.md`;
2. add the skill to the root [`README.md`](README.md);
3. add the skill to the root [`index.json`](index.json) HTTP catalog;
4. include its purpose, platform or runtime requirements, installation method, basic usage, safety boundaries, and verification steps.

When renaming or removing a skill, update the root README and catalog in the same change. When a skill's commands, dependencies, supported platforms, installation process, behavior, safety constraints, or limitations change, update that skill's README together with the implementation.

`SKILL.md` is the source of truth for agent behavior. `README.md` must provide a human-readable explanation without contradicting or weakening the skill's safety requirements.

## README requirements

Every skill README must include, where applicable:

- what the skill does and when it should be used;
- prerequisites and external project dependencies;
- supported operating systems, applications, or file formats;
- project-local and/or global installation instructions;
- a minimal working usage example;
- destructive-operation, credential, network, or execution warnings;
- verification or expected-result guidance;
- links to `SKILL.md`, local `AGENTS.md`, and detailed references.

Use commands and paths that are valid for the repository layout. Do not include credentials, private addresses unless they are explicitly documented defaults, or instructions that bypass security controls.

## Root README requirements

The root README is the human index for the repository. Its skill list must be exhaustive: every directory containing a `SKILL.md` must appear exactly once and link to that skill's README or directory.

Keep installation guidance compatible with portable Agent Skills. Prefer `.agents/skills/<name>` for cross-client examples, while documenting client-specific placement when a skill requires it.

Document both supported consumption paths:

- OpenCode V2 HTTP catalog configuration through the raw repository base URL;
- generic Git clone plus project-local or global skill placement for other agents.

## HTTP catalog requirements

The root `index.json` is an OpenCode V2 HTTP catalog. Keep it valid JSON and observe these rules:

1. Every repository skill must have exactly one catalog entry with the same name as its directory.
2. Every entry must contain `SKILL.md` in its `files` list.
3. Include every README, local `AGENTS.md`, script, reference, example, manifest, license, or other file needed by a remote consumer. Tests and repository-only development files may be omitted.
4. File paths must be safe, relative, same-origin paths within that skill directory.
5. Increment the entry's string `version` whenever any file delivered by that entry changes. OpenCode uses this value to invalidate its cache.
6. Add or remove paths when catalog-delivered files are added, renamed, or deleted.
7. Do not include downloaded binaries, credentials, generated files, local caches, or machine-specific state.
8. Keep [`CATALOG.md`](CATALOG.md), the root README example, and [`opencode.catalog.example.json`](opencode.catalog.example.json) synchronized with the catalog base URL.

A catalog entry does not make a host-project-dependent skill standalone. Keep those dependencies explicit in the skill README and `SKILL.md`.

## Validation checklist

Before publishing a skill-related change:

1. enumerate all `SKILL.md` files and confirm that each sibling `README.md` exists;
2. confirm that every skill is listed exactly once in the root README and `index.json`;
3. verify that every catalog path exists and that every entry includes `SKILL.md`;
4. confirm that the affected catalog version changed when a delivered file changed;
5. verify relative links, raw catalog paths, and example installation paths;
6. run the tests or syntax checks documented by the affected skill;
7. confirm that documentation and catalog files contain no secrets and do not overstate successful execution or validation.
