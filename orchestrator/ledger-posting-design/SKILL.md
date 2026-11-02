---
name: ledger-posting-design
description: "Use when designing auto-journals or cancel reversals."
---

# Designing automatic ledger postings from business documents

For features that make an existing flow (receipt, generated PO, return, payment) post a general
ledger journal, or change what it posts. Money: a wrong design passes every test, so design and a
fresh red-team come before any build ticket.

## Procedure
1. **Map what posts today, per step.** For the sibling flow that already posts (the template) and the
   flow being added: every step (create, approve, generate, invoice, payment, each return type,
   cancel) -> journal written or not, accounts, amounts source, file:line. Prove it with a throwaway
   test that drives the real services and counts journals per step. Grep every journal writer (services,
   triggers, scheduled jobs) so "posts nothing today" is verified, not assumed; a missed writer means
   double booking.
2. **Pick the trigger** as the point after which the amounts can no longer change through the normal
   flow. Then enumerate EVERY write path to the documents the journal is computed from, including the
   generic CRUD/status API of a generated document (edit, reopen, cancel) AND every other service
   that takes that document's id from a request and writes against it (e.g. a receipt or delivery
   created on a PO by id; such services often check neither origin nor status, and a negative qty
   can reopen a closed document). Each path either is frozen for
   documents that came from this flow (named 4xx pointing to the correct flow) or reverses the journal.
   A status API with no transition guard lets a partly posted document be re-opened, edited (qty,
   price, charges) and posted again against new amounts. Offer the user "lock after the first
   live receipt or any invoice settlement, correct via return" (recommended). Lock the document row
   in the re-open path so a concurrent receipt create serializes with it. Also fix the re-approve
   dead end: if the invoice already exists and is unsettled, refresh it instead of refusing a
   second create.
3. **Amounts:** the journal must equal the invoice/payable per document, using the same exact-amount
   rule as the template; give worked examples (unit/box price, discount, tax, partial returns) the
   build tests will assert. Check every extra charge the journal credits to the party (freight,
   handling) against WHEN and FROM WHAT the invoice is created: an invoice made at approval from
   the document's base total leaves the charge owed after a "full" payment, which makes aging and
   party balances wrong. Put the sum in one shared helper used by every invoice creator, then grep
   every reader of the invoice total (lists, reports, dashboard, credit-note spend, cancel, return)
   for a comparison against the base total. Edge case to hand to the user: base 0 + charge > 0
   (the invoice shows the charge while a qty-split journal books none).
4. **Reversals:** no reversal may post more than is still posted for that receipt. Check the template
   flow for the same double reversal (cancel after a credit note); if it has it, fix both flows in the
   same ticket. Before choosing "cancel reverses only the remainder", read what cancel does to the
   subledger: if it zeroes the invoice payable while the party keeps a credit note from an earlier
   partial return (possibly already spent), a net reversal leaves GL and subledger disagreeing. Then
   make whole-document cancel and partial credit-note returns refuse each other (checked at create,
   approve and again at completion under a per-document lock that only these return paths take, e.g. a
   namespaced advisory lock, not the document row (see `postgres-concurrency-guards`); rejected ones
   don't count), and let cancel on
   a clean document reverse every receipt journal in full, idempotently.
5. **Existing data:** prefer cut-over over backfill (backfill posts into closed months and must net
   corrections already made at old amounts). Decide eligibility PER DOCUMENT and store it (column,
   default false for existing rows, true on create); exclude documents with corrections made before
   deploy, unlinked lines, or anything the journal cannot be computed for exactly, and hand those to
   finance as a read-only list.
6. **Item kinds the template filters:** check every special item kind the template skips or routes
   elsewhere (fuel, services, expense-only items without a stock account). Refuse the kind at document
   entry, or exclude the document and list it; never let the journal disagree with the invoice.
7. **Check each decision's premise before recording it** ("the template has the same restriction",
   "no rows like this exist"): count or read the code. A blocking rule on a wrong premise can stop
   suppliers being invoiced or paid; prefer "no journal + finance list" over blocking the business flow.
7b. **Accounts created on the fly** (a per-supplier/per-customer payable or receivable account made
   when missing): a computed account number can collide (zero-padded codes, a numeric code equal to
   a generated number), and reuse-by-code then credits one party's balance to another's. Before
   reusing an account, refuse one already linked to a different party (skip -> finance list, write
   nothing). Serialize next-number picking by locking the parent account row. Wrap the creation in a
   savepoint so a document that ends up skipped keeps no account it made. Have the rehearsal list
   accounts linked to more than one party and duplicate codes.
   Count soft-deleted parties as owners too. The legacy seeder/backfill that links parties to
   accounts must run AFTER the collision list is resolved, or it links a party to an account named
   for another party. When a new party's computed number is taken, leave the party unlinked (the
   UI shows that an admin must act) rather than quietly sharing the account or changing the
   numbering rule. Picking a different numbering rule is a business decision for the user.
   Skip vs block: missing per-document master data (an item stock account, a party account) ->
   skip + finance list. Broken configuration (a settings account unset, a header account used for
   posting) -> refuse with a message naming the setup to fix, same as the template flow.
