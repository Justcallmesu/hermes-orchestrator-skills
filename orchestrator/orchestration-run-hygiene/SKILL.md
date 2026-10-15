---
name: orchestration-run-hygiene
description: "Use when PM-running a ticket board. Scope, counts, commits."
---

# Orchestration run hygiene (PM running a ticket board with worker agents)

Complements `thin-orchestrator` (which owns the per-ticket build -> gates -> mutation -> review loop).
This skill covers what goes wrong ACROSS tickets in a long run: scope creep, misleading counts,
decisions under delegated authority, pauses, lost workers, and commits.

## 1. Scope: feature path vs backlog
- Every review finds pre-existing bugs near the diff. Logging each as a feature ticket makes
  "tickets left" grow forever; the user reads that as no progress. Classify each finding when it is
  logged: blocks the feature release -> feature row; otherwise -> a `BACKLOG` row, not counted.
- When the user says "focus on <feature> first", mark every non-blocking open row BACKLOG on the board,
  write the feature path (ordered) under the board, and work only that path.
- Deferred review notes still become rows (never only a log line), but in the right list.

## 2. Answering "how many left / are we done"
- Lead with the feature count, then backlog separately, then what needs the human.
- Compare with the previous answer: done +N, added +M, and why each was added. Never let a total
  rise silently; the user notices and loses trust.
- Count from the board file with a script (parse rows, classify by status), not from memory.
- Give runs, not rows: bundled rows are one run; say the parallel width (waves).
- "How long": estimate from this run's observed wave times (build, PM gates, review, commit), list the
  remaining waves with a time each, give a range whose top end covers the observed fix-round rate, and
  name what stretches it (lost workers, decisions the user owes, data-dependent preconditions). Say
  that it is an estimate.
- "Detail me the tickets": one table per list (feature path in order with deps / waits-for, then
  backlog grouped by kind), one plain-language line per ticket, then the open user items.

## 3. Decisions under standing approval
- If the user grants "go with your recommendation" for typical questions: note the grant in `decisions.md`,
  then decide, record each in the
  spec decisions table marked as taken under standing approval with the rejected alternative and its
  consequence, and list them in STATUS.md so the user can overturn.
- Still park for the user (keep working on other tickets meanwhile): financial data already posted/stored,
  tax or legal rules, documents an external party already saw, irreversible data changes, options with
  no clear best practice. Push, merge, SQL on real DBs, production repair and browser tests are never
  done unattended.
- Technical decisions that only implement an already-approved rule are the PM's; mark them
  "(PM, technical)" and still record them.

## 4. Pauses
- "Pause after this" = finish the in-flight wave (gates, review, commit if clean), start nothing new,
  write the resume point (ordered next steps, what is uncommitted, what needs the user) into STATUS.md,
  and append the pause (and later the explicit resume) to `decisions.md` so a fresh session honours it.
- A review returning CHANGES-REQUIRED during a pause is not fixed: commit the clean tickets, leave the
  failing ticket's work uncommitted, add an `<id>-fix` row, and brief the next worker to build on the
  tree (never stash / checkout / discard).
- Answering parked questions does not lift a pause; only an explicit resume does.

## 5. Lost workers (owner exit, outcome unknown)
- Do not re-dispatch blindly. Inspect the worker's scratch dir: RED-on-HEAD output, mutation outputs and
  `.bak` sha vs the current file (restored?), the last full test run. Drop any throwaway DB it left.
- Run PM gates on the tree; ask the reviewer to also write the "what was built" section.
- Brief every worker to write its report early and keep it updated, so a death leaves evidence.

## 5b. Workers that STOP on a business conflict
- A worker that stops because a decided rule would break a documented flow (code comments, design
  docs, existing UI behaviour) did its job; do not override it. Amend the decision in the spec with the
  reason and the rejected alternative, add an item-0 "re-dispatch note" to the same brief, update the
  STOP condition to the new rule, and have the new run write `build-report-2.md` so the first report
  stays as evidence. Write rules that keep the documented flow (narrow guard) before rules that
  change it (require a field), unless the user decides otherwise.

## 5c. Reviewer runs that fail on their own
- A reviewer probe exiting non-zero is not a failing test until its output says so (e.g. a test runner
  reporting "No tests found" from a doubled path). Read the output before reacting; reject a review report whose
  evidence rests on such a run.

## 6. PM mutation checks
- A surviving PM mutant may be weak, not the test: if the remaining path still behaves correctly on
  the test data (e.g. a lock pass that is already ascending), break the guard completely and re-run
  before declaring the test useless. Log both runs.
- Never mutate, reformat or edit files while a reviewer is mutating / sha-checking them, and dispatch
  the review only after your own mutation script has restored the file (sha256 match): a reviewer
  probing a mutated file reports nonsense.
- Anchor the mutation on text that occurs exactly once (assert it in the script); a non-applied patch
  is not a run.

## 7. Formatting gates (formatter = whatever `PROJECT.md` names)
- Run the formatter's write mode only on files that already pass it at HEAD (check by formatting
  `git show HEAD:<f>`) or are new. A flagged line inside a block that already fails at HEAD is a logged false positive, not a
  reason to reformat the file.
- A worker that died mid-run usually left formatting undone; run the HEAD-clean format pass after the
  review, then re-run the gates before commit.

## 8. Local commits (when the project grants them)
- One script per wave: check branch, empty index, no probe files (`zz-*`), each file's sha256 prefix ==
  the sha the gates ran on, staged count per commit; one commit per ticket with a why-message citing
  spec decision ids. Verify the whole tree equals the gated snapshot before committing.
- Never stage files owned by someone else's uncommitted work.

## 9. Tickets that change stored money or other precise values
See `references/precision-sensitive-tickets.md` before cutting these tickets.
