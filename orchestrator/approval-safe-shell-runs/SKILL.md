---
name: approval-safe-shell-runs
description: "Use for multi-step shell work. Script files, no bash -c."
---

# Approval-safe shell runs

Hermes scans each terminal command. Some shapes are flagged and need a UI approval from the user;
with no answer within the timeout the command does not run at all.

## Procedure
1. Single step, simple: run it as a plain command with absolute paths and a redirect, e.g.
   `D=/abs/dir; VAR=$D/x $D/tool.sh $D/runs/NN > $D/runs/NN/out 2>&1; echo "exit $?"; cat $D/runs/NN/out`.
2. Multi-step (backup -> patch -> test -> restore -> verify, commit with guards, merge sequence):
   write it with write_file to `<run dir>/<name>.sh` (`set -u`, explicit paths, `tee` the summary to
   a `.out` file), then run `bash <run dir>/<name>.sh`. The script doubles as evidence and is
   re-runnable.
3. Long background jobs: same rule; background the plain command or the script, not a `bash -c`.

## Pitfalls
- `bash -c '...'`, `{ ...; } > file` groups, heredocs inside a chained one-liner and dynamically
  built commands get flagged (the scanner cannot prove the nested body). Rewrite as a script file
  instead of retrying.
- A blocked command means the user did not consent: never retry it verbatim or rephrase it to slip
  past; switch to a script-file form only when it does the identical thing, and tell the user.
- The user typing "approve" in chat does not answer a pending command prompt, and a user who is
  away cannot pre-approve. Say this when asked to work unattended, and plan commands in the forms
  above.
- A script that edits a source file temporarily must restore it from a backup and print
  before/after sha256; report a mismatch loudly with the backup path.
- When the user runs a command for you and says "done", check the expected output file exists and
  is newer than any earlier run before trusting it; relative paths run from the wrong directory
  write nowhere you look.
