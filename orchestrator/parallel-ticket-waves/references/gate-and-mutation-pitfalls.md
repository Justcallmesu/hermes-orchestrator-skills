# Gate, mutation and commit pitfalls (jest-only backend gates)

Depth for sections 2, 2a and 4 of SKILL.md.

## Scratch DBs
- `createdb`/`dropdb` hang forever on a `Password:` prompt unless `PGPASSWORD` is exported (load
  `.env`, then `export PGPASSWORD="$DB_PASSWORD"`) and stdin is `< /dev/null`. Put both in every
  gate/mutation script and in the worker RULES file.

## Gate scope
- Run the FULL backend jest (path `src`) before every wave commit, not only the touched modules:
  specs in other modules (notifications, reports) drive the changed services through their own
  fixtures and are the ones that break. A module-scoped gate that misses them reads GREEN.
- Gate result = "no new failing test NAMES vs the baseline list", not a count: grep `^FAIL` from
  the jest logs, `sort -u`, and compare with the recorded known failures.
- A new failing name in a module the wave did not touch: in one script, print
  `git diff --name-only HEAD -- <that module>` (must be empty) and rerun only that spec 3 times on a
  fresh DB. Empty diff + 3/3 green = pre-existing flake: read the failing assertion for the cause
  (two rows created in the same millisecond compared in an order the query never fixes), add a board
  row with that `file:line`, add the name to the known-failures list, and commit. Any red rerun or a
  touched module = treat as a regression.

## Mutation scripts
- Back up the file, apply with `sed`, `cmp` to prove the sed applied, run only the guarding spec,
  restore from the backup, and write `git status --porcelain` at the end to prove the tree is
  unchanged. Name the mutant shapes (`if (false)`, a line reduced to `;`, a deleted lock block, a
  side effect moved into the transaction) in any concurrent review brief with "re-read before
  reporting" — every time, not only for lock waves. A reviewer that still reports a mutant-shaped
  bug: `sha256sum` the file against `gated-sha.txt` and print the cited lines before acting; a
  match means the reviewer read your mutant, and the finding closes with that evidence.
- A lock mutation must REMOVE the lock, not weaken it: `for_key_share` still conflicts with the
  competing path's FOR UPDATE, so the mutant "survives" while the test is fine.
- To delete a multi-line block, use a sed range anchored on the block's unique first line
  (`'/    if (move.x)/,/      });/d'`) and still `cmp`.
- Before running, `grep -c '^<exact anchor line>$' <file>` for every mutant: each must print 1,
  or the sed hits nothing (void run) or several places (mutant tests the wrong guard). When the
  line is not unique (a repeated `transactionalEntityManager,` argument), scope the sed: a line
  number from `grep -n` (`'606s/.../'`) or a context address (`'/deleteFile($/{n;n;s/.../}'`). To
  drop a term that prettier split over two lines, edit both lines by number so the result is the
  exact pre-fix code (`'606s/ -$/,/; 607{/closedQty/d}'`), not a dangling operator.
- Put mutants FIRST and the full gate LAST in the script, and keep a separate gate-only script.
  When the run is killed mid-gate (SIGTERM from an interface switch), the mutant lines already
  printed are valid evidence: grep the tree for leftover mutant shapes, then re-run only the
  gate-only script instead of repeating every mutant.
