# "Show the latest reading" requests (latest HM / km / meter value on a form)

- First check whether ANY stored "latest" column exists (`grep -n` the entity; commented-out
  columns do not count). If not, list every table where a user enters that reading (daily report,
  work order, TSR, fuel filling, status transitions), with its field and its date column.
- Offer the source as a business choice: (A, usually recommended) derive it live as the newest
  reading across all sources, shown with date + source so the user can judge it; (B) a stored
  `lastX` column, which needs every writer plus edits/deletes to keep it right; (C) one source only.
  Ask separately: a value lower than the latest -> warn + confirm (meters get replaced) / reject /
  no check; prefill the field or show it as a hint only (a prefill gets saved without anyone reading
  the meter).
- When the user is confused because "many modules write HM", separate the two kinds in a table:
  a READING (meter value at a moment, typed by a person in each module) vs a TOTAL (hours summed by
  the system). Prove with a grep (`(Hm|KmHm)\s*(\+=|-=)|increment\(.*[Hh]m`) that no module
  increments a reading; only totals are summed, and those already have one recompute writer. Then
  the design is "record where it happens, read in one place": one read function returning value +
  time + source, no stored copy. Show a small ASCII mock of the form with the hint and the warning.
- Check entity identity on every source: a source that stores only the owner SLOT (contract
  vehicle) mis-attributes readings after a swap rewrites the slot's vehicle. Grep the swap method
  and the status/history entities for what is recorded (old unit, new unit, time). If nothing
  records which entity held the slot when, it is a business question (own decision id, own
  NEEDS-USER row) with options: (A) a small swap log written only by the swap method, old swaps stay
  as they are; (B) store the entity on every source row at save time + backfill (touches other
  modules); (C) ignore and accept the wrong hint. Tell the user the same slot-only join already
  mis-attributes the EXISTING reports that join through the slot (usage, uncountable, driver), so
  the fix is not only for the new hint.

## Building the live read (red-team items reviewers found)
- Date each reading by when it was TAKEN, never `updated_at`: status, pricing and QC saves bump
  it, so an old copied value (a work order's start HM copied from the TSR) becomes "newest".
  Read the row that holds the typed value (a submitted repair report) by its own date.
- A header column written as `x = payload.v ?? x` keeps an old value when nothing is typed, so it
  cannot say when or for which unit it was read; after a swap the new unit inherits it. Store each
  TYPED value as its own row (unit, value, read_at, transition) in the transition's transaction;
  no backfill, say older values stop counting.
- Count a report source only in the state the service itself copies forward (SUBMITTED), and
  confirm that state cannot be edited or deleted later.
- Day report rows hold the day's closing value but carry a time of day (one project stored `D 07:00`, not
  00:00; check real rows with `SELECT report_date, date_trunc('day', report_date)`): rank them at
  `date_trunc('day', x) + 1 day - 1 s`, never `x + ...`, and have the UI show only the date for
  those sources. Attribute a day reading to the holder at `date_trunc('day', x)` (start of the
  day) through ONE shared expression; test with fixtures stored the way production stores them
  plus a swap inside the offset window (03:00 swap, 07:00 row -> old unit).
- Convert timestamptz columns with `AT TIME ZONE '<app zone>'` so every compared time is one
  explicit type. Ignore null / `<= 0` (columns default to 0) and soft-deleted rows. One `UNION ALL`
  ordered by time desc, value desc, LIMIT 1.
- Swap log holder rule, one shared SQL helper reused by every report join and filter: latest swap
  at/before T -> its new unit; else earliest swap after T -> its old unit; else the slot's current
  unit. Prefilter to slots the unit was ever on before computing it. Test A->B->A, a swap-day
  reading, and a typed transition just after a swap.
- Moving a report's unit join from the slot to the holder changes the report's grain: a row
  grouped per slot becomes one row per (slot, unit) after a swap. Before shipping, grep each
  report for GROUP BY / per-slot columns: (a) a slot-level stored total (`slot.totalX`) now
  repeats on every unit row, so relabel it as the slot's total (or compute a per-unit total)
  — a business choice, ask with an example timeline (A 20 + B 30 = 50 on both rows); (b) the
  row must carry the unit id, and frontend row keys / Excel rows keyed on the slot id must
  become `slotId:unitId`, or swapped rows collide. The filter and the displayed-unit join must
  use the SAME holder expression, or rows filtered by unit A show unit B's label. Add the slot id
  and unit id as final ORDER BY tie-breakers: one unit can now sit on two rows that tie on every
  sort key, and paging repeats or skips them. Grep every OTHER report on the same detail table
  (operator lines, summaries) for the slot join too; a half-converted screen (totals by holder,
  lines by current unit) contradicts itself.
- New log tables that reference master rows: `onDelete: 'CASCADE'` unless the log must block
  deletes; NO ACTION breaks other specs' hard-delete cleanup (and the app's hard delete). Write the
  reason in the entity comment.
- Tests that swap through the real service get `swappedAt = now()`; pin it (update the log row to
  a fixed time between the fixture dates), or the suite fails once the calendar passes them.
- A field that can hold ANOTHER unit (one "KM/HM" input, with no meter type on the entity) is not
  a source of an HM reading: drop it from the read, and also every row that COPIED it (a record
  written at approval with the source's value and time). Detect a copy by matching value AND time
  against ANY source row of the same entity, not only the currently linked one: a copy can be
  relinked later and keeps the first source's values. Compare times truncated to milliseconds
  (`date_trunc('milliseconds', src.created_at)`): the copy went through a JS Date. Record the
  remaining unit leak (copied into other documents' HM and totals) as its own board row.
- A day reading on a SWAP day may carry the incoming unit's meter while the day-start holder rule
  gives it to the outgoing unit; when the user picks "skip it for the latest reading only", add a
  `NOT EXISTS` on the swap log with a range (`swapped_at >= d::date AND < d::date + 1`, index
  usable, soft-deleted swaps excluded) in the latest-reading query only, and leave every report on
  the holder rule. Test the soft-deleted swap and a swap on another slot that day.
- Retyping a reading column (integer -> double precision) under TypeORM `synchronize` DROPS and
  re-adds it (all values lost): ship an in-place `ALTER COLUMN ... TYPE` that runs before the new
  code boots, and prove on a throwaway DB that sync then sees no diff and values survive.
