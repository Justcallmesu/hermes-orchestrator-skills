---
name: revert-merged-change
description: "Use when asked to revert a merged change. Scope, redo."
---

# Revert a merged change (PM)

The user usually points at the change by its user-facing text (a changelog line, a screen behaviour), not
by a commit. A changelog line often bundles several unrelated rules, and later commits may build on it.

## 1. Locate the change (read-only)
- Find the text: search the repos for a distinctive phrase, then `git log --all --oneline -S "<phrase>"`
  to get the changelog commit. Its message names the fix run / ticket.
- From the ticket's `tickets.md` row get the code commit(s) per repo; `git show --stat <sha>` and the
  spec decision ids it implemented.
- `git branch -a --contains <sha>` and the changelog section ("unreleased" vs a version) tell you
  whether it shipped. Unreleased = no user-facing "reverted" entry; just delete/trim the line.
- `git log --oneline <sha>..develop -- <files>` lists later commits on the same files. Read each one:
  a later fix may extend the same rule elsewhere (sibling entity, shared helper) or refactor the code
  you are removing.

## 2. Scope is the user's call
- Split the line into its separate behaviours and present options in one clarify: the whole line,
  only the part the user's words point at, and with/without the later sibling extensions. Name the
  consequence of each (what users can do again, which screens become inconsistent).
- If the user asks "explain X" first, explain in plain language: who is affected (which role/permission),
  before vs after, per endpoint, and what reverting re-opens. Mention the cheaper alternative if one
  exists (e.g. grant access instead of removing the check).
- A bare "revert it" after options = the literal scope the user quoted. State the option taken and
  what is deliberately kept, record it as decisions in `docs/<revert-name>/spec.md`, then act.

## 3. Build
- Own branch in both repos via `git worktree add -b <branch> <path> develop` (script file), with
  `node_modules` symlinked, so the shared develop checkout and other sessions stay untouched.
- Revert BY HAND on current develop, never `git revert <sha>`: later commits changed the same files
  and a mechanical revert drops or conflicts with them. The brief lists what to remove, what to KEEP
  (sibling fixes, shared helper params other callers use, unrelated parts of the same commit), and
  says to keep later commits' changes (e.g. locks) when restoring old logic.
- Tests that asserted the reverted behaviour are rewritten to assert the restored behaviour, not
  deleted wholesale; keep the checks for the kept parts. Trim both changelogs.

## 4. Verify
- Cross-check: the OLD test suite against the reverted build must fail on exactly the reverted
  checks; the NEW suite against plain develop must fail only on the behaviour you changed back. Any
  other difference = something extra was removed or kept.
- Run the related suites on both builds and compare counts; only failures identical on develop are
  pre-existing.
- Read the diff yourself (dead imports, still-injected services still used), typecheck, then a fresh
  reviewer. Commit/merge only after the user approves.
