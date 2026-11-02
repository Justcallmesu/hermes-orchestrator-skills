---
name: deploy-data-scripts
description: "Use when writing deploy-day backfill/recompute SQL."
---

# Deploy-day data scripts (backfill / recompute / link SQL)

For scripts run once per environment around a release, outside the app, that change stored rows
(money, costs, links). Project specifics (where scripts live, the rollout note, DB access) come from
`PROJECT.md`.

## Procedure
1. Read the design and every decision the script implements; list each case as RECOMPUTE, KEEP+LIST
   or SKIP+LIST before writing SQL. A case the decisions do not cover is a STOP, not a guess.
2. Shape (all required):
   - stop on first error inside the file (`\set ON_ERROR_STOP on`), one transaction;
   - dry run by default: prints the plan lists, writes nothing; an explicit apply flag writes;
   - version / schema guards first, then `SET LOCAL lock_timeout` before any lock;
   - idempotent: a second apply writes 0 rows;
   - a final in-script check of every invariant that aborts and rolls back the whole run.
3. One shared predicate (temp view / CTE) for every "posted / has a receipt / already linked" rule,
   read by BOTH the plan and the final check. Two copies drift; a stricter copy in the check aborts the
   whole run on ordinary data, so nothing is applied anywhere.
4. Never invent a value. A row the script cannot trace to exactly one source stays as is (or NULL)
   and is listed with a reason code. A link is written only when certain; a set that cannot be proven
   whole stays unlinked rather than partly linked.
5. Operator inputs (override id lists): report every id that matched nothing, and write nothing for it.
6. Reproduce the app's own arithmetic exactly, including its float quirks if that is what the app
   stores today; flag rows where the app's own result is order-dependent (half-cent ties). Derived
   values (e.g. a percent discount) are re-derived with the app's formula on the corrected base, so a
   later app re-save of the document changes nothing; prove it by running the app's save math on the
   script's output.
