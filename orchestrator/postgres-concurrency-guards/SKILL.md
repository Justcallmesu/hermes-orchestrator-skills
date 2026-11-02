---
name: postgres-concurrency-guards
description: "Use when guards or reads race on shared Postgres rows."
---

# Postgres concurrency guards (TypeORM / NestJS services)

For code where two flows touch the same rows: a guard that refuses an edit based on rows another
flow writes, a read that combines several values into what a user sees, or anything whose result
depends on row order. Project conventions (lock helpers, test DB setup) come from the repo's own
CLAUDE.md / PROJECT.md.

## Procedure
1. **Map the locks first.** For every flow that writes the rows your guard reads, write down the
   lock order it takes (header -> document -> lines ...), file:line. Your new lock must fit that
   global order on every path; if it would have to invert anywhere, stop and redesign.
2. **Guard = lock, then read.** A guard that reads rows another flow writes races unless both flows
   lock the SAME rows in the SAME order: lock them `pessimistic_write`, sorted by id, before the
   guard's read, reusing the other flow's lock helper or its exact row set. A plain read, even inside
   a transaction, does not wait for the other flow.
3. **One snapshot for one answer.** Several reads that together decide a shown/hidden value (a cost
   and its "under review" flag, a count and its page) run in one `REPEATABLE READ` read-only
   transaction, or are folded into one query (`EXISTS` subselect). Two independent reads let a
   concurrent correction commit between them and show a half-updated value as real.
4. **Never trust physical row order.** An UPDATE moves the row, so an unordered read that "always"
   returned insert order flips after an unrelated change. Sort explicitly (createdAt, then id) wherever
   order affects a result (line matching, generated documents, allocation).
5. **Prove it** (see below), then mutate the lock/snapshot/sort away and show the proof fails.

## Proof recipes
- **Race test, deterministic:** two real connections plus a third that holds a row lock to force the
  interleaving; assert the expected waiters in `pg_stat_activity` before releasing; run both orders
  (A locks first, B locks first) for >= 8 rounds; assert the end state is never inconsistent, one side
  wins with a clean 4xx, and no `40P01` deadlock.
- **Force "A holds the row, B arrives" over HTTP:** from a test pg client hold the LAST lock A
  takes (e.g. today's `document_sequence` row of A's number prefix, `FOR UPDATE`). A then parks while
  already holding the contested row. Poll `pg_stat_activity` until 1 lock-waiter, fire B, poll until
  2, then COMMIT the holder. Deterministic, no sleeps on the result; mutate B's lock away once to show
  it turns red (B succeeds too).
- **Deadlock repro across modules:** pause the other path while it holds its first lock, right
  before the write that closes the cycle, and make sure that write really happens with your data: an
  operation that leaves the row's values unchanged (e.g. a full receipt that leaves the totals
  unchanged) never writes it, so the test passes without proving anything. Show RED (`40P01`) with the old
  lock before GREEN with the new one, and comment in the test which ordering of the other path it
  depends on.
- **Snapshot test:** a spy on the first read commits a real correction on another connection before
  the second read runs; the old code shows the mixed state, the new code does not.
- **Ordering flake:** when a test flips order only in the full suite, run it isolated vs in the suite
  on HEAD and HEAD+change; look for an unordered read of rows something UPDATEs.
- **SQL actually sent:** turn on the query logger once and check the isolation / READ ONLY / lock
  clauses really appear in order.

## Pitfalls
- TypeORM `manager.transaction(isolation, ...)` on a manager already inside a transaction opens only
  a SAVEPOINT and silently ignores the isolation level. Call snapshot helpers on the default manager,
  or throw when `manager.queryRunner?.isTransactionActive`; the usual "accept an optional manager"
  convention does not apply to them.
