# Merging main into a feature branch (PM-run, user-approved)

## Setup (script file, run with `bash <file>`)
- Abort if the worktree path exists. `git worktree add -b merge/main-into-<feature> <scratch>/wt
  origin/<feature>`; `git merge --no-commit --no-ff origin/main`; record pre SHAs, merge output and
  `git diff --name-only --diff-filter=U` in `runs/MERGE-main/`.
- Symlink `node_modules`, copy `.env` (check both are git-ignored before commit). The user's own
  tree is never touched; they pull the fast-forward later.
- Gate specs that read files outside git (untracked `docs/` SQL) fail in a worktree: symlink that
  folder for the gate run and remove it after; say so in the report.

## Resolve brief (one fresh developer)
- Per conflict: what each side did (`git diff <base> <side> -- <f>`), required result = BOTH
  behaviours; for money code name the invariants of each side and demand each side's tests keep
  their assertions.
- Semantic check of auto-merged code: every new writer the other side added (stock movements,
  journals, balances) against the feature's runtime rules, and every new report that reads a
  column the feature changed the meaning of. Text-clean merges still break: import chains that
  need a test mock, return shapes gaining a field.
- Reverted work on main (commit + revert) must stay out; doc folder moves must keep the feature's
  docs at the new location.
- Stop-and-ask on any rule neither side defines; no commit; report updated per milestone.

## Checks before commit
- PM gates on the staged merge over every module either side touched. Attribute each failure:
  baseline class, fails on a pristine `origin/main` worktree (main's own), or env (worktree-only).
  Lint/format RED on files the resolution did not touch is the other side's debt, not a blocker.
- Fresh reviewer (both parents kept, app boots on a throwaway DB, no duplicate routes/permissions)
  plus a money red-team when journals are involved (random property sequences incl. reversals).
  Point the red-team at reversing a NON-latest receipt and re-receiving: an amount derived from
  received qty alone (no stored "posted" column per receipt line) drifts by cents there, while
  plain sequences sum exactly. The fix pattern is a nullable posted column read back as priors
  from live receipts, like the other posted amounts.
- Run reviewer and red-team in parallel with the PM gate run; tell both not to touch the gate's
  temporary symlink or throwaway DBs.
- A red-team defect that the other side's original code has too is not a merge regression: commit
  the merge as pure resolution, fix it as its own ticket on the feature branch before main.

## Follow-up fix ticket on the merged branch
- Brief the developer in the same worktree on the pushed merge; demand the red-team repro as real
  specs, a seeded random property test with reversals, one real-DB integration run, and a mutation.
- A fix that adds a stored "posted" column read as NULL = 0 changes the deploy: ask the user
  whether the other side's pre-fix code ever ran on prod/staging, and add a fail-closed pre-check
  to the rollout (see `deploy-data-scripts`).
- Fresh reviewer with its own adversarial spec (expected values from an independent helper).
  Findings only in out-of-git deploy docs/SQL the PM may fix directly, prove (exit codes on a
  throwaway DB) and note on the board. Comment-only or knowledge-doc findings inside the tree
  (a stale comment describing the old formula) the PM may also fix, then run the formatter check on
  those files and both type checks in the commit script before staging. Any behaviour change goes
  back to a developer.
- Commit script stages only the files the build report lists, after `git status --short` shows
  nothing else changed.

## Commit + push script
Assert remote feature SHA and HEAD unchanged, no unmerged/unstaged paths, no env/node_modules
staged; commit with a message listing how each conflict class was resolved and the known follow-up;
`git push origin HEAD:<feature>` (fast-forward only); print parents and the remote SHA after.
Keep the worktree for the follow-up fix tickets (they build on the pushed merge there); the user's
tree stays behind until they pull, so any browser re-run prompt must require that pull first.