7. Account for what the script LEAVES BEHIND, not only what it writes: rows it skips or keeps as
   posted may still carry the wrong value the script exists to fix, and strict app rules (e.g. "refuse
   when NULL") do not catch a wrong non-NULL value. List every such row with its reason and make that
   list a go/no-go item (empty at the freeze, or each row decided by an owner).
8. Match related rows with the same key the shared library / app uses (e.g. the representative source
   line), never a looser one like item only: a looser join pulls unrelated rows in and makes a whole
   document skip.

## Choosing a backfill rule (also for app migrations that fill a new column)
- Before approving a rule that derives a new value from master data (e.g. "payment type from the
  customer's terms"), run read-only counts of each outcome per tenant/DB on real data. A rule whose
  input is mostly empty (terms never filled in by a legacy import) sends almost every row to the
  default branch.
- Cross-check against the documents' own evidence (due date vs document date, paid/unpaid status):
  if thousands of rows the rule calls "cash" carry 30-day due dates, the rule is wrong, not the data.
  Prefer document evidence first, master data second, a default last.
- Show the user the outcome counts with the options before the migration ships; a migration already
  applied to a local/scratch DB needs an explicit OK before re-running it there.
- Always offer "nullable, no default, no backfill" as an option: old rows show "-" and the value is
  chosen at the next document that needs it (e.g. type picked on the invoice, written back to the
  order in the same transaction, only where still NULL). Then: readers must be null-safe, update
  paths must keep a stored NULL (not re-derive from master data), and only new rows get a value.
- A new nullable "amount already posted" column that the app reads as 0 when NULL makes the next
  document catch up on everything earlier documents did not store. That is right only if no earlier
  build already posted that amount without storing it (e.g. another branch's code that booked the
  amount straight into the journal); otherwise the catch-up books it twice. Ask whether such a build
  ever ran on prod/staging, and ship a read-only pre-check (journal rows carrying that amount) as a
  go/no-go step, or a backfill of the column from the journal.
- Re-keying a number counter (per customer id -> per printed code): seed each new counter from the
  highest number found in the documents (soft-deleted and cancelled included) AND from the old
  counter rows mapped to the new key. Paths that hard-delete documents (reverting an import) leave
  numbers only the old counter remembers, so seeding from documents alone reissues them. Upsert
  with `GREATEST` so a rerun or an already-higher counter is never lowered, and leave the old rows
  untouched. When the SQL rebuilds a key with an app function (code cleaning/sanitizing), prove
  parity by running both on tricky inputs (unicode, whitespace, null, the length-cut boundary).
- An UNPUSHED migration may be edited in place instead of adding a fix-up migration; any DB that
  already ran the old version (local dev) keeps the old schema and shows drift until it is rebuilt.
  Tell the user and leave that DB alone unless they say otherwise.
- Retiring a field that production already has (moved to another document; the full remove-a-field
  workflow is `field-removal-across-stack`): offer "keep the columns, stop reading/writing them" first (no migration, no data loss; TypeORM `select: false`
  keeps them out of every response). Grep every reader (reports, search, exports, raw SQL,
  recurring jobs, import, sample data, legacy port) before calling it unused, and let old clients'
  extra body fields be stripped by the validation whitelist instead of rejected.

## App-side backfill scripts (TS script using the app's formulas, not SQL)
Use when the value needs the app's own total formula (tax, discount, shipping). Same shape as above
(dry run default, `--apply`, idempotent), plus:
- Transaction grain = the unit whose derived status must change once (one per order/bill, not per
  row), so status history gets one row per document. Say in the report that an error rolls back that
  whole unit and a re-run does it again.
- Print each committed unit as it commits; on an error print the partial summary marked
  "STOPPED because ..." and exit non-zero. A summary only at the end hides what an aborted run wrote.
- Finance-ready summary: per tenant and grand total; every listed row carries party, document,
  source row and amount; totals per list; when a cap hides a value (deduction capped by the stored
  refund), print both figures.
- Add guards for impossible ported data (returned > delivered, source not verified) that send the
  row to the manual list, never a silent bind. A soft-deleted parent (order, customer) is a manual
  row and the run continues; only a truly missing parent row (corruption) stops the run, because one
  stop hides every list of the dry run.
- Before binding an old row, run it through every app guard that reads the columns you write (cancel
  refusals, "already counted" predicates). A value that is right for the money (deduction 0) can
  match a guard meant for another case and leave the row un-cancellable behind a document that can
  never be cancelled (a paid invoice). Leave such rows unbound and list them. Then check the reverse:
  unbound + cancellable must not leak value (a partly netted row would leave units unbilled), so
  partly-covered rows go to manual. Prove each class with a follow-on action test (cancel, later
  document on the same parent).
- Bind at the coarsest level that carries the money (document header) rather than splitting old
  child rows that hold other links (stock movements); state what the coarser bind costs.
- `--apply` needs a second explicit flag (e.g. `--confirm-app-stopped`) and prints the warning
  first; without it, exit non-zero before connecting. The dry run needs no flag.
- Each reason on a listed row is its own code and label ("paid" vs "refund 0" vs "price 0"); one
  label for several causes misleads finance.
- The dry run also takes the locks: run it only with the app stopped or on a copy. Never re-run
  `--apply` after the app has restarted (new-style rows now exist that the script's rules do not
  expect). Both go in the runbook.
- Tests: an API suite that seeds old-shape rows by SQL, runs dry run -> apply -> apply again, asserts
  the summary lines, the written columns (and the columns that must stay untouched), the readers
  (outstanding, status, reports), and the follow-on actions (cancel of each bound/unbound kind).
  RED = the suite against the previous script version, not just "script missing".

## Proof (worker builds it, a fresh red-team re-checks)
- Fixtures shaped like the app's rows for every case, incl. cancelled / soft-deleted / partial
  documents. Dry run: whole-DB table hash before = after. Apply: exact expected row counts. Re-apply: 0.
- Parity: run the app's helpers (under node / the app runtime) on the same inputs over thousands of
  random documents; compare every written value; print the count compared (a broken harness compares
  0 and reports 0 mismatches).
- Mutants: drop or loosen each rule in a copy; the fixtures or the final check must catch every one.
- Held lock -> exits after the timeout with nothing written; injected bad write -> full rollback.
- After every fix round, a focused re-review of only the changed hunks, re-running the earlier probes.
- Each worker/reviewer harness names its own throwaway DB in its own script variable and guards against
  any other DB: the shell session persists, and an inherited variable from another run points the
  script at someone else's database.

## Rollout note
- Script order and which app version must be live; who needs which DB privilege (temp tables).
- When a strict code rule ships with the script (e.g. "no cost -> refuse"), add a go/no-go step: the
  script's dry run on the frozen DB lists 0 rows the rule would refuse; drain those documents on the
  old system before the freeze.
- Hand the KEEP+LIST outputs to their owners (finance adjustments, documents to re-send).
- Check where each go/no-go list can actually run. A script that guards on the release schema cannot
  run on the live old DB, so its first list would appear only inside the window, when the old-system
  remedies (approve, fix the document) are gone. Add a rehearsal before the window: restore a fresh
  production backup into a scratch DB, boot the release schema, run every dry run, hand the lists out;
  repeat on the backup taken at the freeze (shortly before the window). A non-empty list in the
  window = no-go (old system stays), never a hand-fix in the window.
- For each remedy the note offers ("cancel the document", "approve on the old system"), name its side
  effects in the app (what else it cancels, where it is refused, which list it lands on next).
- Changing an existing column's TYPE under an ORM schema sync (TypeORM `synchronize`) is a data
  drop: the Postgres runner emits DROP COLUMN + ADD COLUMN on a type mismatch, not ALTER. Ship an
  idempotent `ALTER COLUMN ... TYPE <new> USING <col>::<new>` as a runbook step BEFORE the first
  boot of the new code; prove on a throwaway DB that the sync plan lists the drop/add before it and
  0 statements after, with seeded values kept. The rollback note needs the same care: the OLD
  build booted with sync on drops and re-adds the column back to the old type (data loss again), so
  give the reverse ALTER or require rolling back with sync off. Put every step in ONE numbered
  "Deploy (in this order)" list in the changelog; scattered sentences ("boot once with sync" above
  "ALTER before first boot") get executed top-down in the wrong order.
- Order schema constraints after the data cleanup they depend on. A new UNIQUE index or NOT NULL
  shipped by the app's schema sync (or the release DDL) runs at boot, BEFORE the window's cleanup
  statements, so existing duplicates or NULLs make the deploy itself fail. Ship non-unique indexes
  freely; defer a unique / not-null constraint to a later release, once the rehearsal list shows 0
  rows on prod, and keep it as a backlog row with that precondition.
- Every script, seeder or one-time command the release depends on needs a runbook step, with its
  precondition and a verify query. Grep the app's seeder/command map for entries no step runs: a
  step that exists only in code is silently skipped on deploy day. Forbid the catch-all form (a bare
  `seed` that runs every seeder) when any seeder must wait for a rehearsal list to be cleared.

## Read-only rehearsal / finance-list scripts
For a script that only lists rows (go/no-go and finance lists for a feature), same proof bar:
- One transaction ending in ROLLBACK; create no temp objects if possible, so a read-only role or a
  replica can run it. Prove it: row count + md5 of every table identical over repeated runs, and it
  runs under `default_transaction_read_only=on`.
- Number the lists; mark each go/no-go (must be empty at the freeze) or finance-info; name owner and
  action. A `strict` psql variable makes the script exit non-zero when any go/no-go list is non-empty,
  and never on a finance-only list.
- Start with a schema check of every release column it reads (exists, type, nullability, default,
  FK): RAISE so a wrong schema fails loudly instead of returning empty lists.
- One query body per list; switch "at the freeze" vs "weekly after deploy" filters with a psql
  variable, not a second copy.
- Money columns aggregated over joined child rows (payments, returns) fan out and multiply totals:
  aggregate each child set in its own lateral subquery. Seed a document with several children to
  catch it.
- Fixtures: at least one hit and one near-miss per list (soft-deleted, rejected, other status, other
  parent); rule mutants (drop or loosen each predicate) must each change a list's output.
- A go/no-go list that guards a later writing step (seeder, backfill) must predict what THAT step
  will do, derived from its code: for each row, say what it would do (adopt / refuse / create) and
  count every owner the step sees, soft-deleted rows and unowned existing records included. A list
  derived from "live rows only" passes while the step still links a row to someone else's record.
- Some outcomes only exist after the step's own choices (next free number, sort order). In the
  rehearsal, run the writing step on the scratch copy, then run the list again; both runs must be clean.
- Control variables fail closed: accept only unset / `0` / `1` and RAISE on any other value. A typo
  like `strict=true` that silently means "off" passes a no-go DB.
- Money lists show each document's status next to its amounts (cancelled payable, write-off vs cash
  settlement, amount still open), or finance reads a cancelled bill as owed and a write-off as paid.
- Every go/no-go row needs a named clearance action that someone can actually perform. If the app
  cannot do it (a read-only field), name the owner who decides and the one reviewed SQL statement that
  clears it, logged in the window log. "Accepted" is not cleared while strict still counts the row.
- Give one remedy per predicted outcome (adopt / refuse / create), and make each remedy change the
  field the writing step actually matches on: renaming a record the step matches by code does
  nothing. Re-run the list after each remedy to prove the row is gone and nothing new appeared.
- Every rehearsal copy replays the whole statement log before its first list run, so the last
  rehearsal executes exactly the window sequence.
- Clearance proven on the rehearsal copy does nothing on prod. The window step must (1) replay the
  logged statements on prod, (2) run the list in strict mode on prod unconditionally, right before
  the writing step (exit non-zero = no-go), (3) only then run the step. A post-step check cannot
  catch it: once a row is wrongly linked it no longer matches the list.
- A remedy that creates a record by hand (a payable account for a party) must be one template
  statement that sets every column the app's own create code sets (posting flag, level, type, normal
  balance, parent, code format, an id generated like the app's so id-ordered locks still hold), with
  a built-in check that raises and rolls back. Prove it with the app's own validation (the journal
  posting check), not only with the list: a plain INSERT takes column defaults, passes the list and
  the seeder, and then every journal on that record is refused after go-live. Check whether the admin
  UI can make the record at all before naming it as the remedy.
