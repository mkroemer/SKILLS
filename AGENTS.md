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
3. include its purpose, platform or runtime requirements, installation method, basic usage, safety boundaries, and verification steps.

When renaming or removing a skill, update the root README in the same change. When a skill's commands, dependencies, supported platforms, installation process, behavior, safety constraints, or limitations change, update that skill's README together with the implementation.

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

## Validation checklist

Before publishing a skill-related change:

1. enumerate all `SKILL.md` files and confirm that each sibling `README.md` exists;
2. confirm that every skill is listed in the root README;
3. verify relative links and example paths;
4. run the tests or syntax checks documented by the affected skill;
5. confirm that documentation contains no secrets and does not overstate successful execution or validation.