- Lock a parent row BEFORE inserting children that reference it, never after. An FK insert takes
  `FOR KEY SHARE` on the parent; asking a stronger lock on that parent later is a lock upgrade, and it
  deadlocks against any other path that holds a lock on the parent and waits for your rows (e.g. a
  form save on the parent). Weakening the late lock to `FOR NO KEY UPDATE` only fixes the
  same-path-twice case, not the cross-path one. Take the parent locks (sorted by id, the weakest mode
  that still serializes the writers, usually `FOR NO KEY UPDATE`) at the top of the transaction. To
  prove it, race the path against every other path that locks the parent, not only against itself.
- The reverse case: YOUR new path locks a shared row (a cash register, an account) that OTHER paths
  touch only through an FK insert (a payment row referencing it), and those paths lock something
  your path locks earlier (the customer). `FOR UPDATE` conflicts with their implicit `FOR KEY SHARE`,
  so the orders invert (theirs: row -> customer, yours: customer -> row) and they deadlock. Lock the
  row `FOR NO KEY UPDATE` instead: it does not conflict with `KEY SHARE`, yet still serializes
  against the real writers (close, cash-out) that take `FOR UPDATE`/`NO KEY UPDATE`. Before choosing
  a lock mode, grep which tables hold FKs to the row and which paths insert into them. Fixing one
  lock-order bug by adding a new early lock (customer first) is exactly how this inversion appears:
  in review, list every path that inserts rows referencing each row the fix locks later, and race
  the fix against the one that locks the earlier row AFTER its insert (deposit settlement vs void).
- Do not take a batch of locks "up front" in one path (e.g. all stock locks before allocating a
  document number) when every other writer takes the number/sequence lock first and the per-line
  locks after: the batch inverts the order and deadlocks under mixed load. Take each lock where the
  other writers take it (document row -> number/sequence -> per-line locks). Prove it by racing the
  path against a DIFFERENT writer of the same rows (approve vs stock-out), never only against itself.
- Adding an early-in-order lock (a number/sequence counter) to a CENTRAL helper (a stock-reversal
  used by every cancel) changes the order for every caller: a caller that, after the helper, locks
  rows another path takes BEFORE that counter (bad-stock entries locked by scrap confirm, then the
  counter) now closes a cycle. Before shipping, list for each caller the rows it locks after the
  call; fix the order in the caller (take those rows sorted before calling the helper, the order its
  create path already uses), not by dropping the helper's lock. Brief the builder to probe each such
  neighbour path with a mixed race and STOP when one deadlocks, since its own new race test will
  not show it.
- To serialize a config edit against postings that READ the config (a unit conversion vs stock
  postings), lock the PARENT row: the edit takes `FOR UPDATE` on it first, each posting takes
  `FOR KEY SHARE` on it (plus `FOR SHARE` on the child rows it reads) before reading. Child-row locks
  alone cannot stop an edit that re-adds a child as a NEW row no posting has locked. `KEY SHARE` does
  not block FK inserts or ordinary `NO KEY UPDATE` writers (price edits, archive), only the edit;
  say in the docs that an edit now waits for open postings of that parent (no lock timeout).
- A race test of a path against itself proves nothing when an earlier shared lock (a document-number
  sequence) already serializes the calls: it passes on HEAD too. Run the race test on HEAD first; if
  it is green there, race against a different writer or hold the earlier lock from another connection.
- Lazy creation of a shared row with no unique index (e.g. a per-parent account or code row created
  on first use) needs a lock on the parent row, then a re-read, then create. A race test whose two
  transactions already queue on some earlier lock (a sequence row) never reaches the create step and
  proves nothing; hold the parent lock from a third connection to force the race.
- A generic `save(merge(entity, dto))` on update rewrites every column, including links that other
  flows set (a system-created account id), so an overlapping form save writes the stale value back.
  Write only the columns the form owns and test it with a concurrent writer. Prefer setting those
  fields on the LOCKED instance and `save`-ing it over `manager.update(Entity, id, fields)`: the
  query-builder update skips entity subscribers' entity data, so audit/activity logs record the change
  with an empty entity id and it drops out of the record's history. If `update()` is unavoidable,
  check the audit row in the test. This applies equally to race fixes: "write only the changed
  columns" after a lock means assign them on the re-read instance and `save`, not `update()`; a race
  test passes either way, so add an activity-log assertion for status changes.