- The list of "party linked to a bad record" must cover every condition the posting code refuses
  (non-posting, soft-deleted, missing), read from that code, not only deleted or missing. Add a
  separate list for records the posting check accepts but that differ from the shape the app creates
  (parent, level, type, normal balance, code format): a wrong normal balance passes every gate and
  then books the balance with the wrong sign. Every remedy that links, relinks or flips a flag must
  leave the record in that shape too, not just make the row disappear from the list.
- A standalone go/no-go pre-check exits non-zero on a no-go by itself (no flag needed): `SELECT
  count(*) > 0 AS nogo \gset`, then `\if :nogo` + a `DO` block that RAISEs. `\if` takes only a
  boolean, so gset a boolean, not the raw count. A printed count with exit 0 relies on the operator
  reading it. Prove exit 0 and exit 3 on a throwaway DB holding just the tables it reads (one clean,
  one with a single hit row), then drop it.
- State the script's valid window in its header and in the runbook step: a check that the release
  itself makes non-zero (the release posts the same rows) is valid only before the first release
  document on that DB (prod before deploy, the rehearsal copy right after the schema boots).
- Print the effective control variables at the top of the output and require that line in the
  window log; a bare `-v strict` (no value) means unset in psql and runs as a plain report.
- Retire the record a relink / unlink leaves behind: it stays live under the number the app computes
  for that party, so a party re-created later is silently linked to it by the app's own
  reuse-or-create code, and a post-deploy run with the go/no-go lists off never sees it. Make
  "renumber the old record to a number the app never computes" its own logged statement after every
  relink / unlink. A record the renumber statement cannot handle (e.g. a non-numeric code the app
  casts to a number) goes to a named owner; the row keeps counting until cleared.
