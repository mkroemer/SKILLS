# Safety and integrity rules

## Before reading

- Verify that the file extension is supported.
- Work from an absolute path so the target is unambiguous.
- Treat extracted VBA as executable code even when it has not been run.

## Before writing

- Inspect the module inventory and extract the current source first.
- Keep the original file under version control or in another recoverable location when possible.
- Confirm the source directory contains only the modules intended for the write.
- Review code that launches processes, opens URLs, reads credentials, modifies files, uses COM, invokes AppleScript, accesses the registry, or makes network calls.
- Warn that writing invalidates VBA digital signatures.

## After writing

- Confirm that the sibling `.bak` file exists.
- List modules again.
- Re-extract changed modules into a separate verification directory.
- Compare the re-extracted source against the intended source.
- Open the document in the correct Office application when available.
- Do not claim compilation success unless Office has compiled the project successfully.

## Before execution

- Require an explicit user request to execute the macro.
- Identify the exact macro and target document.
- Inspect the macro and directly called procedures first when practical.
- Confirm the document is open in its host application.
- Do not weaken macro-security settings or suppress security prompts.

## Recovery

The upstream writer creates `<document>.bak` before changing the file. To recover:

1. Close the document and its Office application.
2. Preserve the failed modified file for diagnosis.
3. Copy or rename the `.bak` file back to the original filename.
4. Reopen the restored document and verify its VBA project.
