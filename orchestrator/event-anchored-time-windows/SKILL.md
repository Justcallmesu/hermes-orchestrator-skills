---
name: event-anchored-time-windows
description: "Use for 'within N days of event X' rules. Bound both sides."
---

# Event-anchored time windows ("within N days after X")

For business rules like "a dead link can be taken over within 7 days after it died" or "a record
written up to 7 days before the TSR counts". Typical stack: NestJS + TypeORM + Postgres.

## 1. Design the window (before the brief)
1. Name the anchor event and the record being tested against it. Write the window as an explicit
   inequality with BOTH bounds: `event <= t <= event + N`. An upper bound alone also accepts records
   created before the event; a lower bound alone stays open forever.
2. Attack it: can the window never close? (anchoring on a time that is always just after the
   record, e.g. "N days from the dead TSR's createdAt", never closes for that record.) What happens
   at the exact boundary? Is the anchor terminal (can the event happen twice)?
3. If the answer changes business numbers (downtime, billing), it is the user's call: show a dated
   timeline example with the wrong number it produces, 2-3 options, recommendation first.
4. Keep explicit user actions (user picks the row on purpose) outside automatic windows unless the
   user says otherwise; record that as its own decision.

## 2. Source the event time
- Status transitions: the latest `status_history` row with that `new_status` for the entity. Grep
  every writer of the status and confirm each logs history in the same transaction (list file:line
  in the report). Fall back to the row's `updatedAt` for older data; on a terminal row updatedAt is
  the transition or later, so the fallback only widens the window. Never add logging silently to
  make the rule work.
- Compare like with like: know which columns are `timestamp` (session zone) and which are
  `timestamptz`; convert the timestamptz side with `AT TIME ZONE '<app zone>'`. A UNION mixing both
  types fails; an implicit cast hides a zone shift.
- Define the event-time expression ONCE as a const next to the condition that uses it; every reader
  (SQL branch, service check) uses that definition.

## 3. TypeORM raw-SQL fragment pitfalls
- `alias.property` inside a raw fragment is rewritten to the column only when followed by a space,
  `=`, `)` or `,` - not a newline or `::`. Build fragments on one line (`[...].join(' ')`), use
  `CAST(x AS text)` instead of `x::text`.
- One named parameter binds one Postgres type: reusing an enum-typed param against a varchar column
  fails (`varchar = <enum>`). Bind a separate param with a comment saying why.
- A bare param in arithmetic (`:p - ts`) has no inferable type: `CAST(:p AS timestamp)`. Writing
  `CAST(:t AS timestamp) - <event> BETWEEN make_interval() AND make_interval(days => :n)` evaluates
  the event expression once.

## 4. Tests
- Both sides of every bound: inside (T+3d), outside (T+10d), exact edge (T+N d taken, T+N d + 1 min
  not), before the event (T-1d not taken), and the fallback path (delete the history row, set
  `updated_at`).
- Create the anchor through the real transition (service call), then move times with direct DB
  updates: a repository `update` overwrites `@UpdateDateColumn`, so set `updated_at` with raw SQL;
  assert exactly one row moved. A negative case where the real transition bumps updatedAt past the
  window also proves the history row wins over the fallback.
- Adding a bound breaks older specs whose seeded event happened "now", after a backdated record:
  fix their seed order (event before the record), never their assertions; say so in the report.
- Pre-change check: remove only the new bound, the outside/before cases must fail; restore and `cmp`.
