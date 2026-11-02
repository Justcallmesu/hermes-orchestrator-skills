# Auditing which documents feed a balance (AR/AP, stock, credit exposure)

Use when the user asks "is X only counted when <document>?" across several modules (SO, PO, invoice, POS...).
The user often does not know the module list ("sales order, purchase order and etc"): enumerate it for them.

## Procedure
1. **Find the ledger owner, not the documents.** Grep class names for the concept and its local terms in one go:
   `class \w*(Receivable|Payable|Ledger|Deposit|Advance)\w*` plus `piutang|hutang` in comments/report text.
   The owner's `loadLedger`-style method is the single answer for "what creates a balance".
2. **Read the owner's source query in full**: which entity, which status filter (cancelled/void/draft), what is
   added to the total (shipping, tax), what is subtracted (payments only? returns? deposits?).
3. **Find plug-in sources.** Grep `registerSource`/`onModuleInit`/event subscribers: another module (e.g. POS)
   can inject documents into the ledger without the owner importing it. Missing these gives a wrong "only invoices".
4. **List every consumer** (`grep -rn '<owner>\.loadLedger\|<ownerService>'`): pages, dashboard, reports, statements.
   If they all read the same ledger, say so; a report that re-derives figures is a likely mismatch.
5. **Hunt side paths that count earlier documents without being the balance**: credit-limit exposure
   (un-invoiced orders, drafts), deposits/advances kept as a separate balance, refund returns recorded but not
   netted, expense/other payables living in their own table. Each goes in an "exceptions" list with `file:line`.
6. **Cite the gate that makes the trigger true**: the status check that forbids creating the invoice before
   delivery/receipt. That is what guarantees "only at invoice".
   A balance that is netted only on one printout (e.g. a recap PDF subtracts returns while the ledger,
   payment cap and invoice status do not) is an inconsistency, not a feature. Also check whether the same
   value is booked as a cash outflow in a cash-flow report: once it becomes a credit against the bill, that
   row is double counting.
   A recorded amount with no payment rows (a refund on a return) is often booked by reports as cash
   moved ON THE DOCUMENT DATE. Adding a payment/settlement for it raises two questions: are existing rows
   treated as already paid at deploy (recommended, or users pay them twice), and does the cash report move
   to the payment date (else double count). If the same amount can also be netted against a bill, a
   cash settlement must exclude what was netted.
   Red-team checklist for a new settlement document on an existing record (each item was a real miss):
   - A backfill flag set by a migration ("already paid") must also be set by every insert path that runs
     AFTER migrations: legacy port/rebuild scripts and importers write explicit column lists and get the DB default.
   - Revert/hard-delete paths (import revert, cleanup of cancelled rows) must refuse on ANY settlement history,
     voided included, with a clear message. Keep the FK RESTRICT; CASCADE silently deletes money history.
   - Helpers that copy link columns onto a reversal row (cash/Kas reversal) enumerate FKs by hand: add the new FK.
   - Cancel of the settled record must lock its row inside the transaction, re-read status, then check for
     live settlements; a status check outside the transaction lets a concurrent settlement slip in.
   - Settlement create re-reads status/type/amount from the LOCKED rows; lock by id alone (FOR UPDATE can't
     cross outer joins) and read the contact through the joins after the lock.
   - Copy contact-access checks from the side that has them all (list filter, detail, void); a sibling
     template may be missing some.
7. **Check in-flight branches/specs** (`docs/<feature>/spec.md`) that change a side path; state it is unmerged.

## Deliver
- One-line verdict ("Mostly yes: invoices + <extra source>; <side path> is the exception").
- One table per side (receivable / payable): document -> feeds balance? -> evidence.
- Numbered exceptions; then, if an exception is a business choice (net refunds? include expenses?), an options
  list with consequences and one question. Note the recorded decision it would overturn, if any.
