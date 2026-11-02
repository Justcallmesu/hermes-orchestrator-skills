---
name: derived-totals-design
description: "Use for totals or paid status fed by events. One writer."
---

# Designing stored totals fed by several events (counters, HM/downtime totals, report rollups)

For features where a stored column (contract HM totals, downtime, usage, a cached sum on a header,
an invoice's paid status) is fed by events from several modules, and/or a report lists the rows
behind it. A wrong total passes every unit test, so map the writers first and red-team before
tickets. Ledger journals have their own skill (`ledger-posting-design`); this one covers
non-journal aggregates.

## Procedure
1. **Map every writer of the column** (grep the column name and `increment(`/`decrement(` on the
   entity): who writes, SET vs increment, from which source, file:line. Two writers with two rules on
   one column (an event `+=` and a periodic `SET SUM(...)`) silently erase each other: the next SET
   drops every increment. If this is a port, read the old app's writers before accepting a premise
   such as "the old app added X to this total"; a wrong premise becomes a wrong decision.
2. **One writer:** replace all increments with ONE manager-based recompute that SETs every derived
   column from source, called inside each event's transaction. It locks the parent row first
   (`FOR NO KEY UPDATE` when other tables FK it) so concurrent recomputes serialize. Document the
   lock order and every caller in its header comment.
3. **List every moment an input changes** (row created, linked, timestamp stamped, reused, soft-
   deleted, cancelled, re-parented) and check each one either recomputes or provably cannot move the
   value. An endpoint that stamps a timestamp the total now reads becomes part of the total: lock the
   row and accept only the expected current status, or a repeated call re-stamps it and the total
   grows with no error.
4. **Units and types:** check the target column type (integer column vs decimal sources: a
   fractional SET fails the cast where the increment was silently rounded; round once in the
   recompute). When a column's meaning changes (engine hours -> clock hours of downtime), change every
   label and doc in the same release and state the unit in the spec.
5. **Same value in two totals on purpose** (repair hours in both maintenance and uncountable):
   state it in the recompute comment, grep every reader for a sum of the two, tell the user.
6. **Report next to the total:** a paged report over several sources is one SQL `UNION ALL` with
   one ORDER BY and `COUNT(*) OVER()`; each row carries its source and a stable key (`source:id`).
   A per-row figure (downtime hours) uses the SAME SQL fragment as the total and is null exactly
   where the total counts 0, so the column sums to the total.
7. **Business rules go to the user** as options with consequences (what feeds the total, from
   which moment a record counts, link windows, which parent a carried-over event counts against);
   record each in the spec decisions table; then cut tickets: shared recompute first, then each
   source, then frontend labels.

## Topic references (read the one that matches before designing)
- `references/settlements-and-credits.md`: a document that pays off an existing amount (refund
  payouts, bulk settlement), or a credit that reduces what is owed on a bill (sales returns, credit
  notes): allocation-derived paid status, frozen credit split, no-money deposit types, item-level
  source guards for multi-delivery credits, the pre-bill credit formula, backfill + status
  recompute, lock and counter order, removing an undeployed payout feature safely, the frontend
  side (empty credit form, server-parity estimate, labels for new row types), and non-cash
  settlement methods (a rounding/write-off method, "settle the remainder" button, per-invoice max,
  bulk opt-in, cent-exact eligibility).
- `references/latest-reading.md`: "show the latest HM/km/meter reading" requests: reading vs total,
  live read across sources, swap-log holder rule, report grain after a swap, time-zone handling.

## Stored status derived from a LIVE total (invoice PAID/PARTIAL computed from a total that sums child docs)
- When a total is computed live (e.g. invoice grand total includes the ongkir of its live delivery
  notes) but a status derived from it is STORED and recomputed only by one writer (payments), every
  writer of any input to the live total is a status writer too. List them (child create, void,
  revise, delete, imports, auto-create paths, credits and their cancel) and recompute the status in
  each one's transaction.
- Export the status rule once (a util taking `manager`) and call it from every writer; never copy it.
- The total used for the recompute must read through the caller's `manager`: an existing
  `computeTotals` that reads via repositories runs outside the transaction and misses the child row
  just written or voided. Until the two are merged, a reviewer must compare the in-tx copy line by
  line with the original (taxes, discounts, rounding, which children count) and a backlog row tracks
  folding them into one formula with an optional manager.
- Lock order for the child path: parent document -> contact/customer -> the status-bearing row
  (reuse the payments' lock helper), re-read and skip it if it was cancelled meanwhile; payments
  lock contact -> row and never the parent, so no cycle. Test both directions (total up: PAID ->
  PARTIAL; total down: PARTIAL -> PAID) plus a forced race against a payment.

## Status rules for a zero / free total ("a Rp 0 invoice counts as paid")
- Before changing a status rule SHARED by several modules (one `resolvePaymentStatus` for sales and
  purchase), grep every consumer and ask what a zero total MEANS there. It differs: a free sales
  invoice (all bonus lines) is settled, while a Rp 0 purchase invoice may be "price not yet
  verified", and a verification queue that lists only UNPAID rows would silently lose it. Put the
  module-specific rule in that module's status util (wrapping the shared one) and keep the shared
  util byte-identical to HEAD; assert it with `git diff --quiet HEAD -- <shared util> <other module>`.
- The rule has to hold at every point where the status is SET, not only in the payment recompute:
  creation (status from the computed total, in create AND in imports), every writer of an input
  to the live total (an ongkir delivery note added turns it back UNPAID, voiding it gives PAID
  again), and the guards that only allow UNPAID (cancel, change date). Widen those guards to
  "unpaid OR free with no live payments", and mirror the same predicate in the webapp buttons.
- Test boundaries at the rounding precision (0, 0.004, 0.01) and mutation-check the free branch.
- A webapp that re-computes totals for display must equal the server: run a parity script that
  imports both formula files under Node (`node --experimental-transform-types` + a resolve hook
  mapping each repo's `@/` alias by importing file) on a few thousand random documents, and run it
  against the OLD webapp file too, to prove it can find a difference.

## Event records that back a total (condition / breakdown / position records)
- Write the record at the step that COMMITS the work (the approval that generates the work order),
  not at an offer/quotation step that can end rejected or cancelled (that counts rejected offers and
  needs delete cleanup). Date it from the earliest real event (when it was reported), so waiting
  time stays in the duration.
- Store the link (`tsrId`: FK + partial unique index when set) instead of guessing it in the report.
  A guess kept for legacy unlinked rows must exclude targets another row already owns, or one
  repair shows on two rows.
- "Open record" linking needs a bounded window (one named constant) and must match the owner slot
  AND the real entity: a swap keeps the slot row (contract vehicle) and changes the vehicle, so a
  slot-only match lets the replacement overwrite the old unit's record; a record from another slot
  (the unit's previous contract) must not link, or its duration counts against the wrong parent.
- Serialize all writers of one entity's records with a lock on the entity row (the record that
  matters may not exist yet, so it cannot be locked).
- **Freeing a record whose linked work died (relink rules):** define "dead link" ONCE (a query
  fragment + a manager-based check) and use it in every linker (auto-link at approval, explicit pick
  from the row). List every terminal way the work can end without a repair: the document rejected /
  cancelled AND a child document cancelled while the parent stays approved (TSR APPROVED + work
  order CANCELLED). Missing one leaves the record stuck and the next repair writes a duplicate with
  a later start time. Confirm each dead status is terminal (transition table) so the read is safe
  under the entity lock alone.
- **Reopen windows: anchor on when the link died, bound both sides.** A window measured from the dead
  document's createdAt never closes (the breakdown is always just before it), so an abandoned record
  is later taken by an unrelated routine document and counts months of downtime. Rule shape:
  `diedAt <= newDoc.createdAt <= diedAt + N days`, diedAt = latest `status_history.changed_at` for
  that terminal status (grep every writer of the status to confirm it logs), falling back to the
  row's `updatedAt` (terminal row, so never earlier). Test both edges (exactly N days, N days +
  1 min, a document created BEFORE the death), each dead path, and the fallback with the history row
  deleted. An explicit user pick needs no window.
- **Links that cross owners:** once a record can be linked to work raised on another owner slot
  (after a swap / return / move), the completion step must recompute every owner of every linked
  record, not only the work's own owner, locking them in ascending id order. Seed the other owner's
  total with a stale value in the test to prove it was recomputed.
- Raw SQL fragments in a TypeORM query builder: TypeORM rewrites `alias.property` only when followed
  by a space, `=`, `)` or `,`. Keep such fragments on one line (`[...].join(' ')`) and use
  `CAST(x AS text)`, not `x::text`. One named parameter binds one type, so an enum column and a
  varchar column compared with the same value need two parameter names. A bare parameter in
  `$n - timestamp` has no inferable type: write `CAST(:p AS timestamp) - <expr>`; the subtraction
  form (`now - diedAt BETWEEN make_interval() AND make_interval(days => :n)`) also keeps a long
  died-at expression to one copy.
- Removing a cross-table increment from a status transition can remove a deadlock entirely: if the
  total only changes at a later step that already recomputes, drop the increment and its parent
  lock rather than reordering locks around it.

## Pitfalls
- Before trusting any column a total or report reads, grep its WRITERS outside specs
  (`grep -rn '<prop>\s*=' src | grep -v spec`). A column only fixtures seed (a work order's `endHm`
  while the app writes the end reading into `currentHm`) makes every test green and the real total
  always 0. Fix on the read side with ONE exported SQL helper used by every reader. A numeric
  transformer whose `to()` turns null into 0 stores "never written" as 0, not NULL: treat unset as
  `COALESCE(NULLIF(col, 0), fallback)`. Seed at least one regression test through the real service
  path (report submit -> QC approve), not by setting the column.
- RED test for the overwrite bug: credit the total through event A, then save a source of writer B,
  assert A's credit survives. It fails on HEAD with the exact lost amount.
- Mutation-check the guards (parent-type skip, status filter, link window, slot + entity match). A
  redundant clause (`IS NOT NULL` inside `GREATEST`, which already skips NULL) survives mutation by
  design: note it instead of chasing a test.
- Adding a time bound breaks old tests that backdate `createdAt` while the real transition stamps
  its history row at the real clock: the seeded timeline becomes impossible (death after the new
  document). Fix the seed to a possible order (move the history `changed_at` / `updated_at`
  before the new document; backdate `updated_at` with raw SQL, since a repository update re-stamps
  an `@UpdateDateColumn`), never loosen the rule; report which tests changed setup and that their
  assertions did not.
- A header total frozen from line values (quote subtotal = sum of line subtotals) must sum the
  values as STORED (rounded to the line column's scale), not the in-memory unrounded results the
  freeze just computed: otherwise the printed lines do not add up to the printed subtotal, and any
  client preview that sums the stored lines is a cent off. Changing it moves new frozen totals by
  up to 1 cent, so ask the user (sum stored lines / keep status quo) before briefing, and note
  "existing rows not backfilled" for deploy.
- Existing rows keep their old stored value until their next recompute: say whether a backfill is
  needed and list parent types the recompute skips (they keep stale values forever).
- Appending to a run log with a patch tool: anchor on the LAST entry's unique text. Repeated phrases
  ("Waiting on review.") match the first occurrence and splice the new entry into an old one.
