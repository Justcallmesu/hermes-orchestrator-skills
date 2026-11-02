---
name: document-gate-placement
description: "Use when moving/explaining a business gate. Trace, options."
---

# Where a business gate belongs in a document chain

A gate = a hard check that blocks a document (credit limit, stock availability, approval, price
policy). Questions like "why is X checked at the order" or "move the check to the invoice" are
business rules: answer with verified current behaviour, then options for the user.

## Procedure
1. Find every caller of the gate (`grep -rn '<assertFn>' src`) and tabulate each document action
   (save draft, save confirmed, confirm, edit/reopen, cancel, system-generated runs) with
   check yes/no and `file:line`. Read the code comments around each call: they usually state the
   intent ("draft reserves nothing").
2. Read the DOWNSTREAM documents' create services in full before claiming how amounts relate
   (e.g. whether the invoice may change the order price or only discount it). A claim like "the
   order total is only an estimate" made without reading the invoice service is the usual error;
   if you made one, correct it plainly in the next answer.
3. Read the exposure/aggregate the gate compares against and check:
   - does it include the document being checked (double count on confirm/convert)?
   - does it include drafts or cancelled rows that commit nothing?
   - which rows leave the aggregate when the next document is created, and is that 1:1?
4. Check the bug audit / board for findings already logged on the gate, and whether they are in
   or out of the current branch's scope.
5. List paths that would hit a moved gate: edit of a re-opened document, scheduled/recurring
   generators (they fail the whole run and only log the error), POS or other entry points.

## Options to put to the user (recommended first, each with its consequence)
- Keep at the commitment point (order confirm) + fix the aggregate bugs.
- Move to the billing document (real amount, but stock is reserved/shipped before the block).
- Warn early, block late (most work, both repos).
- Remove (loses the legacy rule).
For a move, also ask: what remains at the origin (nothing / warning), whether open un-billed
orders still count (excluding the one being billed), which amount is checked (with shipping/fees?),
and whether failing scheduled runs is acceptable. Offer a one-line reply format ("1a 2a 3a").
If the work must land on its own branch while another run has the tree dirty, follow
`parallel-ticket-waves` §0 (worktree + overlap table).

## Placing a side effect (record, total, stock) on a quote → order chain
Same question shape as a gate: "when does X get recorded?"
1. Find the document that COMMITS the work: a quotation (TSR) only proposes; its approval generates
   the order (WO) in the same transaction. Recording at the quote counts rejected quotes and needs
   delete/cancel cleanup; recording at completion hides open work.
2. Recommend the commit point, but take the event TIME from the earliest document (quote created =
   when the problem was reported), so time waiting for approval still counts.
3. A "link the open record from the last N days" rule also needs an owner scope (same contract or
   parent): without it, a unit that changed owner inside the window attaches the old owner's record.
4. Replacing a guessed link with a stored id: keep the guess only for old unlinked rows, exclude
   targets already linked elsewhere, and enforce one-to-one with a partial unique index.

## Moving a field + its gate from the parent to the child document (after it shipped)
Typical ask: "remove payment type/tempo from the order, choose it on the invoice".
1. Ask in ONE clarify call: what stays at the parent (nothing / non-blocking warning / keep the
   block), how the child form fills the field (required no default / default from master data),
   what happens to the parent's columns already in production (keep unused / drop), and whether a
   value already stored on the parent seeds the child. Users often pick "warn, never block" for the
   parent; offer it explicitly.
2. Columns already deployed: keep them, no migration, mapped `select: false` so nothing reads,
   writes or returns them (no data loss, no deploy risk). Remove the fields from DTOs and every
   creator; with a whitelisting validation pipe, old clients that still send them are stripped,
   not refused.
3. A non-blocking parent warning needs no new endpoint when a status endpoint already exists
   (e.g. credit status): add an optional `excludeId` query so editing a document does not count
   itself, allow it for the parent's create permission, compute `exposure + form total > limit`
   in the form, stay silent on error/403, and never block submit. Word it so the user knows the
   limit applies only to the child's credit option.
4. The child: field required at the DTO when a user always creates it; automated creators
   (recurring runs, imports) derive it from master data through one shared helper. The child no
   longer writes back to the parent; keep the parent row lock + one-active-child re-check.
5. Tests that encode the removed parent block ("over the limit is rejected") are rewritten to the
   new rule (accepted, then cancelled so later figures stay the same), not deleted; every suite
   that creates the child must send the newly required field.
6. Say the risk: protection moves later (goods can ship before the child blocks), and what the
   user can do then (collect payment, raise the limit, bill as cash).
7. Write the change as a NEW spec whose decisions table names every earlier decision id it
   supersedes ("supersedes Q6/Q16"), so a reader of the old spec is not misled.
8. Form prefill from master data (customer tempo) must copy only COMPLETE values, with the same
   predicate the server uses (number > 0 and unit set): legacy imports leave 0 or a number without
   its unit, and a prefilled invalid value blocks the form's own validation while the server would
   have treated it as "none".
9. When the child picks a value per document, a concurrent second child of the same parent can pick
   a different one and skip the check: lock the parent row inside the create transaction and
   re-check "one active child" and the inputs there (see `postgres-concurrency-guards`); test it with
   two parallel requests and a mutation that removes the lock.
