---
name: thin-orchestrator
description: "Use when orchestrating tickets via fresh worker agents."
---

# Thin orchestrator (files are the memory)

The orchestrator session keeps NO state it cannot re-read. Project state lives in
`docs/<feature>-tickets/tickets.md` (board + event log), `spec.md`, `decisions.md`, `runs/<ticket>/` (or
wherever the project's `PROJECT.md` says). The kit (README, gates script, report/review templates) and the gate
commands come from `PROJECT.md`; read it first (it also names the worker profiles, the branch/commit
policy and the formatter/test runner).

## Start / resume
1. Read `decisions.md` FIRST and follow it (pauses, skipped checks, ordering the human chose in chat), then
   `tickets.md`, the spec, the kit README. Run `git status --short` + `git log -1` in each repo.
2. Pick the next ticket whose deps are DONE. Confirm earlier tickets' artifacts still exist (grep
   their entities/enum members): other sessions can overwrite shared files silently.
3. Read only the code needed to write a precise brief (follow `pm-discovery`). Bulk reading and
   implementation are the workers' job. Keep your context to the board, briefs, reports, gate summaries.

## Workers are profiles
Launch each worker as a separate process from the repo directory, in the background:
`hermes -p developer chat -Q --query-file <brief.md> > runs/NN/<role>-run.log 2>&1`
(`reviewer` the same way). Then BLOCK on it with the process tool's `wait` action, repeating until it
exits. Never end your turn while a worker or a gate run is still running: in a one-shot session the
completion notice would never reach you.

## Per ticket
1. Snapshot `git status --short` + `git diff --stat` (both repos) -> `runs/NN/pre.txt`. Name any
   pre-existing uncommitted changes in the brief as "not yours, do not touch".
2. Brief -> `runs/NN/build-brief.md`: goal, non-goals, decision ids, files + pattern file, invariants,
   acceptance tests, verify commands, "stop and ask if", report path. Restate the hard rules.
3. Developer worker -> `runs/NN/build-report.md`.
4. Run the gates yourself (`gates.sh runs/NN`, in `bash -c`, background + wait). The worker's own
   "tests pass" never counts. Check the report against reality: the files it claims vs
   `git diff --name-only` + untracked; its test counts vs the gate log. A mismatch is a retry.
5. Do one mutation check yourself on the line the ticket's main test guards (break it, test fails,
   restore, sha256 match). This is cheap and catches tests that guard nothing.
6. RED or mismatch -> fresh developer run with the failing evidence (retry +1). Cap 2, then stop and ask the human.
7. GREEN -> reviewer worker with a review brief (diff scope, brief path, spec decisions) -> `runs/NN/review-report.md`.
   A BLOCKER -> fix round (retry +1). `MAJOR (unproven)` -> put it on the board, decide with the human.
8. Status AWAITING-HUMAN, append a log line, report to the human: diff stat, gate summary, your mutation
   result, review verdict + findings, NOT-VERIFIED list, open questions. The human commits; you never do.
9. LEARN: a mistake seen twice -> CLAUDE.md, a lint rule, or the relevant skill/SOUL.

## decisions.md (what only the chat knows)
When the human decides something in chat that no file shows ("pause after this", "skip the Verify on T4",
"use approach B", "ask before batch 2", "go with your recommendation"), append ONE line to
`docs/<feature>-tickets/decisions.md` at once, before doing anything else:
`- YYYY-MM-DD <decision> (why, if given)`. Append-only; a later line overrides an earlier one by saying so
("resumes the pause of <date>"). Spec design decisions keep their own table in `spec.md`; this file holds
run-level decisions. A new session has no other way to learn them.

## Models per role
- Orchestrator/planner and reviewer: the strongest model available. Developer: a mid-tier model is
  enough when the brief is precise and gates + mutation checks back it up. Project-specific choices
  belong in `PROJECT.md`.
- Scouting goes INTO the brief before the build; the developer still reads the real files it edits.

## Pitfalls
- A pause stays in force until the human explicitly says to resume ("go", "continue the queue"). Answering parked decisions ("go with your recommendation") records the decisions only; it does not lift the pause. Ask before dispatching anything new.
- "Stop all" with workers mid-edit: stop them, save their partial diff/new files under `runs/<id>/stopped-partial*` (unreviewed), then restore only their files to HEAD with a script (`git show HEAD:<f> > <f>`, never checkout/stash), check no throwaway DB is left.
- Two sessions building the same ticket in one working tree corrupt each other; check the board + `git status` first.
- Do not run gates while a worker is still writing files.
- If the login shell is zsh, an unmatched glob aborts the whole command. Wrap gate runs in `bash -c '...'`.
- A new feature needs `runs/baseline/` recorded once on a CLEAN tree before ticket 1.
- Check the gate summary's test-path line covers every module the ticket's specs live in.
- Deferred MAJOR review notes go on the board as their own rows, not only into a log line.
- Parallel workers only for tickets with disjoint files.
- Never mirror tickets into the Hermes kanban plugin "for display". A card assigned to a profile is live
  work: the auto-decomposer rewrites triage cards, promotes them, and the dispatcher spawns workers that
  edit the repo. Blocking only works on running/ready cards. To show the board, render `tickets.md`
  (e.g. a generated kanban.html), never create kanban tasks unless the dispatcher should run them.
- Inline chained shell commands that edit files (mutation checks, commits) get auto-blocked; write them
  to a script file and run it with plain `bash <file>`.
- If the developer/reviewer profiles fail with 401 (expired OAuth), use in-session `delegate_task`
  subagents with the same brief files, and tell the user to re-auth.
