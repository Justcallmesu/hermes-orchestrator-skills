# Settlement documents and credits against a bill

Two shapes that sit on top of an amount already stored on other rows (a return's refund, an invoice's
outstanding). Business half (are old rows already settled? which report date?) lives in
`pm-feature-work` 5b; these are the technical rules red-teams and reviewers checked.

## Settlement documents for an amount that already exists (refunds, fees paid in bulk)
A header + allocation document that pays off an amount stored on other rows (a return's refund).
- Paid = SUM(allocations whose header is ACTIVE), derived in ONE helper (pure maths + one grouped
  query) used by list, detail, open list, preview and create; no stored paid/status column, and no
  per-row payment table when there is no single-row payment flow (it would duplicate allocations).
- Allocation table: FK to the settled row RESTRICT (never CASCADE money history), header FK CASCADE
  is fine, `UNIQUE(header, row)`, `CHECK (amount > 0)`, and an index LED BY the settled row id (the
  unique index leads with the header, so per-row lookups scan). Split with the existing
  allocation helper so allocations sum exactly to `round2(header total)`.
- Create locks contact row -> settled rows by id, no joins, `ORDER BY id` -> cash account -> number
  counter, then re-reads status/type/amount AND ownership (contact via joins) from the locked rows.
  Cancelling a settled row locks that row first, re-reads its status, refuses while an ACTIVE
  allocation points at it, and never locks the contact (no cycle with create).
- Void keeps allocations as history and reverses the cash movement with a reversal row that carries
  the same document FK (extend the shared reversal helper; existing callers must get null).
- Tests: forced-order race in BOTH orders (create-then-cancel, cancel-then-create), not only
  `Promise.all` rounds, since one order usually always wins and two requests that both take the
  contact lock first serialize there, proving nothing about the locks after it. Force the order from
  the test: a pg client holds the contested row (`SELECT ... FOR UPDATE` in an open transaction), fire
  request A, wait until `pg_stat_activity` shows it waiting, fire B, release; then swap. Plus a
  mutation removing the cancel's lock or guard; a race test that stays green with the lock removed is
  named for what it really proves. Add integrity SQL: ACTIVE sum <= amount, no ACTIVE allocation on a cancelled row.

## Non-cash settlement methods (rounding / write-off of a small remainder)
A request like "add a Diskon payment method and a button that clears the remaining balance".
- Name it for what it is: clearing a sub-unit tail is ROUNDING ("Pembulatan"), not a discount. A
  "Diskon" label misleads users into commercial discounts and reads wrong on the purchase side (a
  gain there). Offer the name as a decision with a recommendation.
- The safety guard is a per-company maximum (a setting, edited with the existing settings
  permission), applied PER INVOICE as the sum of live rounding payments (cancel + re-round cannot
  get around it), not a new permission. Rules that make it a write-off and not a free-invoice
  button: the amount always equals the whole remainder (no partial rounding), and the invoice
  must already have a live non-rounding payment (an unpaid invoice whose total is under the max is
  never closed by rounding). One util holds the throwing guard AND a non-throwing allowance
  function (for bulk/preview) built from the same rule, so the maths exists once.
- When credits (returns) reduce the outstanding and the user counts them as real settlement, define
  "real settlement" ONCE (`paid excluding roundings + credited > 0`) and use it in the guard, the
  settle endpoint, the bulk allowance and the screen eligibility; the bulk allowance must also take
  the outstanding from the same settlement helper (credits subtracted), or a flagged bulk aborts on
  any invoice with a credit. Make the refusal text name what counts per side (sales "pembayaran atau
  retur", purchase just "pembayaran" when purchase has no credits).
- Validate the max setting as a finite number >= 0 on save; an unparseable value otherwise reads as
  0 and silently disables the feature. Skip the customer "payment received" notification for the
  method, and skip it when a template picks "the latest payment".
- Copy the existing no-money method (uang muka / DEPOSIT) instead of inventing a shape: it counts as
  paid in the settlement helper, carries no payment detail (add it to the no-detail method list),
  writes no cash/bank movement, and is skipped by the cash-flow report's `isMoney` filter. Grep
  every `=== 'DEPOSIT'` / `!== 'DEPOSIT'` and method-label map (server reports + frontend label
  record) and decide per hit whether the new method joins it.
- The "settle remainder" button posts no amount: the server computes the outstanding under the
  invoice lock via the shared settlement helper and creates one payment for exactly that, so a
  stale screen cannot over- or under-settle. Reuse the normal payment `createInTransaction` so
  status recompute, status history and numbering stay one path; the normal cancel then reopens it.
  If that is done with an "amount = whole remainder" sentinel, bind it to the rounding method and
  refuse a resolved amount <= one cent inside the shared resolver; a sentinel any method can use
  writes zero/negative payments the day a second caller appears.
- Bulk payments: make rounding opt-in (a flag), one rounding payment per invoice that got money from
  THIS bulk, linked to the bulk (void cancels it) but outside the bulk total, allocations and the
  bank movement, and never spread the bulk DTO into it (bank/detail fields would leak). An
  ineligible invoice is skipped, never fails the bulk; preview shows the per-invoice amount.
- Eligibility in bulk/preview must compute "remaining" with the guard's EXACT formula. The ledger
  loader's outstanding (`round2(raw total - paid)`) and the payment cap (`round2(round2(total) -
  round2(paid))`) differ by a cent on half-cent tax totals; the allowance then says "within max",
  the guard refuses, and the whole bulk transaction rolls back. Do not wrap the call in try/catch:
  a caught error inside a Postgres transaction still aborts it. Test with a half-cent grand total
  (e.g. PPN on a non-line-based invoice) sitting exactly at the max after the bulk.
- Tests that prove the rules: a mutation that disables the guard call, one that disables the
  "real payment first" check, one that removes the bulk skip; plus an invoice in the bulk selection
  with a tail but no allocation (an unpaid one proves nothing: the real-payment rule refuses it anyway).
- Screens: the button and the method option show only when the server rule holds (not cancelled,
  create-payment permission, remainder > one cent, a live real payment exists, remainder <= max minus
  live roundings), computed in ONE shared util/hook used by the sales and purchase pages. Compute
  the remainder from the SERVER's grand total with the server's per-term rounding, never a page-side
  recomputed total. Read the max through the permission-free settings read if one exists (check the
  server), and keep the button hidden until the max has loaded. Picking the method locks the amount
  to the remainder and hides AND drops every money field (bank, detail, reference number, deposit);
  clear the picked method when the invoice stops qualifying (refetch, another tab). The max setting
  field is required with min 0 and a "0 = off" hint; mapping an empty field to 0 switches the
  feature off company-wide with a success toast. Show the confirm amount with cents (a whole-rupiah
  formatter turns 0.50 into Rp 1).
- Before writing a "run the seeder after deploy" step for a new setting key, check whether app
  start already syncs missing default keys into existing tenants; a reviewer's deploy-step claim is a
  claim until the startup path is read.
- A TS payment-method enum is stored as a separate PG enum type on EVERY table that uses it
  (invoice payment, bulk payment, deposit ledger): adding a member needs `ADD VALUE` on each, and a
  DTO on a table that must not accept it (bulk payment, deposit entry) needs an explicit refusal.
  Guard each `ALTER TYPE` with `to_regtype('"<type>"') IS NOT NULL` (a `DO $$` block): `ADD VALUE
  IF NOT EXISTS` guards only the value, and a branch merged meanwhile may drop one of those tables'
  types in an earlier-sorting migration, which then fails every tenant's migrate and new-tenant
  provisioning.
- Every customer-facing place that prints payments (statement / kartu piutang lines, statement
  email, reminder templates) must label the method by name ("Pembulatan <invoice>"), not "Payment
  (<RAW_CODE>)": the customer otherwise reads a write-off as money received. Drop any reference
  number the API sends on a rounding row server-side; hiding it in the form is not enough.
- Business questions to put to the user before the spec (options + consequences): name; sales only
  or purchase too (and bulk payments); max-amount setting vs its own permission (a no-limit one-click
  button is the dangerous shape); max per invoice or per payment; allowed on an invoice with no real
  payment yet; selectable in the normal payment form (amount locked to the remainder) or button-only;
  settlement-only vs reducing the invoice total/tax (changing issued tax figures needs a credit
  note — recommend settlement-only); whether a credit (return) counts as "real settlement" when
  credits reduce the outstanding; what happens when the only real payment is cancelled while a
  live rounding remains (refuse / auto-cancel / leave, invoice then shows paid with no money), and
  the same question for a CREDIT cancelled after a rounding relied on it (the leftover rounding can
  then be large, up to the credit-settled tail); a hard ceiling on the max setting or trust the
  settings permission. Whatever is chosen for "leave it", record it with an API case that asserts the
  resulting status after the cancel and after the manual rounding cancel. Also check whether commission
  or incentive reports read payments, so a write-off does not pay commission.

## Credits against a document's outstanding (returns / credit notes that reduce a bill)
When a later document (a sales return) must reduce what is still owed on an invoice, outstanding
stops being "total - payments".

### Where the figure lives
- Change the outstanding ONCE in the shared ledger loader (add a `returned`/credited field and
  subtract it); list every reader that does NOT go through it (payment cap, stored PAID/PARTIAL
  status rule, statement lines, as-of views, invoice detail, contact report, recap/print screens)
  and patch each. The credit documents' create AND cancel become new callers of the status rule.
- One settlement helper (`total, paid, credited, outstanding`) for the payment cap, the stored status
  rule, detail API, delivery-note status sync AND notification templates; grep `grandTotal - paid`
  (and the local-language "sisa") across services and notifications after the change.
- Grep for screens that ALREADY subtract the credit themselves (a recap printout netting returns
  per order): once the loader is net they subtract twice. Keep the figure as an info column only.
- Statement and contact reports subtract the DEDUCTION, never the full credit amount: the deposit
  part is already counted in the deposit balance column.
- Round each term BEFORE subtracting (`round2(total) - round2(paid) - round2(credited)`, floor 0),
  the form the payment cap and the PAID rule already use. A ledger that subtracted unrounded values
  disagrees with the cap by a cent on half-cent totals with a partial payment; unifying moves the
  ledger figure by ±0.01 on such old rows. Record that as a decision and tell the user.
- Adding paid/credited/outstanding to a shared `totals` object leaks them through every endpoint that
  returns that object as-is, including unauthenticated share links. Grep the object's consumers and
  keep public ones on the document totals only unless the user asked for payment state there.
- Mutation for the PM check: remove the credit term from the shared rule; the suite must fail on
  every reader (detail, cap, PAID status, ledger/as-of, bulk open list, notification text).
  A reader that stays green has no test.

### The split
- Freeze the split when the credit is created, under the locks:
  `applied = min(credit, total - paid - earlier applied)`, `excess = credit - applied`; store both on
  the credit row. Payment create/cancel never re-split; without stored figures a payment cancel
  silently brings back an excess that was meant to be ignored or already moved to a deposit.
- Excess posted to a deposit/advance ledger must use NO-MONEY entry types (new credit and
  credit-reversal types in the no-money list, a new source enum value): a plain DEPOSIT row shows in
  the cash-flow report as cash received. Fold sub-rupiah excess into `applied` instead of posting it
  (`applied = credit, excess = 0`; outstanding floors at 0), so `applied + excess == credit` always
  holds: assert it in code. "Capped at outstanding" here breaks that invariant.
- Price a credit from the BILL only (net unit after line + header discount, times the bill's tax factor;
  no fallback to the order price). Per-credit rounding over-refunds a line returned in pieces (3 x 1
  unit gives 900.00 for 899.99): price the credit that reaches `returned == billed` on a line as the
  line's rounded net minus the refunds the earlier live credits on that line STORED. Store the refund
  per credit ITEM (a column, last slice of a line takes the remainder, header = sum of items, no
  second rounding); recomputing earlier shares from quantities breaks after cancel + re-credit of a
  closed line (the closer stored the remainder, the recompute uses q x unit: 899.98 for 899.99).
  Test 1+1+1, cancel-after-close then re-credit, and 0 left (progress shows 0, not 0.01). The net
  unit excludes shipping, so a fully returned bill still owes its shipping; say so in the spec.
- The new per-item refund column is NULL for older rows (use a nullable numeric transformer; the usual
  one stores NULL as 0). The "earlier on this line" sums must skip NULL items for BOTH quantity and
  refund (`refund IS NOT NULL`): counting their quantity but not their refund makes the closing credit
  refund those units again (1499.99 on an 899.99 line).
- Write the RED case for such a fix through the API (stored credit totals, bill outstanding, deposit
  balance) and keep any SQL check on the new column in a separate step: on the old tree the column is
  missing, so a single combined check fails on "column does not exist", which proves nothing.
- A residual of 1 cent between the sum of fully credited lines and a multi-line bill's grand total
  is inherent to per-line rounding; each line closing exactly + `applied + excess == credit` is the
  bar. Record it as accepted rather than chasing it.
- A TS enum shared by two tables (customer and supplier deposit type/source) maps to one PG enum
  type per table: add the new value to ALL of them in one migration separate from any migration
  that uses the value, or `migration:check` drifts.

### Create and cancel
- Lock order for credit create AND cancel: the order row first (same as the delivery-note void path,
  which locks order -> delivery -> contact -> bill), then contact -> bill -> source rows by id ->
  document numbers. Document-number counters are locked rows too: take them in the order other paths
  take them (deposit counter before stock counter, as POS does), or two unrelated customers deadlock.
- Cancelling the credit: refuse when its deposit part is already used (same rule as deleting a used
  deposit), else post the reversal, restore the deduction, recompute status. Refuse cancel / date
  edit of the bill (and un-verify of a source delivery) while a live credit exists.
- Validate credit date >= bill date and >= the source delivery date, or as-of views and the restock
  date precede the outbound.

### Stock and billing caps
- A credit that also moves stock needs the shipped source line (warehouse, lot, conversion all
  come from it): split each credited line into slices per delivery line (newest verified first,
  `NULLS LAST` on the verified time, capped by delivered - already returned), one stored item per
  slice. Goods invoiced but never shipped cannot come back as stock: refuse or make it a business question.
- Credits split over several source documents: every guard and cap that reads the credit HEADER's
  single source FK ("returned so far on this delivery note", un-verify / void / revise / date move of
  a delivery note, import revert) misses the other slices and lets stock be released twice. Key them
  on the ITEM's source line, and test a 2-source credit against the older source.
- Make the billing cap net of credits taken before the bill exists (billable = delivered -
  returned), or returned goods get billed in full and then deducted. Then a credit taken BEFORE the
  bill must deduct 0 when it is later bound to that bill (bind the header only, keep its items out of
  the per-bill-line cap): the bill already excludes those units. One formula serves binding and the
  backfill, per order line: `deductible qty = min(R, max(0, I - (D - R)))` (D delivered, R credited,
  I billed), priced at the bill line's net unit and capped by the credit. Count only money credits
  (REFUND) in the cap and the formula; exchange returns leave the bill unchanged. Change the
  "billable quantity" progress endpoint the form pre-fills from in the same ticket.
- Binding unbound credits at bill create: lock them FOR UPDATE after the order lock and re-read status,
  or a concurrent cancel commits first and the binding writes onto a cancelled row.
- A pre-bill credit bound with deduction 0 must not be cancellable while its bill is live: cancel puts
  the goods back with the customer, the net bill never bills them, and the bill cannot be edited.
  Refuse with "already counted in bill X, cancel the bill first" (detect it by ONE named predicate:
  bound, deduction 0, deposit 0, no item bill line), and let the bill-cancel guard skip such credits
  so the order cancel bill -> cancel credit -> re-bill works. Apply the REFUSAL to money credits
  (REFUND) only: an exchange was never netted by the cap, so refusing it leaves no billing reason and
  becomes a permanent dead end once the bill has a payment. The predicate itself (skip + release)
  still covers exchanges, and the backfill must bind old rows so they match the same predicate. Without the skip the two guards block
  each other. A suite asserting "cancelled, bill still owes the net" locks the gap in: rewrite it.
- Bill cancel must also RELEASE those header-bound credits (unbind: bill FK -> NULL, locked FOR UPDATE
  in id order after the bill check), or the next bill (net billed by the cap) never re-binds them and
  the credit cancel guard no longer fires: cancel A -> bill B -> cancel credit -> unbilled goods again.
  Bill cancel then needs the ORDER row lock first (order -> contact -> bill -> credits), the order
  credit create/cancel and bill create already use; a bill cancel that locks only contact -> bill races
  bill create on the same order. Race bill cancel vs bill create and vs credit cancel, both orderings.
- Credit cancel reads its bill link AFTER the order lock (re-read the row), not from the unlocked
  lookup that told it which order to lock: a binding committed while it waited is otherwise missed.
- Every report that subtracts credits by their own amount (tax/PPN, Retur columns) must skip the
  already-net pre-bill credits too, or it reduces twice. Tax is a business rule: put it to the user
  (fix from go-live / fix history / keep) before changing it.
- A report row that lists bills found by "credit in period OR payment in period" must sum credits by
  ONE rule for every row (credits dated in the period), or two rows of the same shape show
  different Retur figures. State the rule in the report note.

### Old credits at deploy
- Decide (business) whether they reduce their document, how far (down to 0, excess ignored, is the
  safe default), and what happens to credits whose order has no bill yet. Run a read-only count of
  each case on the real DB before the user decides. The exact split needs the app's total formula
  (taxes, discounts, shipping), so backfill with an app-side script, not SQL, using the formula above.
- The backfill re-runs the stored status rule for every touched bill (with one status-history row),
  or fully offset bills stay UNPAID, keep the pay button and keep sending reminders.
- Bind old credits at the HEADER only (bill FK + deduction, deposit 0); never give old items a bill
  line or split them: items hold the stock-adjustment link, and the delivery-line cap already stops
  the same units being credited twice. Their per-item refund stays NULL (see the NULL-skip rule), so a
  later new credit on that line is priced q x unit, not as the closer. Say this cost in the spec.
- Ship it as a script, not an automatic migration: dry run by default printing per tenant the counts
  (bound with deduction, bound header-only, exchange, left unbound with reason, total deducted, excess
  ignored, bills whose status changes), `--apply` to write, idempotent (a second run finds nothing).
  Deploy order: stop app -> migrate -> dry run -> finance reads the summary -> apply -> start app.
- Check every state the backfill writes against every guard predicate keyed on the same columns. An
  old money credit on an already-paid bill gets deduction 0 (excess ignored), which looks exactly like
  the "pre-bill credit, already netted" state that the cancel refusal keys on. A paid bill can never be
  cancelled, so that credit can then never be cancelled either. Have the reviewer reproduce each such
  overlap with a fixture (assert the cancel returns 4xx on the old script, 2xx after). Fix it without
  loosening the guard: bind with deduction 0 ONLY when the bill really billed net (the formula gives
  deductible qty 0); a credit whose 0 comes from "bill already paid" or "stored refund 0" stays
  UNBOUND and goes in its own finance list (excess ignored, with its value).
- Leaving a row unbound puts it back in the population that bill-create binding scans ("pre-bill
  credits waiting for a bill"). Check what a LATER bill on the same order does with it: if it binds
  it with deduction 0 the same dead end returns. Make the reviewer prove it with a fixture.
- Recompute each touched bill's status ONCE per bill: run the apply in one transaction per order
  (not per credit) so a bill touched by several credits gets one status-history row (first -> last).
- Rows the backfill cannot bind with certainty (an order line on two bill lines, several live bills
  but none for this line, a new-style credit already on that bill line, items on another order's
  delivery, no items, no live bill) are left unbound and listed by number with a reason, never guessed.

### Screens (frontend side of a credit feature)
- The credit form must start with NO lines: the user adds what really comes back through the picker
  (quantity defaults to what is still creditable, editable). Pre-filling every line of the bill at
  full quantity makes one Save credit the whole bill into the deposit, and once that deposit is used
  the cancel is refused. Refuse an empty or all-zero save in the form with a local-language message;
  the server's validator message for an empty array is usually English.
- A money estimate shown before save ("deducted X, to deposit Y") reproduces the server's split rule
  exactly (closing-line remainder price, sub-unit excess folded into the deduction), is labelled an
  estimate, and EXCHANGE shows none. Reviewer proves parity by running the frontend function against
  the server's real util on many random cases and printing the count compared.
- Paid / credited / outstanding come from the server totals only: grep the frontend for
  `grandTotal - paid` (and local "sisa") on that document type, and for screens that subtract the
  credit themselves (recap create screens) now that the server figure is net.
- Every new server row or enum the credit adds needs a frontend label (statement row type, deposit
  entry type + its sign + "no money method", deposit source); a missing label renders the raw code.
  An open-documents table showing Total / Paid / Remaining needs a Credited column once credits
  exist, or Total - Paid != Remaining looks like a bug.
- Old stored snapshots built under the previous rule (a recap saved as total - credit) need their
  labels chosen from the stored figures, not the new rule's wording.
- Do not use the number input's own `max` for the creditable cap if the app's rule is "show over-limit
  in red, never clamp"; clamping hides the error and silently rewrites the quantity.
- A deep link from the source delivery to the credit form must look up the bill with a lookup the
  user is allowed to read (public/permission-free list, or ignore-forbidden); a protected list call
  bounces users without bill permission to the 403 page.

### Conflicts with an earlier payout design
- A credit model that reverses an earlier "refunds are paid in cash, not deducted" design conflicts
  with any cash-payout document built for the same rows: pays twice. Remove or rework the payout
  before deploy and say "do not deploy" until then.
- Removing a merged-but-undeployed money feature: keep an already-shipped global migration that ADDs
  enum values (PG cannot drop them; deleting the file drifts DBs that ran it), mark the TS members
  deprecated, delete the permission ROWS in a new migration; the tenant drop migration is idempotent
  (`IF EXISTS`), drops the FK first, and RAISEs while any ACTIVE payout row exists (dropping it would
  leave unexplained cash rows).
- Global migrations run before tenant ones. A global migration that deletes the feature's permission
  rows must itself refuse first, checking EVERY tenant schema (read them the way the tenant migrator
  does, e.g. from the tenant table; skip schemas without the table) and naming each schema with its
  count in one message. Otherwise the global step commits, the tenant check stops the upgrade, the old
  version restarted to void the payouts re-seeds the rows, and the global migration never runs again.
  Keep the tenant check as a backstop; test the preflight with two schemas holding ACTIVE rows.
- The removed feature is usually still announced in the "unreleased" sections of both changelogs and
  the in-app release notes. Rewrite those entries in the release-notes ticket (never shipped, net
  effect of create-then-drop migrations on a fresh deploy) so neither users nor deployers see it.