8. **Business decisions go to the user** (trigger point, existing data, refusals, AP vs a
   goods-received account) as options with consequences; record them; then a fresh red-team of the
   design; record amendments as new decision rows naming what they replace; only then cut tickets:
   guards first (freeze/refuse, no journal yet), then the posting, then each reversal, then the finance
   list.

## Cancel / void of a document that wrote ledger rows (Kas, deposit, points, journal)
1. Inventory every cancel/void/delete path that removes ledger rows: grep `softDelete|delete|remove`
   on each ledger entity and on every `reverseSource*`-style helper; tabulate flow -> today's effect ->
   file:line. Look for an in-repo flow that already reverses correctly and name it as the template.
2. Ask the user (one clarify call): which ledgers get reversal rows (money vs stock), the reversal
   date (cancel date keeps closed days stable; original date rewrites them), whether the cancelled
   document stays visible, and which deletes are typo fixes that stay real deletes.
3. Rule: keep the original row, insert an opposite row with the same source FK and reference number,
   the cancel date, the user, and a note naming the document and reason. Idempotent: skip sources
   already reversed. One shared reversal helper per ledger, reused by every caller.
   Idempotency by "count existing reversal rows" is only safe under a lock: two concurrent cancels
   both read 0 under READ COMMITTED and both write (double credit), whereas the old delete was
   harmlessly repeatable. Every cancel/void must lock the source document row (`pessimistic_write`)
   INSIDE the transaction and re-check its status there; a status check done before the
   transaction is a race. Audit sibling actions on the same document (settle/pay vs void) for the
   same read-outside-transaction shape.
4. Keep the cancelled document's own row hidden from totals the way it is today (soft-delete) when
   many readers sum it; expose it only through an opt-in list parameter (`includeCancelled`,
   `withDeleted`) so no other reader needs a new filter. A client that sums the opt-in list must
   exclude cancelled rows AND must not read a capped page (`limit: 100`): cancelled rows eat the
   cap and understate the total; use the non-paginated form. Note reports built from the document
   table instead of the ledger (e.g. cash flow from payments): there a cancel still vanishes from
   its original date, contradicting a "cancel date" decision; report it as a pre-existing gap.
5. A new entry type/source must be classified everywhere the ledger branches on type: the sign
   helper, cash-flow/report filters (a reversal of a no-money row moves no money either), webapp
   labels and sign tables, exhaustive enums; add the enum values by migration. A new source with its
   own document FK column must also be added to the shared reversal helper's copied FK list (and its
   override type): the helper copies only the FKs it knows, so the reversal row loses the link while
   the balance still nets, and "which rows belong to document X" misses half the pair. Match the void
   on `{ <newFk>: id, source }`, with no reference-number fallback for a source that never lacked the FK.
6. Ledgers replayed by lots (points, batches with expiry): never reverse with a plain negative row
   that the replay consumes FIFO. It hits the oldest lot: it refuses valid voids of expired points,
   eats unrelated live points, and revives expired points. Plan the reversal from the source's own
   lots in a pure util. The rules (deterministic tie-break, restore onto the original lot capped at
   what the source still takes, skipping already-voided sources, reversal date, the spend guard
   under dated rows) and the required unit specs are in `references/lot-replay-reversal.md`.
   Ask the user two business rules up front, in one clarify: is a void refused when its points are
   already spent, and what remains when two linked documents are both voided.
6b. **Close input freedom before adding replay logic.** If review rounds keep finding holes from
   one input (a back- or future-dated document date), check whether the UI can even produce it
   (grep the client for the field). If only the raw API can, recommend that the server set the
   value itself (today, in the business time zone) over more replay rules. A client that sends
   `new Date().toISOString()` gives a date in UTC, which is yesterday for early-morning sales in
   UTC+7. Keep fixes that are already built and reviewed; they still protect old data.
7. Legacy rows written before the reversal change may lack the source FK; the reversal finds them by
   a fallback (reference number scoped to the same source and account), never reverses the same row
   twice, and the brief lists that fallback explicitly.

## Moving the date of an already-posted document (stock out, journal)
When a user may edit a document's date after it posted (e.g. a delivery's date at the final step):
1. Move every copy of the date in ONE service method inside the document's transaction: the header,
   its lines, and every per-lot/per-batch movement row. Grep for each table's date column; a copy
   left behind splits reports from the ledger.
2. After moving, re-run the never-below-zero balance check per product + warehouse over the affected
   date window. Share that loop with the reversal path; do not copy it.