- A review that sends a fix round back while the gate is still running: kill that gate (its jest
  will not cover the fix), keep its already-printed caught mutants as evidence, and write a
  re-gate script that first drops the killed run's leftover scratch DBs (`psql -lqt | grep
  <gate prefix>`), then runs ONE mutant for the fix round's guard, then the full gate. The commit
  waits for that re-gate; never commit on a gate whose tree predates the last edit.
- Frontend logic with no test runner: have the worker keep a node check script in its run dir
  (`npx esbuild <check.ts> --bundle --platform=node --tsconfig=tsconfig.app.json --outfile=<scratch>.js`,
  then `node`, printing PASS/FAIL per case and a final `FAILED n`). The PM mutates the FE source with
  the same backup/sed/cmp/restore loop and reruns that script; a mutant is caught when the script
  prints FAILED. This gives FE pure helpers (splitters, approved-amount rules) the same mutation
  evidence as backend guards.
- A rounding call that survives being mutated (`roundCents(x)` -> `x * 100`) means every test value
  happens to be float-exact, not that the rounding is unneeded. Pin it with inputs whose `* 100` is
  inexact in floats (1.1, 9.45) in a MULTI-line case and fold that case into the next fix brief: in a
  splitter the dust from one line's headroom lands on the NEXT line, so a one-line case at the cap
  still passes under the mutant, and some inexact values (0.29) round back to exact at 1.00.
- A type-only change (narrowing an entity property so money columns no longer compile) has no
  runtime RED. Evidence is a tsc probe file that reads the forbidden field: 0 errors with the HEAD
  types swapped in temporarily, N errors with the new types, then `sha256sum -c` to prove the
  restore. Brief this up front so the worker does not hunt for a failing jest test.
- For a fix round, add one mutant per finding the round closed (the pre-lock block, the status
  re-check, the count re-check, an assert moved before an early return). A finding with no failing
  mutant is not closed.

## Fix-up briefs after a review
- Tell the builder to VERIFY each reviewer claim first (both code paths, `file:line`) and to
  reproduce it as a RED test before fixing; if the claim is wrong, report why and skip it. Findings
  that came from reading lock order alone are hypotheses until a race test fails.
- A minor whose fix needs a shared validator outside the file list (a decimal-places rule that
  create also lacks): let the builder report it instead of fixing one path, and add one backlog row
  covering every path, so the paths stay consistent.
- A builder's "likely bug, out of scope" note goes into the fix-round review brief as "confirm or
  refute with a concrete example; say whether it exists at HEAD; MAJOR only if a normal user action
  hits a backend refusal". Worker notes often name the wrong cause. A confirmed PRE-EXISTING major in
  a sibling path does not hold the approved wave: commit the wave + fix round, and cut the sibling
  fix as its own next ticket.
- Review minors that touch a file the NEXT ticket owns go into that ticket's brief as a named list,
  not a separate cleanup ticket.

## Worker hygiene checks before the gate
- A worker that ran `prettier --write` on a whole existing file: `git diff -U0 -- <f> | grep -c '^@@'`
  and `git diff --stat` must show only the hunks its report names (insertions only for an
  append-only test file). Extra hunks = reformatted foreign lines: restore them by brief before
  gating, never by hand-reverting yourself.
- A worker whose `dropdb` sat at an unanswered approval prompt leaves its scratch DB behind: run
  its own `db-drop.sh` (plain `bash <file>`) from the PM turn before the gate and log it. Brief
  every worker to keep create/drop in such a script file so the PM can finish the cleanup.

## Integration-spec fixtures
- A real-DB spec must scope every count/aggregate assertion to its OWN fixture ids (its supplier,
  its tagged rows), never "exactly one row in this month/status": an interrupted run leaves its
  rows behind on any reused DB (workers often reuse theirs), and a global assertion then fails on
  every later run. Ask reviewers of new integration specs to check this.

## Hand-rolled stubs in other specs
- When a ticket makes an existing method call a NEW collaborator method (a lock helper that now
  asks another service for its row first), grep the specs that build the service by hand
  (`grep -rln "new <ServiceName>(" --include=*.spec.ts`) and list them in the brief's file list.
  Those stubs mimic the old dependency shape, so the call becomes a 500 in a suite outside the
  touched module, and the worker can only STOP on it.
- A worker's STOP that only asks to add the missing method to such a stub (returning the "nothing
  here" value, e.g. `null`) is a test-only PM fix: apply it with a one-line comment saying why, log
  it as "(PM, technical)", and let the next full-jest gate prove it. Anything that changes an
  assertion still goes through a fix brief.

## Commit
- Commit a wave only after: gate GREEN, mutants all caught, fresh review with no BLOCKER/MAJOR left.
- Record sha256 of the files the gate and mutants touched when the gate ends; the commit script
  re-checks them (`sha256sum -c`) and refuses if anything moved. When nothing else is in the tree
  (no next-wave worker started yet), commit the gated tree directly (`git add -A -- <src dirs>`);
  the clean detached-worktree check is needed only when other uncommitted work shares the tree.
  Dispatch the next wave only AFTER that commit, so its edits never mix into the gated set.
- Every commit script asserts the branch first and prints `rev-parse HEAD origin/<branch>` after
  the push, so a silent push failure is visible.

## Batch shape
- Merge two small tickets that edit the same file into one worker run; put every new permission
  into one ticket that runs first, so parallel tickets do not collide on enum/seed files.

## Rounding fixes to stored totals
- A brief that changes how a document's frozen totals are rounded (grandTotal = rounded subtotal +
  rounded tax) must ask the worker to list every caller of the shared totals helper and fix the
  rounding in the caller when the helper has other callers (a quote freeze), cutting a sibling
  ticket for each caller with the same gap. Also list every amount POSTED from the stored total
  (auto-approved receivable, journal) and state in the report that it moves by up to 1 cent from
  now on, and that existing rows are not backfilled (a deploy-note line).
- Also grep the frontend for previews that mirror the backend totals formula (pricing tabs, summary
  cards; often commented "mirrors <util> in the backend"): they keep summing unrounded values and
  show a total 1 cent off the stored one. Cut the FE ticket in the same wave, with a node check
  script that bundles the REAL backend util (esbuild) rather than a hand port.
- The parity check must feed each side the inputs it really gets, not one shared array: the backend
  freeze sums line subtotals as computed (unrounded), while the FE preview sums the line values the
  API returns (stored, rounded to the column scale). Generate raw lines (percent discounts,
  fractional qty), give the backend the raw values and the FE the column-rounded ones. Feeding both
  the same rounded lines proves only the header formula and misses a 1-cent gap in about a third of
  quotes; brief the reviewer to probe this when the check script does not.
- Float-ORDER gaps (both sides round the same, but add lines in a different order) only show with
  inputs that make the sum inexact: shuffle the line order on one side and use round header
  percents (2.5, 10, 12.5, 50) with many lines. Random 2-decimal percents can give 0 mismatches on
  HEAD too, so require the sweep to print a non-zero RED count on HEAD before its green counts.
- A worker proving "the change only removes float noise" (same order, HEAD vs new, max diff 1
  cent, never on an exact-float sum) must run that proof for EVERY caller of the changed helper,
  not only the ones in its file list; a caller it leaves out is where the visible bug shows up.

## Side effects that must wait for commit (disk files, external calls)
- A brief that moves a side effect after commit (delete the disk file only once the DB delete
  committed) lists EVERY method of the shared service that performs it, not only the one the review
  named: single delete, bulk delete, delete-all-for-owner, and replace/update (which deletes the old
  file before the new row is saved). Grep the service for the low-level call (`fileSystemService.
  delete`, `saveAndDelete`) and list each method's callers that pass a transaction manager. The
  missed siblings otherwise come back as a STOP and a second ticket.
- Pattern to brief: with a manager, the service does only the DB part and RETURNS the paths; the
  caller calls one `removeFromDisk(paths)` after its transaction resolved (never on rollback), which
  logs and never throws. RED test: make the transaction throw right after the call, then assert the
  row AND the disk file still exist (disk in a scratch temp dir). PM mutant: call `removeFromDisk`
  inside the manager branch.
- Clearing a reference inside the transaction (a setting's file link): brief `field = null`, never
  `undefined` — TypeORM's `save` skips undefined properties, so the old value stays stored. A FK
  `onDelete: 'SET NULL'` can hide this for the id column while a sibling text column (the stored
  path) keeps the stale value; the test asserts EVERY cleared column is null after commit.
- Bulk replace methods that take parallel arrays (`ids[]`, `files[]`) must pair by the caller's id
  order, not by `findBy({ id: In(ids) })`, which returns rows in DB order. Brief the checks to run
  before any disk write: unknown id -> 404, duplicate id, count mismatch and an empty list against
  non-empty ids -> 400; tests assert the scratch folder's file count is unchanged on each refusal.

## Deploy notes to collect while building
- New enum values on synced-schema projects still need `ALTER TYPE ... ADD VALUE` where production
  does not synchronize; note each one for the docs ticket the moment a build report adds it. First
  check the entity column type: a TS enum stored in a `varchar` column (common for notification
  events) needs no SQL, so ask the builder to state which it is instead of promising deploy SQL.
- New permissions are seeded for Admin only: decide grants on existing roles (deploy SQL copying
  from a sibling permission) before the feature ships, or users get 403 on day one.
