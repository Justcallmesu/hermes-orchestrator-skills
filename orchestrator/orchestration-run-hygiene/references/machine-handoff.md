# Handing a PM run to another machine

Use when the human says "hand off to the other PC". Goal: one archive plus a setup script that lets
a new chat resume from STATUS.md alone.

## What travels how
| Item | Channel | Why |
|---|---|---|
| Committed branch | GitHub (the human pushes) + a `git bundle` fallback | the PM never pushes; check `git ls-remote origin refs/heads/<branch>` first, it may already be there |
| Knowledge docs inside the repo | with the branch | nothing extra |
| Uncommitted, unreviewed worker output | `git diff HEAD --binary` patch (exclude foreign files) + tar of `git ls-files --others --exclude-standard` | never commit or push unreviewed work just to move it |
| Board, spec, STATUS, runs, out-of-git SQL, gate scripts, PROJECT.md | tar of the docs folder | usually outside git on purpose |
| PM persona, memories, the skills the PM uses | tar of that profile subset | the rules live there |
| `config.yaml`, `.env`, logins | never archived; set up by hand | may hold keys |

## Old machine
1. Stop every worker; confirm the tree equals the pause sha snapshot and no throwaway DB is left.
2. STATUS.md gets a "Handoff" section: new layout, what is uncommitted, the verify step, and "the new
   chat verifies, logs handoff received, then waits for continue". Point the resume list at ready briefs.
3. Build the archive by script with `SHA256SUMS`; check the patch with `git apply --check -R <patch>`
   against the live tree.

## New machine (setup script; never overwrites existing work)
1. `sha256sum -c`; clone; take the branch from origin when its head matches, else from the bundle.
2. Apply the patch only on a clean tree; restore untracked files.
3. Unpack docs and profile files.
4. Rewrite absolute paths in docs, PROJECT.md, skills and memories. Order the pairs most specific
   first (repo paths before the workspace root) and include the `~/` forms. Ask the human for the new
   layout; do not assume the old one survives the move.
5. Install dependencies; print the by-hand list (.env, login, profile config, reference repos).
6. Verify script: branch, uncommitted files vs the pause sha, no old paths in gate scripts, skills
   present, createdb/dropdb, tsc, one spec. Ends `READY` or lists FAIL lines.

## Pitfalls
- A kit that refuses a dirty tree blocks the move when unreviewed work exists: export it as a patch.
- Only one PM may drive the repo once the archive exists; tell the human to stop using the old machine.
- Keep the reply short: a what-travels-how table, then numbered steps for each machine.
