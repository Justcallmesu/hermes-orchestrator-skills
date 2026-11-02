# Reversing documents in lot-replayed ledgers (reward points, expiring credits, batches)

These ledgers have no stored balance. The balance comes from replaying signed rows: positive rows
become lots with an expiry, and negative rows consume lots FIFO. When a document is voided, every
reversal row must be planned against the lots, or the replay sends it to the wrong place.

## Model the planner on these rules
1. **Make the replay deterministic: order by date, then createdAt, then id.** Rows written in one
   transaction share `createdAt` (the DB `now()` is the transaction start), so without the id
   tie-break every guard built on the replay gives random answers.
2. **Lots carry identity.** Each lot keeps the entry id and source (type and id) that created it,
   and the replay records which lots each negative row consumed (`{lotEntryId, amount, expiresAt}`).
3. **What the source earned:** take back only the part of its own lots that is still unspent and
   unexpired on the reversal date. A negative REVERSAL row consumes only lots of its own source,
   capped at what is left. It never touches other lots and never creates a shortfall.
4. **What the source spent:** give it back per consumed lot, keeping that lot's original expiry.
   Skip lots that have already expired.
   - Store `restoresEntryId` (a nullable self-FK, `ON DELETE SET NULL`) on the positive reversal
     row, and let the replay add the points back onto that original lot.
   - Without this, two linked documents both voided (A earned, B spent A's points) leave phantom
     points. Voiding B creates a new lot owned by B, then voiding A finds its own lot empty.
5. **Cap every restore at what the source still takes in the CURRENT replay.**
   - The plan is made at void time, but a back-dated row entered later reorders FIFO.
   - Restore onto the original lot only up to what the source took from that lot now. The part it
     took from other lots becomes a new lot. Drop anything it no longer takes at all.
   - Turning the excess into a plain lot gives back points the customer never had.
6. **Already-voided sources:** when planning a give-back, skip parts whose consumed lot belongs to a
   source that was already voided.
   - Detect "voided" by the source document's status as well as by existing reversal rows. A void
     whose earn was already fully spent writes no reversal row at all.
   - Inside the void transaction, the document's own status is still the old one, so it does not
     count itself.
7. **Reversal date = max(today, latest entry date of the source).** A reversal dated before a
   future-dated source row replays before the lot exists and takes nothing.
8. **Idempotency:** skip a source that already has any reversal row. Re-planning after posting is
   not idempotent by itself, so the guard depends on the source lock being held.

## Spend guard (redeem / use) under dated rows
- Do not check "balance as of the row's date". Replay the full history with and without the proposed
  row, and refuse only the shortfall the new row adds (on itself or on any later negative row).
  Leave out negative rows of already-reversed sources.
- Give the proposed row `createdAt` = far future (`new Date(8.64e15)`) so it sorts last within its
  day. The app clock and the DB `now()` differ, and a same-day tie can otherwise order differently
  from the stored row.
- A replay that clamps lots at 0 never produces a negative balance, so a `balance < 0` "already
  spent" guard is dead code. Whether a void is refused when its points are already spent is the
  user's call.

## Unit specs the pure util must carry
Use an `asOf` date. Cover each of these:
- expired unspent earn
- expired earn plus an unrelated live lot
- redeem taken from an expired lot
- redeem taken from a live lot (keeps its expiry)
- partly spent earn
- earn and redeem in the same document
- shuffled input order
- linked documents voided in both orders, and three-document chains in all void orders
- a back-dated earn and a back-dated redeem entered after a void
- a future-dated source voided today
- a voided future-dated spend that must not block today's spend

## Known residual
A part restored as a new lot carries the original lot's expiry, not the expiry of the lot the
source actually consumed after reordering. This only happens with back-dated rows. Prefer closing
the input freedom (see SKILL.md) over more replay logic.
