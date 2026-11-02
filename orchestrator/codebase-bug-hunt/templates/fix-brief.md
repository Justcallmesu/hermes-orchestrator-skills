# <ID> — <short bug name> (audit #<n>[, #<m>])
Repo <S|W>. Decisions: <Q ids>.
Files: `<exact paths, exclusive to this ticket>`; new `test/api/<NN>-<run>-<topic>.mjs`.

Bug: <method (~line range)> <what it reads/checks and where (before/inside the transaction)>,
<what is never locked/passed>. <Concrete bad outcome: double posting, wrong total, 400 forever>.
Fix: <shape, e.g. inside the transaction lock the <doc> row (pessimistic_write, no joins), re-read
status + dependent data AFTER the lock, re-check, then set the changed columns on that re-read
instance and `save` it (not `manager.update`, which drops the record id from the audit log)>.
Reuse <existing helper>; keep lock order <spec Qx> (parent document row first, as the existing
create paths of this module lock it).
Non-goals: <sibling audit items deliberately left out>.
Acceptance (suite <NN>): (a) <race: N=5 rounds of 2 parallel requests -> exactly one 2xx, totals
correct>; (b) <guard: refused case -> 400>; (c) <normal path still works>; (d) <status change
still appears in the activity log of that record>. RED on HEAD for (a)/(b).
Also run <existing suites touching this area>; current fixture requirements the suites may miss:
<required fields added since the suites were written>.
Resources: build the HEAD and the fix backend one after the other, never more than 2 alive; kill
each when done.

## Common
Read first: shared worker-rules.md, spec.md (decision ids), the audit item text.
Report: docs/<run>/runs/<ID>/build-report.md (write it early).
Stop and ask if: a file outside the list is needed; an existing test's expected outcome must
change; the fix contradicts a documented client rule or spec decision; the lock order cannot be kept.