3. Refuse (clear 400, nothing moved) the moves that silently rewrite history, and make the refusal a
   decision row for the user: a stock recount (REPLACE / Stock Aktual) of the same product +
   warehouse between the old and new date (the recount absorbs or releases the movement and today's
   balance changes); a lot that is expired on the new date (reuse the posting's expiry rule); a new
   date after a dependent document (a return of this delivery). Same-date move = no-op.
4. Tests: a multi-line, multi-product document (every per-product loop runs), each refusal leaves all
   rows unmoved, and a move after a revise moves the re-posted rows.
5. Red-team brief items: every date copy, the balance check's completeness, lock order versus the
   other paths on the same rows, and what a revert of the step does to the moved date.

## Parent documents that create child postings (bulk payment -> per-invoice payments)
- When a parent posts one ledger row for the whole document and creates children through the
  single-document service, the child path must skip its own posting when the parent id is set;
  otherwise every amount is booked twice and the parent's void reverses only half. Keep one shared
  validation helper (account exists, right type, not archived) used by both paths, run before any write.
- Acceptance tests assert the exact balance delta (== total, once) and the exact number of ledger
  rows per source after create and after void, not just "balance went up".
- Assert FK fields (e.g. the chosen bank account) are persisted on the document: a field assigned
  after `save()` and never saved again is silently lost and no typecheck catches it. Check the
  parent's own FK too, not only the children's.
- A posting fix for a bug already on a pushed/shared branch leaves wrong rows in every database
  that ran the buggy code (dev, staging), and the new reversal logic will not undo them. Add a
  board row: ask the user whether such documents were created there, and write a one-off cleanup
  if so.

## Review loop for money changes
- After each fix round, run a fresh reviewer on the DELTA only, and give it the previous round's
  attack specs (kept in scratch) to re-run against the repo code. Ask for severity based on a
  realistic user flow, with a concrete history and numbers.
- A reviewer's prototype fix is input, not the answer: have the developer port it and check that
  it meets every spec history. Dropping an excess instead of keeping it can be the correct
  deviation; record it as a technical decision row.
- A migration that names a FK must match the entity (`@JoinColumn({ foreignKeyConstraintName })`),
  or `migration:generate` sees drift.

## Pitfalls
- A null journal reference on an invoice/payable means "never journaled", not "booked elsewhere";
  confirm by reading the writer before assuming double booking either way.
- Guards that change when an existing flow is allowed (e.g. no credit-note return before generation)
  must be checked at create AND approve, and they rewrite existing tests' setup; list each rewritten
  test and STOP if any expected amount changes.
- A new "refuse kind X on this document" guard on update must refuse only X lines the edit ADDS,
  never ones already stored: checking stored lines strands legacy documents (every edit refused,
  cancel-only). Route those legacy documents to the finance list and count them in the rehearsal.
- The ticket that starts posting for a flow invalidates existing tests that pin "this flow posts no
  journal" (e.g. a return of its goods credited at the raw goods value). When briefing the reversal
  ticket, grep for those tests and give their new expected amounts in the brief: the share of the
  posted amount, computed by the template's formula on the same fixture. Update the expectation and
  keep every other assertion; turning the fixture into legacy data instead leaves the new path untested.
- A reversal on a group of source lines (one stock line merged from several receipt lines) must
  refuse a group that mixes posted and unposted members, or a line with an earlier legacy credit that
  stored no amounts, before any goods move. Otherwise the remainder rule credits against a base that
  was never posted. Build the group with the posting's own membership filter (e.g. qty > 0 lines
  only): a zero-qty member that was never posted otherwise makes every group "mixed" and blocks all
  returns. Run such refusals at create and approve through one shared read-only check, and keep the
  locked check at completion as the backstop.
- A new lock on a status path breaks existing tests that BUILD their fixture through that path
  (e.g. re-open + supplier change to set up a guard scenario). In the brief, have the developer grep
  specs for the status value, keep each test's protection (build the state another legitimate way,
  or turn it into a "refused" test), list every changed test, and report guard code that becomes
  unreachable instead of deleting it.
- A freeze leaves documents stuck in whatever non-final status they had at deploy; count them in the
  rehearsal so the business finishes them first.
- The posting ticket and every reversal ticket ship in the same release. A posting without its
  cancel/return reversals leaves journals on cancelled documents, and returns completed in between
  store no journal amounts, which later returns must refuse. Add a rehearsal count for those (must
  be 0).
- Name residual gaps for finance (journal vs stock value after a short inspection, document date
  posting into an earlier month, payments that never debit AP) instead of silently inheriting them.
- Cutting an invoice/payable to what was received (closing a partly received order): before
  defining the cut amount, read how returns already touch the payable. When a return only raises a
  party credit note that later lands on the payable as a CONFIRMED settlement, the cut must sum
  live receipts only (stored posted cents, legacy rows by the frozen formula, a stated rule for
  missing freight); subtracting returns counts them twice. The resize itself is one public method
  on the payable service: caller holds the payable lock, refuse CANCELLED/WRITTEN_OFF, any PENDING
  settlement, and confirmed > new total; then remaining = new total - confirmed in cents and the
  status from the service's existing derive function (never a copy). Test with a property: on a
  fully received document the helper equals the original invoice total.
