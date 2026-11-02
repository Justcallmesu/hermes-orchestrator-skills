# High-yield bug classes (name the relevant ones in each reviewer's context)

Each class below produced real, verified bugs in earlier audits. Paste the group that matches a
reviewer's area into its context; a named class gets traced, an unnamed one gets skimmed.

## Concurrency and status
- Confirm/cancel/edit/run-now that checks status via `findOne` BEFORE the transaction and never
  locks the row: a double click posts twice. Every new module repeats this.
- A lock fix applied to ONE action (cancel) while a sibling action on the same row (approve,
  verify-price, update-date, write-off) still reads before the transaction and `save()`s its stale
  copy, writing the old status back over the locked cancel. After any lock fix, grep every writer
  of that row.
- `save()` of a stale entity that carries a cascade relation (items with orphan delete) also
  reverts a concurrent edit of the lines.
- The purchase-side mirror of every sales-side fix (invoice cancel vs payment, order cancel vs
  receipt, return cancel twice): fix runs tend to harden one side only.
- Two paths taking the same two locks in opposite order (a global per-day number sequence row vs
  a customer row) deadlock under load.
- A status write via `manager.update` leaves the activity-log row without the record id.

## Money and totals
- A stored status computed from a total that is derived live from child documents (shipping
  summed from delivery notes) and recomputed only by payments: a child added after full payment
  leaves PAID + amount owed and hides the Pay action.
- A tender-like deduction (reward points, voucher) subtracted from the stored grand total while
  DPP/PPN/discount stay unchanged: every report row has Total != DPP + PPN. Ask the user whether it
  is a discount or a payment tender.
- A generated document (recurring run, import) built through a create() whose defaults differ from
  the template preview (PPN included vs on top, per-line vs per-unit discount): the preview and the
  generated document disagree silently.
- A default (`?? AMOUNT`) in a validation path that differs from the stored default (`?? PERCENT`).
- Sums that include VOID/cancelled documents; `paid >= total` compared on unrounded floats.
- An "as of date" report parameter that only picks the aging bucket while the ledger loader has no
  date filter: past-date reports include later documents and later payments.
- Money documents (deposits, POS) that never post to the cash/bank ledger while invoice payments
  do: ledger balance and cash-flow report disagree (business question, not a silent fix).
- A tax report that sums output-side and input-side base amounts in one column (DPP sales + DPP
  purchases), or that reads only invoices and skips refund returns (business question whether a
  return note reduces tax there).
- Opening-balance fields editable after movements exist; movements accepted before the account's
  opening date; a balance check that ignores dates (refund dated before the deposit).

## Stock, lots, units
- A return/reversal that converts units with the product's CURRENT conversion instead of the
  snapshot on the source line, while the product form still lets the conversion change.
- Repeated partial returns capped per lot only by the original outbound movement, ignoring earlier
  returns: lots get back more than was taken.
- A document approved/verified days later that posts stock on its request/creation date: a recount
  (REPLACE) in between absorbs the movement. Same for voids that delete an old movement dated
  before a later recount.
- A UI that prefills a date with today but sends it only "if changed from the prefill": the server
  keeps the stored date the user never saw.
- Negative-stock guards compared without a float tolerance (`balance < 0` after `qty * 0.1`) while
  the pre-check uses one: the exact remaining stock in a fractional unit is refused.
- A recount/target quantity validated with the same `min > 0` as add/remove: a count of 0 cannot be
  recorded.
- Same-day ordering by `created_at` (transaction START time) instead of posting order.
- Per-line caps checked line by line, so the same source line id sent twice bypasses them.
- Delete/revise that reverses stock twice or drops omitted lines; a delete that both posts a
  compensating document AND cascades the original.
- A lot-tracked outbound that consumes FEFO instead of the lot its source received into; a named
  lot that bypasses the expiry rule; a flag documented as immutable after history but only one of
  two flags is guarded.
- A snapshot column (unit conversion, unit cost) set on one document path but not its sibling (lot
  cost updated by price verification but not by the normal invoice form, nor on transferred copies);
  a form that shows cost per base unit while the server reads it per document unit.

## Imports
- CSV parsed client-side by a spreadsheet library without raw mode: locale numbers and dates are
  fuzzy-converted (`2,5` -> 25, `15.000` -> 15, dd/mm -> mm/dd) before the server's careful parser
  runs, and the preview says valid. Prove it by running the library on a sample line.
- One importer parsing dates with a bare `dayjs(text)` while the others use the shared strict
  reader (rollover `02-30` -> `03-02`, serials -> year 4629).
- Imported documents created with entity defaults instead of the normal posting path (a delivery
  left NOT_SHIPPED while stock was cut): lists, filters and void/revise guards treat it as open.
- No duplicate guard across import batches; revert blocked by FKs of dead (void/cancelled) rows the
  guard skipped; dry run passing rows the real run rejects.
- A migration backfill that ignores later documents of the rows it seeds; a counter re-key seeded
  only from rows still present (hard-deleted numbers get reissued: also seed from old counters,
  GREATEST, never lower).

## Platform and security
- Upload interceptors with no type/size filter, served statically from the API origin, while a JS-
  readable CSRF cookie lives on the same origin: an uploaded page acts as whoever opens it.
- A generic settings endpoint that writes any key, bypassing a stricter dedicated endpoint for the
  same key; enum-typed keys from user input producing a 500.
- Master-data push from a main tenant overwriting a field the branch is allowed to own.
- Access filters (own customers) applied on list but not on detail/PDF/delete/balance routes; a
  "keep selected ids" helper that re-queries and wipes access filters.
- A request-pinned DB connection released on `res 'close'` (fires on client abort).
- A cron that touches tenant tables before entering the tenant loop.

## Frontend
- Edit payloads using `value || undefined` with a server-side merge update: cleared fields keep
  the old value while a success toast shows.
- `toNumber(undefined)` sending 0 where the server fills a missing value.
- A table summary row laid out by column index while the table also has an expand (or selection)
  column: every total renders one column to the left. Check summary rows on tables with
  `expandable`/`rowSelection`.
- A void/cancel of a document from an already-closed period or shift: closed figures are recomputed
  live while the stored close snapshot is not, and the refund lands in no open drawer.