- Reuse-or-create lookups ("is this row already owned by someone else?") must include soft-deleted
  owners (`withDeleted: true`). Otherwise a deleted owner's row looks free and gets reused, which
  merges two owners' history. Ship a test for the soft-deleted case, because no other test notices
  when that flag is removed.
- Any lock order that relies on id sort order (a parent account sorted before its children) breaks
  for rows with imported or pre-uuidv7 ids. Prove the order with a probe that uses reversed ids, and
  either have the deploy rehearsal count such rows or add a deadlock retry on the losing path.
- To make two paths take turns on a shared document (e.g. two kinds of return on one PO), don't add a
  row lock on that document to a path that never locked it: unrelated modules already lock that row
  in their own order (one holds a sequence row and then updates the document), and the new lock
  closes a cycle with them. Use a transaction-scoped advisory lock on a namespaced key
  (`pg_advisory_xact_lock(hashtext('<purpose>:<id>'))`), taken only by the paths that must serialize.
  Nothing else touches that key, so it cannot join another lock graph. When one transaction takes
  several keys, sort and de-duplicate them by the **hash value**, not by id: two ids can collide on the
  32-bit hash, and id order then inverts the lock order between two transactions and deadlocks. Reuse
  the repo's existing advisory-lock pattern if it has one, and race the change against the unrelated
  path that locks the row.
- A mutual-exclusion check ("refuse kind B while a kind-A record exists on this document") must find
  the other records through the relation that cannot change (their lines -> the document, or their
  stored target id), resolved by the same resolver the current record uses. Never pre-filter by a
  mutable attribute of the document (its current owner/supplier): editing that attribute lets the
  forbidden pair through.
- Count a blocking record only while it can still move money or stock: exclude states that can never
  complete (approved, but its outbound was denied and cannot be re-sent or rejected). Counting them
  creates permanent dead ends (goods in stock, no document possible). Read the status machine (who can
  leave each state) before writing the rule, use one shared condition for the block check AND the
  quantity headroom, and make the error text name the blocking record and a next step that actually
  works in its state. Before shipping, grep every OTHER module that counts the same records (a
  "has a return" skip, a "cannot change supplier" guard): a reader left on the old status filter
  keeps blocking on records the new rule calls dead. When the module dependency direction forbids
  importing the rule (the owner imports the reader's module), move the condition to a shared commons
  util that both use, rather than copying it.
- Filter the blocking query to the document in SQL, not in application code after the fetch: it runs
  under the serializing lock, and fetching every live record of the other kind turns a cheap check
  into a table-wide scan held under the lock.
- Run a serializing check before the expensive work in that path (e.g. before cancelling the
  document), so a transaction waiting on the key holds as few row locks as possible.
- TypeORM `findOne({ lock: { mode: 'pessimistic_write' }, relations: [...] })` fails on Postgres when
  a relation becomes an outer join (`FOR UPDATE cannot be applied to the nullable side`). Lock the row
  alone, then load its lines/relations in a second query on the same manager, and run every status
  or total check after both.
- A check that reads totals before `manager.transaction(...)` ("already delivered", "invoice exists")
  is not guarded by a lock taken inside it: move the read inside, after the lock, through the
  transaction's manager, and build any line map the write uses from rows re-read after the lock.
  The re-check must re-validate the pre-check's WHOLE premise, not only the flag the ticket added:
  compare the locked row's status with the status the request was validated against (refuse 409
  "status already changed, reload" when they differ) and re-run every count the pre-check ran.
  A re-check of one new column leaves the double-click hole open: two identical cancels both pass
  (a same-status move skips transition guards) and the side effect (a reservation release) runs
  twice.
- Adding `FOR UPDATE` on a parent at the top of a status change is a new lock order for every hook
  that runs after it. Grep the hooks the change calls (cancel/reject hooks into other modules) and
  the other modules' writers of those child rows: a writer that locks the child first and then
  saves the parent (a fulfilment recompute after a receipt) inverts the order and deadlocks (a 500
  where the user used to get a clean 409). Lock the children (sorted by id) BEFORE the parent in the
  status path, only for moves that run the hooks, and race the status change against each child
  writer (receive, cancel) in both orders.
