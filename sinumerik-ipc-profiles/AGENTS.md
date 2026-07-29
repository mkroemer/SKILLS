# Agent note: SINUMERIK IPC profiles

1. Keep the schema organization-neutral. Put company defaults only in named
   example presets.
2. Never add passwords, credentials, tokens, API keys, private keys, or other
   secrets to examples, tests, documentation, or profile files.
3. Preserve the resolution order: explicit path, environment variable,
   project-local file, then current-user application data.
4. Validate profile structure before returning it and reject secret-bearing
   property names recursively.
5. Generate bootstrap commands from structured entry-script and argument
   fields. Never execute arbitrary command strings from profile JSON.
6. Keep schema version 1 backward-compatible. Introduce another version for
   incompatible changes.
7. Run tests only against temporary profile files and never contact an IPC.
