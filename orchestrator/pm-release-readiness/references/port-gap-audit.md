# Deep port-gap audit (old app -> rewrite), fan-out recipe

Use when the user asks to "check deeply" how far a port is, or wants a table of what is not
implemented / stubbed / not linked ("the work order doesn't create a receivable"). Read-only end to end.

## 0. Baseline first
`git fetch`, then compare `git rev-list --count <feature>..origin/main`. If main moved since the
feature branched, audit `origin/main`, not the feature branch: another developer's main merges ports
whole areas, and an audit of the stale branch reports them MISSING.
- Give auditors a frozen snapshot, never the user's checkout: `git archive origin/main | tar -x -C
  <scratch>/main-<sha>` (no worktree, no checkout, nothing touched in the user's tree). Tell the
  brief explicitly NOT to read the checkout's code (it is on the feature branch).
- Put the audited SHA in the brief and the summary header.
- A previous audit on a stale baseline: keep it, mark it STALE in its README, write the new run to
  `docs/port-gap/v<N>/` and hand each auditor its old area report as a checklist to re-verify, with a
  "now DONE on main" section so the old summary can be corrected.

## 1. Shared brief (one file, every auditor reads it first)
Write `docs/port-gap/[v<N>/]_brief.md` beside the project docs with:
- Paths: old backend (CRUD modules + domain modules + services such as notification/gateway), old
  frontend (live router, `routes/`, `views/`), new snapshot backend modules, new frontend menu file +
  `Views/`, knowledge docs, specs, and the root rules file that lists known non-final modules.
- Rules: edit nothing but the own report; no git writes, DB access or app start. Never call a
  feature MISSING from a name search: look for the same JOB (table purpose, user action) under other
  names and for a recorded decision; say what was searched. Every status cites old file and new
  file:line or doc section; unverified = ASSUMED + what would confirm it.
- Depth: compare USER ACTIONS (list/create/edit/delete/approve/reject/cancel/print/export/report) and,
  per document, its SIDE EFFECTS in old vs new: stock movement, journal, payable/receivable, invoice,
  cost/price update, parent status, notification. A missing or hand-typed side effect is a gap row.
- Stub detection: `TODO|FIXME|not implemented|stub|placeholder` in the area's modules, endpoints with
  no frontend caller, menu entries/buttons with no route or API call, statuses no code path sets.
- Status vocabulary, exactly: PORTED, PARTIAL, BACKEND-ONLY, FRONTEND-ONLY, STUB (exists, does
  nothing real), LINK-MISSING (works alone, side effect into another module absent), REPLACED,
  NOT-PORTED (decided), MISSING, OLD-UNUSED? (no live route/menu).
- Report shape: header, counts per status, GAP table first (only non-done rows: feature | status |
  what is missing in plain words | old evidence | new evidence | money/stock risk H/M/L), compact
  done table, side-effect matrix per document, rows now done vs the previous audit, recorded
  not-ported decisions, not verified. Final answer = path, counts, top 8 gaps with risk.

## 2. Fan-out
One `delegate_task` call: one auditor per functional area (about 6 for an ERP: inventory+purchase,
maintenance, contract+finance, HR+admin, accounting+tax, fuel+vehicle+remaining masters+reports)
PLUS one cross-module auditor that audits no screens and traces each money/stock chain end to end
(WO -> receivable/journal, PR -> PO -> receipt -> stock + journal -> supplier invoice -> payable ->
payment, usage -> FIFO cost -> expense, payroll -> journal/loans, fuel, assets, who calls the
payable/receivable create method). Area auditors miss links that cross their boundary.
Each task's context names its old route/view folders, old server modules, new modules/Views, the
knowledge docs with earlier decisions, and the user's own example question so it is answered
explicitly. Assign every old area to exactly one auditor. End the turn while they run.
The cross-module auditor must also check:
- Journal STATUS: a link that creates a DRAFT journal is not in the ledger (statements read POSTED only).
- Whether the OLD posting call was live or commented out: an old journal call that was commented out
  makes a missing new journal unfinished design, not a regression. Say which in the reply.
- Whether a post-commit side effect (receivable created after the status save, outside its
  transaction) has a retry path; a failure there leaves the document without its money row forever.

## 2b. While they run: check the user's example yourself
Grep the callers of the effect the user named (e.g. every importer of the receivable service across
modules) and read the call site. The user's example is often already fixed on main; say so in the
status line with the file:line instead of repeating it as a gap.

## 3. Merge
- Spot-check the headline claims yourself before repeating them (dead menu entries: grep the menu
  key outside the menu files; "doc says built" claims: `git log --all -S<Symbol>` in the frontend
  repos; missing subsystems: grep the backend). Mark each VERIFIED in the summary.
- Count per area: live = total - OLD-UNUSED? - new-only; settled = PORTED + REPLACED + NOT-PORTED
  (decided); report settled % per area and overall, sorted best first.
- Write `docs/port-gap/[v<N>/]README.md` (counts table, spot-checks, cross-cutting themes) and reply
  short: headline %, area table, ONE gap table (not implemented / stub / link missing, money risk
  first), corrections to the earlier answer, and 3-5 decisions for the user with a recommendation each.
- A knowledge doc that claims a screen exists when it does not is stale: report it.

## 4. Follow-up: "how about report X, like the old app?"
One screen family, done by the PM directly (no fan-out):
1. List the old live routes for it (`grep` the route files for `path`/`element`) and every old view
   file with line counts, then the new Views for the same job.
2. Diff the COLUMNS and TABS, not the page: `grep -oE "title: *['\"][^'\"]+['\"]|label: *['\"][^'\"]+['\"]"`
   over each old `*Controller.tsx` and each new view, plus `export|print|navigate|Link` for actions.
   Old drill-down routes (`/:id/usage`, `/:id/condition`) are separate rows: they hide whole
   sections (e.g. repair cost detail) that a tab name match marks as ported.
3. For a missing column, read the new entity and the knowledge doc before calling it a frontend
   fix: no source field = a data-model change (and usually a recorded deferral to cite).
4. Reply: one table per report (old | new | status ✅/❌/changed), then "what is actually missing"
   split into frontend-only fixes vs data-model changes, and put the data-model one to the user as
   options (port / drop / later).
4b. Adding money (repair cost, bill) to a report row that comes from ANOTHER document:
   - Read how the row finds that document. A join that guesses ("first TSR on the same vehicle
     created after the breakdown") puts the wrong amount on the row when two events are close; make
     it a stored nullable FK set where the link is born (the "create from this row" action, locked +
     same-parent check + 409 if already linked), keep the guess only for old null rows via one
     `COALESCE(stored, guess)` join, and return an `isGuessed` flag the UI marks "(perkiraan)".
     That is a technical call: record it as T<n> in the spec, tell the user in one paragraph.
   - Put three things in the brief that reviewers otherwise find later:
     - The new FK must not block deleting the target. TypeORM's default `onDelete` is NO ACTION, so
       a hard `remove` of a linked target now fails as a 409 "masih memiliki relasi". Read the
       target's delete path: for a hard delete use `onDelete: 'SET NULL'` and add a spec that deletes
       the target and then links the row again.
     - The fallback guess must skip targets already stored on another row (`NOT EXISTS`). Without
       that, one bill shows on two rows.
     - The "already linked → 409" rule still applies when the linked target is CANCELLED or
       REJECTED, so the row can never be linked again. Whether a new target may replace a dead one
       is the user's business rule: ask it as its own Q (recommended: allow replacement over
       cancelled or rejected) before the frontend ticket.
   - Ask the user which amount (customer bill vs internal cost vs both) with who may see each; a
     field the new document lacks ("Biaya Ditanggung") is said plainly, not faked.
   - Brief: reuse the source screen's price-redaction rule through ONE extracted predicate (no
     copied permission check), a cancelled document shows no cost, line sums in their own subqueries
     (test 2 x 3 lines for multiplication), soft-deleted lines excluded.
   - Return every money field as an AMOUNT from the source document's own pricing util. A stored
     discount input may be a percent (`discountAmount` + `isDiscountPercent`), and the UI will print it
     as Rp; add a computed `discountTotal`. Name line sums so nobody labels them "Subtotal" (the
     document's subtotal is after the header discount).
   - Put the redaction verdict in the response meta (`canSeeRepairCost`) and tell the frontend brief
     that EVERY screen consuming the endpoint reads it, or a second screen silently ships without
     the columns.
   - The `isGuessed` mark must cover every column DERIVED from the guessed target (its child
     document code, every cost field), not only the target's own code; otherwise a guessed bill
     looks certain. Put it in the frontend brief, or ask the user up front whether guessed rows
     show cost marked "(perkiraan)" (recommended) or no cost.
   - Verify each reviewer finding in code before ticketing it (cite file:line): a frontend
     reviewer that never read the backend may report a hole the service already refuses. Close a
     refuted finding with the cite; leftover UX polish becomes a backlog row.
   - Return the linked target's STATUS on the row when the UI offers a "create from this row"
     action. Without it the button cannot hide when a relink is not allowed, and users only hit the
     server's 409.
   - A service that starts reading the caller's permissions breaks the existing specs that build
     it by hand (missing mocks): list those sibling specs in the brief as allowed edits (mocks only,
     assertions unchanged).
   - A "should I link it?" from the user is a UX question: options with the recommended first
     (clickable code shown only to users who can open the target; plain code; nothing).
4c. "This report/total is used in many modules" (vehicle usage/condition/uncountable HM, contract
   HM totals): trace the DATA, not the screens.
   - List every old WRITER of the old snapshot table/column (`grep -rn "generate<X>Report\|<column>"`
     over the old server) with the event that fires it, and every old reader. Then, per writer, find
     the new equivalent: a record table written in the transition, a live query, or nothing. Put it
     as a source matrix (old source | new source | gap).
   - For every aggregate column, grep ALL new writers (`grep -rn "<column>"`, look for `increment(`
     AND `update(... { <column>: ... })`). An event writer that INCREMENTS and a recompute that SETS
     from another source on the same column is a real bug: the next recompute erases the event's
     credit. Unit specs test each writer alone and never catch it; propose a failing test first and
     ask the user which source owns the total (options: per-event records summed / one source only /
     both added, with the double-count risk).
   - Old writers that look buggy (a row per line with the full HM range, odd splice logic) are not a
     parity target: say so instead of porting the numbers.
5. When the user says "port it" and adds ideas, it becomes feature design: write
   `docs/<feature>-tickets/spec.md` (verified current behaviour with file:line, decisions table
   Q1..Qn, risks) and put the open rules to the user as a numbered grid with "all recommended = A".
   Before that, check the source of the data the new report would read; existing reports often
   already miscount it (e.g. crediting a row's full total to every person listed on it), and that
   bug belongs in the spec.
6. User pushes back with "check it first, I think it's already complete": re-fetch, then search
   `origin/main`, every branch (`git grep <Symbol> $(git for-each-ref --format='%(refname)'
   refs/heads refs/remotes)`) and any archived repos for the entity/field, and list the module's real
   form fields from its form file. Answer as two lists, "already records" vs "still missing for your
   request", with file:line. An entity comment saying the table is "deferred" confirms it was never built.
7. Partial answers to the grid ("skip X, skip Y, the rest yes"): record every row, skips as
   "skipped", say in one line what each skip leaves approximate or wrong, and shrink the design to
   match. A dropped field often removes a planned new table: prefer additive nullable columns on the
   existing child/join entity (no backfill, old rows read the default). Then a ticket board in
   dependency order and wait for "go".
8. On "go" (start of the build run):
   - Append the go, the branch and the commit rule to `docs/<feature>-tickets/decisions.md` first.
   - Never switch the user's checkout (often on another feature branch). Create the run branch in
     its own worktree from `origin/main` by script: `git fetch`, `git worktree add -b <branch>
     <projects>/wt/<topic> origin/main`, symlink `backend/node_modules`, `frontend/node_modules` and
     `backend/.env` from the main checkout (a fresh worktree has none; specs read DB creds from
     `.env`), print branch, sha and `git worktree list`.
   - Baseline the clean worktree BEFORE any worker edits it, from one script that first asserts
     `git status --porcelain` is empty, then runs the gate scripts with their repo-path overrides
     pointed at the worktree (`BACKEND=<wt>/backend`, `FRONTEND=<wt>/frontend`); without the
     override they gate the main checkout, i.e. the wrong branch. Run it in the background and wait.
   - Copy the baseline's already-failing suites into every brief as "pre-existing, not yours".
   - One shared `runs/_rules.md` (worktree path only, no git writes, own throwaway DB prefix,
     script files for shell, report format) that each short `runs/NN/build-brief.md` points to.
   - Snapshot `git status --porcelain` + HEAD into `runs/NN/pre.txt`, dispatch, flip the board row
     to BUILDING, end the turn with a short status (branch, baseline result, what happens next).
   - Per-ticket gates reuse the same overrides plus `BASELINE_DIR=<runs>/baseline`. The backend gate
     prints RED on any "Test suite failed to run" even when the baseline has that same suite failing
     to run (an `afterAll` FK cleanup error): diff the sorted `● <suite> › <test>` lines and the
     `FAIL <suite>` list against the baseline log before blaming the ticket. Identical lists =
     green-equivalent; say so in the status with both counts. A gate whose jest paths grew past the
     baseline's (a shared helper moved into another module) has no baseline for the new paths: run
     just those suites on a `git archive <base-sha>` copy and on the branch, fresh DB each, and diff
     the failure lists; identical = pre-existing board row for main's owner.
   - The general verify/review/commit loop is the project's own backend feature-workflow skill
     `references/ticket-verification.md`; the bullets below are what this kind of run adds.
   - While a ticket sits in gate/review, write the briefs of the tickets that depend on it, copying
     the contract from the worker's REAL diff (DTO field names, enum values, error text, which id a
     field holds, e.g. Employee id vs Operator id), never from the spec sketch, and name every
     parallel ticket's files as untouchable so the next wave can start as soon as it commits.
   - Parallel wave on disjoint files: ONE combined backend gate + the frontend gate (copy the FE
     ticket's `*.check.ts` into the wave run dir so it runs), then one mutation PER ticket from one
     script (one mutant per jest run, restore + sha256 each). Reviews are read-only, so dispatch all
     of them in one call while the gate runs; warn each to review only its ticket's file list.
   - A review MAJOR of the form "this ticket is only safe together with ticket N" (an old form
     re-sends the legacy field and resets the new one; old readers still credit absent rows) is a
     release constraint, not a fix round: write it under the board as "merge the branch together",
     commit the ticket, and keep its MINORs as one cleanup row (`<id>b`) scheduled after the tickets
     that share its files.
   - Commit each approved ticket from a reusable `runs/commit-ticket.sh <msg-file> <paths...>`:
     assert the branch, print the author identity, `git add -- <paths>` only, commit with a
     why-message, push the run branch (never main), print `git ls-remote` for the branch and the
     remaining `git status --porcelain` (= the other tickets' uncommitted work).
   - Triage review findings into three bins: frontend MAJORs fold into the next frontend ticket
     that edits the same files (`<id>b` inside its brief); MINORs on committed backend code go to one
     cleanup ticket; pre-existing behaviour or unset business rules (drafts counted on one screen
     but not another, a second flow that skips the record, keep or clear fields when a status makes
     them meaningless) become `NEEDS-USER` board rows, listed in the next status as one table
     (question, recommendation first) and never fixed silently.
   - A business decision that lands while a fix ticket for the same files is still building goes
     INTO that running worker (`delegate_task` action=steer with the rule, the files, the tests to
     add), recorded in the spec first; a separate ticket would fight it over the same files. Tell the
     reviewer that the steered rule overrides the original brief.
   - A data-scope rule the user decided for figures ("drafts excluded") does not automatically cover
     non-figure readers of the same rows (prefill suggestions, lookups): grep every reader, and ask
     about the non-figure ones as their own Q (recommend keeping data that helps the user act early).
   - A ticket that moves shared helpers breaks every gate script whose `*.check.ts` path imports the
     old location: repoint the final/wave gate scripts to the new check file in the same step and mark
     the old check superseded, or the final gate goes red for no code reason.
   - Feed review findings into the NEXT briefs, not only the board: a filter added to a shared
     reader ("present only") hides rows from every screen built on it, so a later screen that must
     show them (an attendance column) needs its own all-values endpoint in the backend brief.
   - Brief test checklist for report/endpoint tickets (reviewers keep finding these):
     - a per-person aggregate over two one-to-many sets (report lines AND incident records)
       aggregates each in its own subquery joined on the person id, with a test where 2 lines x 3
       records would give 6 or 9 if joined; plus one person with two lines on the SAME date
       (DISTINCT days), each filter (contract, vehicle, period start AND end) violated by a row in
       EACH subquery, and a ratio with a 0 denominator (null) and a numeric tie. Ask the reviewer to
       mutate the aggregation: cases built only from in-filter rows pass with the filters removed;
     - a review that shows surviving mutants on a ticket holds that ticket uncommitted for a small
       test-only `<id>b` (same files, contract unchanged) while dependent frontend work starts
       against its API contract;
     - "latest row on or before date D" needs a same-day case (row dated D) next to the D-1 case;
     - a service pre-check that duplicates an FK/DB constraint is only guarded when the test
       asserts the pre-check's own message (both paths give 400 and roll back);
     - each test builds its own fixtures (tests that read an earlier test's rows fail alone with `-t`).