- A child document that lets the request fill a value missing on its parent (e.g. invoice picks the
  payment type for a legacy order with NULL, then writes it back to the order) must resolve that
  value from the parent row re-read UNDER the lock, and derive every dependent rule (due date, credit
  check) from the resolved value. Resolving it from the pre-lock copy lets two concurrent children
  pick different values, and the one that skipped a check (cash -> no credit check) still commits.
  Write back only `WHERE value IS NULL`, in the same transaction, after the checks.
- A row lock protects only against writers that take it too. When you lock a document in one
  action (cancel), grep EVERY other method that writes that row (approve, verify, date/reference
  edits, crons) and give each the same lock-then-re-read: an unlocked sibling that `save()`s the
  copy it read before the transaction writes the old status back after the locked action commits,
  undoing it (a cancelled order returns to CONFIRMED). Race the fixed action against each sibling,
  not only against itself.
- After locking a row and re-checking it, apply the edit to the LOCKED instance and save that one.
  Saving the copy loaded before the lock writes stale columns back over a concurrent change, and
  the re-check passes while protecting nothing. Look for two variables of the same entity in the
  method during review.
- Before adding a lock (row or advisory) to a shared service method, grep its callers for ones that
  compose several services inside ONE outer transaction (scheduled/recurring generators, imports,
  "create SO -> DO -> invoice" chains). Nested `transaction()` calls are savepoints, so the new lock
  stays held until the outer commit, while the later steps take the number/sequence lock: that
  inverts the global order for that caller only. Keep the outer atomicity; fix the order in the
  composing caller, and race it against a normal stock writer to prove it.
- A helper that takes a row lock must run in the CALLER's transaction. Check every caller passes a
  manager: a controller that calls the service with none makes it fall back to `repository.manager`,
  where a pessimistic lock throws (`PessimisticLockTransactionRequiredError`) or the write has
  nothing to roll back with. Wrap the whole action (status change + side effects + recompute) in one
  transaction first, and test that a failure in the last step rolls back the first.
- While holding a row lock, never call a collaborator that opens its OWN transaction and writes the
  same row (a status promotion called without the manager). The second connection waits on the
  first and the first waits on the call; Postgres cannot see that as a deadlock, so the request
  hangs until timeout. Pass the manager down or take the lock after that call, and cover the path
  with a jest timeout.
- `READ COMMITTED` inside one transaction is not a snapshot: each statement sees new commits.
- Postgres raises no serialization errors on a read-only `REPEATABLE READ` transaction, so read
  snapshots need no retry loop; write transactions at that level do.
- Running a cheap check before taking locks changes which error a user sees when two problems
  coincide, and is safe only if the value cannot change before the locked write. Say so in the review.
- A guard bound to a link state ("refuse cancelling child C while it is linked to live parent P")
  must be paired with the path that ENDS that state. When P is cancelled, either reset the link
  (release C so the next P re-links it under the same parent lock) or the guard's precondition stops
  matching and the hole it closed reopens on the next P. Test the full sequence: link -> cancel P ->
  new P -> the guard fires again.
- Read a link that another path sets under parent lock X only AFTER taking X: an id read before the
  lock misses a link committed while you waited, and the guard then checks the wrong (or no) parent.
- A guard's state predicate ("header-only link with zero amounts") must match only the population
  the reason applies to. Filter by the attribute the reason depends on (refund vs exchange) or the
  refusal becomes a permanent dead end for rows the rule never meant to block.
- A bulk delete/revert that removes child documents before their parent (invoices, then orders)
  deadlocks with any writer that locks parent -> child. Lock the parent rows (sorted by id,
  `FOR UPDATE`) right after the batch lock, before the first read or delete. Adding a parent-first
  lock to one writer is exactly what exposes this pair, so race the reverter against that writer.
