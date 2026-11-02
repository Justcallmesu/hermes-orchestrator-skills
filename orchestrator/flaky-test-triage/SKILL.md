---
name: flaky-test-triage
description: "Use when a flaky or red test fails a gate. Prove cause."
---

# Flaky test triage (before committing past a red gate)

A "known flaky" label is not a pass. A ticket can make an existing flake fire more often, and that
is the ticket's bug. Decide with evidence, then either fix or record it as a separate row.

## Procedure
1. Read the failure diff exactly: what differs (order only? a value? a status?) and what still
   matches. Order-only diffs point at unsorted reads.
2. Check history: did it fail before the ticket (baseline file, earlier gate logs)? Count how often
   it failed with the ticket's files vs without. Cheapest count: grep the suite's summary line across
   every recorded gate (`grep -rh '<suite>' docs/*/runs/gates/*/suites.txt | sort | uniq -c`). A single
   new FAIL in a suite whose code the ticket does not touch, that passes on a solo rerun on the gate's
   own copy+DB and has failed once in dozens of gates, is logged as a flake (backlog row with the
   counts) and does not block the commit.
3. Isolated A/B: run only that spec N times (6 is enough) on HEAD and on HEAD + the ticket's files,
   each in a throwaway worktree with its own fresh DB. If both pass alone, the flake needs full-suite
   load; stop rerunning and read the code.
4. Read the code path the test exercises for reads with no explicit order whose result order the
   test (or the output) depends on. In Postgres, an UPDATE writes a new row version, so a new UPDATE
   right after INSERT (e.g. back-filling a link column) changes the physical order unsorted reads
   return.
5. Fix at the read: sort by a stable key (created_at, then id). Reuse the comparator the module
   already uses elsewhere; if there are inline copies, extract one named helper and point them at
   it (behaviour unchanged).
6. Prove it (developer worker or yourself):
   - a throwaway probe that reproduces the wrong order on HEAD code (several rounds),
   - the same probe green with the fix,
   - a mutant with the sort removed bringing the wrong order back, file restored by sha256,
   - confirm the test's expected order is the creation order (else the test is wrong: stop),
   - full module suites 3 times on fresh DBs with 0 failures of that test, other failures equal to
     the baseline list.
7. Re-run the commit gate on the ticket's staged set; the fix ships in the same commit and the
   flake row closes with it.

## Attributing a failure seen outside the gate
Use this before steps 1-7 when a failure shows up in a worker's baseline or mid-run.
- A failure seen in a shared working tree while other workers hold uncommitted edits says nothing about
  HEAD: their half-done files load too. Re-run the same suite on a clean HEAD worktree with a
  throwaway DB, twice, before calling it a regression.
- Make the worktree match the real tree, or the run is void. Symlink `node_modules` and copy `.env`.
  Also symlink every UNTRACKED dir that tests read: a spec that executes deploy SQL from an untracked
  `docs/` fails with file-not-found in a bare worktree. A failure for an environmental reason is not
  evidence either way; fix the worktree and re-run.
- A failure in 1 of N runs inside a spec the ticket changed belongs to the ticket. The worker names
  the test and the assertion, runs that spec 5x on HEAD (same worktree rules), and either fixes its new
  test or shows the flake is pre-existing before reporting DONE. Steer the running worker with this
  rather than re-dispatching.
- A baseline taken after the worker already edited its specs is contaminated by its own work: new
  asserts run against old production code and fail. Take the baseline before the first edit, or in a
  HEAD worktree; check this before blaming a parallel worker.
- A failure in a test that filters or names by date ("today", a date range) that shows up only at
  certain hours is a clock mismatch: the test builds its date from UTC while the code uses local
  time (or the reverse), so it fails in the hours where the two dates differ (WIB: 00:00-07:00).
  Confirm by running it on a clean HEAD worktree at the same clock time and printing both dates.
  If HEAD fails too, it is pre-existing: log a backlog row and do not block the ticket.
- A new test that compares a list of rows read without ORDER BY (or ordered by a uuid) to a fixed
  expected list is an intermittent failure by construction: sort both sides by the same key.
- Compare a suite's failures with a baseline run under the SAME conditions (fresh DB, the suite alone
  or the same suite set in the same order). Suites with capped pickers/lists, page-count/layout checks,
  or settings toggled by an earlier suite (e.g. an oversell flag left ON) fail extra on a DB other
  suites already filled; that looks like a regression and is not.
- Cheapest attribution for a full-gate failure: keep the gate's DB, start a backend built from plain
  `main` (`git archive main | tar -x`) against that same DB, and run the one suite 2-4 times next to
  the branch build. Identical failures on both = DB-state dependent, not the branch; record that in
  the board log with the evidence and commit.
- Compare by FAIL names, not counts: suites with random fixture names fail a varying number of setup
  steps per run. Diff `grep '^FAIL' | cut -d: -f1` of the base-branch run against the ticket run; the
  ticket is clean when it adds no new names. Have each developer snapshot the wider suites before its
  first edit, so its own gate compares against that snapshot.
- A suite at `N pass / 0 fail (exit 1)` with N below its standalone count threw mid-run (fixture
  crash), it did not fail a check: follow `parallel-ticket-waves` section 2 ("ONE suite at ...")
  for the solo rerun on the gate's DB with the gate's env, and read the throw before naming a cause
  (a timeout guess is usually wrong).