- Run every remedy as written (extracted from the runbook text, not retyped) on a messy prod-shaped
  copy, then through the full rehearsal + window sequence to the final strict exit 0.

## Pre-migration count query (user runs it on training/live)
When the PM cannot reach the real DB, hand the user one read-only file that predicts what a
migration's backfill will do, per tenant:
- `BEGIN TRANSACTION READ ONLY; SET LOCAL search_path TO <tenant_schema>; ... ROLLBACK;`, a
  placeholder for the schema, and the psql command line in the header.
- Copy the migration's WHERE verbatim (it is usually exported as a constant) into a CTE; repeat the
  CTE per list instead of a temp view, so a read-only role can run it.
- List 0 = does the guarded table exist here (`to_regclass(...) IS NOT NULL`). Where the migration
  skips tenants without that table, say "false -> skip the rest": the later queries reference the
  table and abort the transaction there.
- Then one count per question the decision needs: rows/documents that will change, edge cases that
  would clash with app rules after the change (two flagged rows on one key), already-billed rows the
  change makes inconsistent (money risk, for manual review), and rows deliberately left alone.
- Prove it before handing over, on a local throwaway DB: substitute the placeholder with `sed`
  into a scratch copy, prepend `CREATE TEMP TABLE <guarded_table>(...)` + one INSERT pointing at a
  known fixture document (temp tables resolve before the search_path schema), run it, and compare
  every count with the fixture's expected numbers. Never prove it on the user's dev/training DB.
- When the user asks whether the count query is needed at all: answer from the migration's own
  code (what it touches, whether it is reversible, what it never changes), name the one risk the
  count would reveal, and offer options: deploy to the training DB first and check real documents
  in the app (recommended when training is a copy of live and the change is a reversible flag),
  the PM runs the query once DB access works, or skip. Mark "training is a copy of live" ASSUMED
  unless the project docs say so.