- Put these worktree rules into every brief that asks a worker for a baseline or attribution run.
- With parallel builders, don't make the reporting worker chase a foreign failure. Steer the worker
  whose files most likely caused it (an entity/index edit for a backfill spec, a guard change for that
  guard's test) to run that suite with and without its change, restoring by sha256, and tell the
  reporter to list it as "seen on shared tree, not mine".
- Before briefing, `git log -3 origin/<base> -- <files the ticket touches>`: a fresh commit by the
  user or another developer that comments out or removes behaviour (a report summary block) leaves
  its suite assertions red and its now-unused variables as lint errors. Name that exact FAIL and those
  lint errors in the brief as expected-on-HEAD ("confirm on HEAD, do not fix"), and open a backlog row
  asking the user whether the removal is permanent (delete dead code + test) or temporary. Never let a
  worker "fix" a test against the user's own recent change.
- Baseline each test family separately. A family the commit gate never runs (e.g. HTTP/permission
  specs) can already fail at HEAD (a route-list assertion left behind by an added route): record its
  HEAD result, compare tickets against that number rather than zero, and log the HEAD failure as a
  backlog row.

## Fixing a base branch's red suites ("fix main's failing tests")
1. Baseline the plain base branch in a scratch worktree (worktree rules above) on a fresh DB with the
   same jest paths the gate uses; summarise per suite: failing count + the most common first error
   line + first `src/modules` frame (a small parser script over the jest log).
2. Classify every suite before any edit, and put the class rules in the brief:
   - **seed-dependent setup**: `findOneOrFail` on rows only the seeder creates (account settings,
     a "first user" via `find({take:1})[0]`). Fix the TEST, never weaken the service.
   - **production bug**: find the real DB/runtime error under the generic 500 (the `.catch` that maps
     it is not the cause line); check whether a real request can reach it (protected controller =
     user always set) before calling it a user-facing bug.
   - **documented behaviour change**: update the test, cite the doc/commit.
   - **environment**: prove it passes once the worktree matches; no code change.
3. Seed-dependent setup across several specs -> ONE shared test util next to the module's other
   `*.test-util.ts`: repoint the row if it exists, else create it from the seeder payload, and return a
   restore step (old value back / created row deleted, in reverse order). It must undo the keys it
   already changed if a later key throws: the caller never receives the restore step then, and
   afterAll deleting the test account (`ON DELETE SET NULL`) would clear a real seeded mapping.
4. A spec that creates its own user deletes its rows by that user's id, never via `user?.id`: an
   undefined condition makes TypeORM drop the WHERE and delete every row.
5. Prove a util fix with a scratch probe (kept outside the worktree, copied in per run, then removed;
   it needs the same `jest.mock('@nestjs/...')` header as the specs that load entities): PASS on the
   fixed util, FAIL on the previous version. Then verify the seeded-DB case (seed, repoint, run the
   changed suites, table byte-identical after).
6. Gate: target suites twice on fresh DBs, then the wide set vs the base baseline by failure name;
   lint/format per changed file compared with the base copy (`git show origin/main:<f>`). Never run
   whole-file `prettier --write` on a file already dirty at base: it reformats untouched lines into
   the diff. If it happened, rebuild the file (`git show HEAD:<f> > <f>`, re-apply only the intended
   hunks with `git apply --include=<f> <saved.patch>`) and format just the changed lines.

## Delegating the fix
- Brief the worker to wait in the foreground for any background test run it starts: a subagent's
  background process dies with it, and a worker idling on one exits with no report.
- A worker that exits without a report often left complete edits: save its `git diff` to the run dir
  and verify it yourself (gates, probe, fresh reviewer) before paying for a re-run.

## Pitfalls
- Before triaging any red gate, read the names it lists as new failures. A name that is not a test
  (e.g. jest's `● Console` log banner caught by a `^\s+● ` grep) is a bug in the gate's failure
  parser: fix the parser (exclude the banner), drop the leftover DB/worktree, and re-run the same
  staged set. Never change code to satisfy a parser bug.
- Likewise read the output of any command that "exited 1" before treating it as red: a pipeline
  ending in `grep -c` exits 1 when it counts 0 (e.g. "0 tsc errors"), so a clean run reports failure;
  a probe suite marked "1 failed" with every test passed failed in its own `afterAll` cleanup (an FK
  on a row other fixtures still reference). Count passed/failed tests, not the suite status.
  The reverse holds too: a count of 0 errors from a command that itself failed (e.g. a linter run
  with a `--format` plugin that is not installed prints an error and lints nothing) is not clean.
  Use the tool's default output and read it.
- When a commit gate fails only on a test marked flaky, do not commit past it: first ask whether the
  ticket plausibly raised its failure rate (new writes on the rows that test reads), and run this
  procedure; commit only after the cause is fixed or shown to be unrelated.
- Do not raise retries or loosen the assertion to green a gate: an order assertion that fails
  under load is usually a real nondeterminism users see (document line order).
- An isolated pass proves nothing about a load-dependent flake; it only rules out a deterministic
  regression.
- Count SKIP next to PASS/FAIL in every gate summary, and export the env a suite needs for its guarded
  sections (e.g. a throwaway TEST_DB for raw-SQL checks): a skipped section reads as green.
- An API suite usually aborts at its first failed precondition, so a second mutation in the same
  backend run is never exercised: one mutation per run.
- Keep the probe outside the repo (scratch) so it is never staged.
