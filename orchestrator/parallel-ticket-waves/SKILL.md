---
name: parallel-ticket-waves
description: "Use when parallel workers share a tree. Gate, commit each."
---

# Parallel ticket waves in one working tree

Use when a PM dispatches 2+ worker agents at once into the SAME repo checkout and each ticket must
land as its own green commit. Complements `thin-orchestrator` (per-ticket loop) and
`orchestration-run-hygiene` (cross-ticket hygiene).

## 0. Side work while a wave's edits are uncommitted
- A new request on its own branch (merge to main separately) must never run in the wave's checkout:
  switching branches carries or refuses the uncommitted edits, and stash/reset is forbidden. Use
  `git worktree add <proj>/wt/<branch> -b <branch> main` per repo touched, and brief its workers with
  that path only.
- Before dispatch, map overlap: list the files the side work edits against every board ticket's file
  list (including unstarted waves) and show it to the user as a table. Overlap = a planned merge
  conflict; say which branch merges second and resolves it, and require a review of the merged
  function (not only the conflict hunks) when both branches change the same function.
- Push/merge rules and the commit author can differ between the wave's run rules and the repo's docs;
  ask which apply to the side branch (author included) and record the answer in its decision row.
  An author named in repo docs (CLAUDE.md "author X") or dominating `git log` is not confirmation
  that the person you work with is X: confirm before the first commit. On a correction of unpushed
  commits, re-author them (`commit --amend --reset-author` with `-c user.name/-c user.email`, move
  the branch refs), fix the docs line, and set the identity with `git config --local` per repo
  (worktrees share it), never `--global`.
- The side branch's gate compares the change against unmodified `main` on two backends side by side
  (own fresh DBs): the new suite must be red on main and green with the change, and every existing
  suite it touches must match line for line.
- "Do this small change directly on `main`" while the run branch edits the same files: you can, but
  first name the overlapping files (`file:line` on both sides) and ask, as options: on `main` (ships
  alone, but a planned conflict when the run branch merges) vs on the run branch (no conflict, ships
  with the run). If `main`, recommend releasing it, then merging `main` back into the run branch
  right away (section 4b), so the conflict is resolved while both changes are fresh. Use a worktree
  for `main`; never switch the run checkout.
- Check `delegate_task action=list` first: no live workers means the dirty tree is parked work, not
  in-flight edits, but it is still off-limits.
- A fresh worktree has no `node_modules`: symlink the main checkout's (`ln -s <repo>/node_modules
  <wt>/node_modules`) inside the same script that creates the worktree.
- Remove a PM worktree that holds a branch the user works on (`main` above all) as soon as its
  commits land: git refuses `checkout <branch>` in any other checkout while a worktree holds it
  ("already used by worktree"). Release it from a script: assert the worktree is clean, `rm` the
  `node_modules` SYMLINK first (never let a recursive delete follow it into the real repo),
  `git worktree remove`, `git worktree prune`, then print `git worktree list` and confirm the real
  `node_modules` still exists. Leave worktrees you did not create alone. Prefer a detached worktree
  (`git worktree add --detach <wt> main`, commit, then `git branch -f main <sha>` from the real
  checkout) when the user may want the branch while you work.
- The wave's scratch runner (`git archive HEAD` of the main checkout + listed files) is wrong for side
  work: it exports the other branch. Give the side branch its own runner that `rsync`s the worktree as
  it is on disk (excluding node_modules/dist/.env/.git) into a scratch copy, its own DB-name prefix
  and port range on the same throwaway cluster, and `FRESH=1` whenever a migration file changes.
- Re-check the base branch's HEAD right before creating the worktree: if it moved since discovery
  (a merge landed), `git diff --stat <old-sha>..<new-sha> -- <every path the spec cites>`. Empty =
  citations still hold (say so in the spec); otherwise re-verify the cited lines before briefing.
- A clean side-branch worktree can host the next side feature: `git switch -c <new> main` in it
  (assert clean first) instead of adding another worktree.
- When the PM baseline copies the same worktree the workers will edit (rsync at start), dispatch in
  parallel but give each brief a "wait first" step: no edit until the baseline copy's `src` exists.
  Otherwise the baseline silently includes half-made edits.
- Record the side branch's baseline on clean `main` before dispatch with the suites its tickets touch,
  and add any suite a worker later reports failing: a suite missing from the baseline turns every
  failure in it into an unanswerable "is this ours?" question.
- Mirrored features (the same document for customers and suppliers): build ONE server side first as
  the template, commit it, then brief the other side as "mirror the committed sha, these are the
  differences" (contact join, payment enum, ledger posting or not, access helper names), letting it
  extract shared pure code only if the first side's suite still passes unchanged. On the webapp give
  both kinds to ONE ticket as one view set switched by a `kind` config, when an existing pair already
  works that way: two webapp tickets would fight over the same menu/route/enum files.
- Server and webapp tickets of a side feature can run in parallel when the server brief fixes the
  exact API contract (field names, enum values, which endpoint the form reads); the webapp brief
  codes against that contract and lists the browser behaviour as NOT verified until the server lands.
  When the server side lands, grep its DTO/service for each field the webapp config assumed (ids
  array, allocation relation name, preview id) before the webapp review, and log the match.
- Webapp briefs that add a deep-link button into a contact-scoped create flow ("Bayar Refund" from a
  return detail) must say what a contact-restricted user sees: the source page's list/detail is often
  unscoped while the target endpoint asserts contact access, and the shared GET hook turns that 403
  into a full-page /403 redirect. Brief the hook's no-redirect option plus an inline Alert, and have
  the server return the contact on the source detail so the webapp needs no extra lookup query.

- "Do all tickets, I'll check at the end": record the grant in `decisions.md`, run the tickets back
  to back with no commit stops. Tickets stack uncommitted in one tree, so each brief lists earlier
  tickets' files as "not yours" (allowing only a named minimal addition when reuse demands it, e.g.
  one public method on the earlier ticket's service instead of duplicating its query), and each build
  report keeps its own exact file list. Per-ticket commits survive only while no later ticket edits an
  earlier ticket's file: once one does (shared service, detail page, helper), the earlier file list
  no longer describes a clean commit. Check the overlap before handing out per-ticket commit
  commands, and if any file is shared, give one commit per repo (or ask to commit each ticket as it
  turns DONE) and say why; never re-issue an earlier per-ticket command unchecked. Still stop for business
  rules and retry caps. PM technical calls taken on the way (e.g. which create paths a new required
  field exempts) get a spec decision id marked "pending user check" and are listed in the final
  report.
- A user-reported bug arriving mid-run: probe it first (scripted API probe on a develop backend,
  read-only DB query), then add it to the run as its own spec decision row and ticket instead of a
  side fix. If it needs a file an uncommitted ticket owns, mark it "waits <owner> commit", dispatch it
  right after that commit, and scope the brief to named lines of the shared file ("findAll filter
  only", "create return only"), so its commit stays separable.
- A new FEATURE request mid-run that reverses an earlier recorded decision ("add back the field
  you removed, but only for X"): grep the feature's spec and `git log --grep` for the removal
  before answering, and quote the decision rows it partly supersedes. Then ask in ONE clarify call:
  which part comes back (name each removed piece as an option, including any whose data was
  dropped), which branch (the run branch as an extra ticket vs a separate feature branch after the
  run merges), and the shape questions (can the later step still change it, field form). Check
  whether the server already accepts the value for system paths; if so the work is mostly
  frontend, but mark that ASSUMED until a test proves it. Write the spec in its own docs folder with
  its own decision ids naming what they supersede, log a pointer line on the run board, and build
  nothing in the run checkout.
- A fix that changes what an existing API field MEANS (a GET returning a cost per purchase unit
  instead of per base unit): brief the reviewer to find every reader of that field (detail pages,
  PDFs, reports, exports, prefills of other forms) and to treat any reader expecting the old
  meaning as a major.
- Edit endpoints that convert a displayed value back to a stored one (per purchase unit shown,
  per base unit stored, rounded for display): brief "changed" as "differs from the exact value the
  form showed for this line, computed the same way (posted conversion, same rounding), or omitted"
  -- never "re-derived value differs from the stored one". Otherwise a no-change save refuses or
  silently rewrites the value whenever the stored one is not exactly the derivation (null/legacy
  rows, more decimals than displayed, set by another path, API callers omitting the field). Put
  those three cases in the acceptance tests up front.
- A ticket that adds a relation to a detail/read response ("load the customer and vehicle for the
  print"): brief the exact fields the consumer needs and a test that a sensitive column is ABSENT.
  A whole-entity relation load ships cost and accounting columns (purchase price, ledger account,
  id numbers) to everyone holding the endpoint's read permission, and the existing price redaction
  never covers the embedded parent's own money fields. A ticket that ADDS redaction to another
  read path (a vendor job embedding job lines) extracts the existing field list into one shared
  helper both paths call (never a second copy), applies it to the response object only (never to
  an entity that is saved later), and its review greps every endpoint that embeds the entity.
  A leak fix on ONE entry of a shared polymorphic/relation map (the WORK_ORDER entry of a location
  map) covers the sibling entries in the same brief (CONTRACT, WAREHOUSE: list their money/tax
  columns), and narrows the shared TS type too, so a later money read fails to compile instead
  of silently getting `undefined`. Fixing one entry leaves the next leak for the review to find.
- A builder reporting that the brief and the spec disagree: re-read both, decide which is right the
  same turn, fix the spec text in place (not an appended note) and log the correction in
  `decisions.md`, separating the user's decision from the PM's technical call. A stale spec line
  misleads every later brief and the final report.

## 1. Split
- **Memory cap first.** Each worker that builds a scratch copy, starts a backend and runs tsc holds
  ~1 GB, and the workers live inside the agent app's process tree: too many at once gets the whole
  app OOM-killed, taking every worker and the PM turn with it. Run at most 3 building workers in
  parallel (check `free -g` first) and brief them to build their HEAD and fix backends one after the
  other, killing each when done. Read-only reviewers told "no build, no backend" cost little and can
  run beside them. Recovery: section 2b.
- **API rate cap second.** Long-running subagents share one account rate limit: keep at most 3
  builders + 1 reviewer alive at once, and fewer after any 429. A 429 that exhausts retries can kill
  one worker or every sibling of the fan-out, and the stated reset can be hours away. Every brief
  therefore says "save progress to the build report as you go". While waiting, write the next
  wave's briefs; a reviewer that completes many calls without a 429 meanwhile shows the limit has
  cleared, so dispatch then instead of idling to the stated reset time.
  Prefer dispatching reviews of finished tickets over starting another builder when near the cap.
- A run built FROM the backlog (user picks groups of rows): first dispatch at most 2 read-only
  discovery workers split by theme (locks vs data/access/UI), each writing one file incrementally
  with, per row: VERIFIED current behaviour (`file:line`, or "already fixed"), the concrete failure,
  minimal fix + helper to reuse, affected callers and their lock orders, how a test proves RED,
  business QUESTIONs, size, and a proposed ticket grouping with file overlap. Start the baseline
  gate on the fresh branch at the same time. Cut tickets only from those reports, asking the
  QUESTIONs first; backlog rows written weeks ago are leads, not specs.
- Backlog ids: assign a new id only when appending its row, after reading the board's current max id
  by script. A log line that names an id before the row exists later collides with another row;
  on a collision, renumber to fresh ids and note the old reference in the row.
- Group backlog rows into tickets by the files they touch; each ticket gets a disjoint file list in
  its brief. Money/locking tickets get a red-team; the rest a normal review.
- Briefs written before you decide to run two tickets side by side lack that list. Before dispatching
  the pair, pull every path each brief names (`grep -o '`[^`]*\.\(ts\|mjs\|md\)`' <brief>`), confirm
  the sets are disjoint, and add a "Files (only these; anything else -> STOP)" section to each brief
  that also names the OTHER worker's files as do-not-touch, including shared test suites and docs
  either ticket would otherwise update (a report ticket rewriting suite assertions vs a guard ticket
  adding cases to the same suite). Also expand every folder glob one brief owns
  (`work-order/services/**`) and grep the other briefs' item text, not only their file lists, for
  paths under it: an item body that says "fix the comment in <file>" collides with a sibling that
  owns that folder even when the file lists look disjoint. Move the item to the folder's owner.
- Write one shared rules file every brief points to: own scratch DB name per worker, "touch only your
  listed files; never revert, format or fix another's", STOP if a file outside the list is needed or
  an existing test's expected outcome must change. When the baseline shows suites red because the
  API recently made a field required or changed a route (a payment type on invoice create, a reason
  on cancel, a removed DELETE route), list those current payload rules in the rules file: new
  suites copy fixtures from old suites and otherwise fail setup for a reason unrelated to the ticket.
- Tickets stacked uncommitted in one worktree (S2 builds on S1's diff): a `HEAD + listed files`
  scratch runner only sees the earlier tickets if the brief says "pass EVERY file from
  `git status --porcelain` plus yours". The RED copy for the new ticket (HEAD + earlier tickets,
  without this one) must be built BEFORE the worker's first edit; afterwards the worktree no
  longer holds that state. Put "build the RED copy first" as step 0 of the brief.
- Review findings that assert behaviour outside the diff ("existing tenants need a manual seed",
  "this runs only on deploy") are claims: check the code path before routing them. A wrong one
  closes as a board row with the `file:line` that disproves it, and gets struck from any proposed
  doc/CLAUDE.md text a later worker copied it into.
- Brief every NEW HTTP suite to find its fixtures by `search=<name>` (or a sort that puts the wanted
  row first), never `.find()` on the first page of a list: the full gate runs every suite on one DB,
  and by the late suites hundreds of products/warehouses exist, so a first-page lookup returns
  undefined and the suite crashes before its first check. "Newest row" lookups (`?limit=1` before and
  after a create) are first-page lookups too: list endpoints sort by DOCUMENT date, and other suites
  leave future-dated rows on top, so find the created row by its returned id, a unique tag via
  `search=`, or `createdAt` order. It must also CREATE the rows whose state
  it consumes (its own tagged product + its own stock, customer, Kas), never sell from a shared seed
  product: earlier suites oversell those far below zero, so the late suite's sales order gets
  "stock tidak cukup" mid-run. Its verify step runs the suite once on a DB that earlier suites
  already used (or pre-filled with 300+ rows), not only on a fresh one.
- Cross-cutting seed files every feature of a batch touches (permission payloads + their backend
  and frontend enums, role grants): cut ONE wave-1 ticket that adds ALL the batch's new entries up
  front, and make every feature ticket depend on it and only USE them. Otherwise each parallel
  builder appends to the same payload/enum files and the per-ticket commits cannot be split.
  Likewise, when two planned tickets edit the same service file, merge them into one build run
  (mark the absorbed row "MERGED INTO <id>" on the board) instead of serialising them.
- A stock/money feature split into an "approve" ticket and a "downstream readers" ticket (approved
  qty written at approve; receive/shipment still read the requested qty): the branch is NOT
  mergeable between the two commits, because the half-built state moves the wrong quantity. Write
  "<downstream id> must land before merge" on the board when cutting them and in the report after
  the first commits; brief the first ticket to list every reader of the old field for the second.
- Write the wave plan as one line on the board under the ticket table (W1 = ..., W2 = ... (needs
  X), ...), so a resumed session knows what to dispatch next without re-deriving dependencies.
- A ticket that adds values to a server enum lists every frontend map keyed on that enum
  (`Record<...Type, label>`, union types, filter options, colour maps) in its brief, even when
  another ticket owns that file: otherwise the new rows render with a blank label and nobody owns
  the fix. Two tickets running at once that both need one enum file: let the second only ADD
  members (re-read the file right before editing), gate the two together, and commit the file with
  the first one, saying so in the message.
- Two builders may run at once on ONE source file only when they edit different named methods
  (one lock fix, one validation fix). Brief both: name the other's method as untouchable, patch
  locally (never rewrite the file), re-read the file right before each edit, and expect the scratch
  copy to carry the other's half-done edit (wait and retry a failing typecheck before reporting).
  Gate them together. At commit, split the file by hunk: `git diff -U3 <f>` to a patch, cut it
  into header (4 lines) + each ticket's `@@` hunks, assert each part contains its own method name
  and not the other's, `git apply --cached --recount <part>` and commit with the first ticket, then
  `git add <f>` for the rest with the second. Record which hunk belongs to which ticket on the
  board when they are dispatched, so the split needs no re-reading of both diffs. A builder that stops because its fix needs a file
  outside its list (a caller whose lock order the fix breaks): decide it the same turn as a PM
  technical call when it stays inside the approved group, record it, and dispatch the fix-up with
  the extra file named plus a race case that must fail with the original fix alone.
- A helper that 2+ tickets need (e.g. a dedupe assert, a lock util) is OWNED by one ticket. Write its
  exact name, path, signature and body into a shared contract file before dispatch. The owner creates
  it as its first step; the others only import it and add its path to their scratch-copy file list.
  Without this, parallel workers each create their own copy of the same helper.
- For HTTP baselines without a usable dev DB, start a throwaway Postgres cluster (own data dir, own
  port, socket in scratch) and give each worker its own database on it, never the user's DBs.
- Workers run mutations and probes in a scratch copy (`git archive HEAD backend | tar -x` + their own
  files + the shared helpers they import), never in the shared tree, so no other worker ever reads a
  mutated file and another worker's half-edit never breaks their compile.
- Name the PM's baseline backend/DB (port, DB name) as FORBIDDEN in the shared rules file. Workers
  proving "fails on HEAD" otherwise reuse the running baseline and write test rows into it, which
  makes every later comparison on it untrustworthy; they must build their own HEAD copy instead.
- In locking briefs, tell the worker to set the changed fields on the row RE-READ after the lock and
  `save` it; never write "use `manager.update` instead of saving the stale entity". `update()` skips
  the entity data audit subscribers need, so status changes land in the activity log with no record
  id (see `postgres-concurrency-guards`). Have reviewers grep the diff for new `manager.update(` on
  audited entities.
- When 2+ tickets add locks (row locks, advisory stock locks), write ONE global lock order into the
  shared contract. Name the parent document for each child (purchase order before goods receipt,
  sales order before delivery), read from how the existing create paths already lock: a brief that
  orders a new path against them forces the worker to overrule it. Include the lock taken by
  document-number allocation (e.g. a
  `document_sequence` row lock held to commit): document row -> number allocation -> stock locks.
  A worker that locks stock "up front" before asking for a number deadlocks against every other
  writer, and single-operation race tests never show it. A ticket that adds a NEW lock to an
  EXISTING path (a status change now locking the parent `FOR UPDATE`) must list every hook that path
  runs after the lock (cancel hooks into other modules) and the lock order of THOSE modules' own
  writers (child row first, then a parent write): taking the parent before the hook's children
  inverts their order and turns a clean 409 into a deadlock 500. Brief: lock the hook's rows before
  the parent, then re-check status AND the child counts under the lock. Every locking ticket's review runs one
 MIXED probe (N of this operation in parallel with N of another stock writer on the same
 product) and greps the backend log for `deadlock detected`. Brief the reviewer to also check
 implicit FK locks: a row the new path locks `FOR UPDATE` that other paths reference by inserting
 child rows (payments -> register) conflicts with their `KEY SHARE` and inverts the order; the
 mixed probe must include such an inserting path (see `postgres-concurrency-guards`).
- Grep for callers that wrap the changed service in an OUTER transaction (scheduled/recurring jobs,
  imports, "generate X from Y"): transaction-scoped locks taken inside stay held until the outer
  commit, so a later step of that job (e.g. auto-verify posting stock under a new number) breaks
  the lock order. Put those callers in the brief or as their own follow-up ticket.
- A ticket that adds a global provider (interceptor, guard, middleware, subscriber) must list the
  module file that registers it, not only the new class: without the registration the fix is dead
  code in the shared tree while the worker's scratch copy (where it patched the module) looks green.
- When a ticket makes the server reject an input (duplicate lines, missing field), list EVERY UI
  that builds that payload (purchase AND sales pickers, import, POS) and ticket them in the same
  wave. Otherwise the sibling screens turn a silent bug into a 400 the user cannot avoid.
- A ticket that REMOVES a field from master data or a DTO: brief the worker to (a) check that every
  document copies it into its own snapshot column (so printed history keeps working) and grep reports,
  exports, imports and seeds for readers of the dropped column, and (b) read the global ValidationPipe
  (`whitelist` vs `forbidNonWhitelisted`) to say whether old clients still sending the field are
  silently stripped or get a 400; the answer decides whether the frontend ticket must ship first.
- A ticket that MOVES a field from a parent to its child rows (product -> each unit): grep both the
  camelCase and the snake_case column name (raw SQL, port/seed scripts, report queries, import
  templates, every HTTP suite that posts it) and list them all in the brief; the migration copies the
  value, drops the old column, and `down()` restores it from one named child (e.g. the base row).
  Brief the server so an OMITTED child field on UPDATE keeps the stored value (explicit 0 clears, new
  rows default 0), on normal and shared-copy saves alike: the validation pipe strips the old field
  from stale clients silently, so "omitted = 0" wipes the new values on any unrelated edit. The
  frontend brief still sends every row with every field. When the new child field has a cross-field rule against a
  value another tenant/owner can push (min price <= pushed sell price), state in the spec what
  happens on a push that violates it (block push, or reject the copy's next save) and tell the user.
- A new floor/limit field (lowest sell price) must be checked against EVERY other value that feeds
  the same check (customer-group prices, promo prices), not only the row's own price: list them in
  the spec and ask the user whether to block them. If blocked, guard both directions in one ticket
  (saving the other value below the floor, and raising the floor above an existing value, naming
  the record); one direction alone still reaches the broken state.
- Before telling the user when a rule fires ("only when a discount is given"), read each caller's
  trigger: callers of one shared policy often differ (some guard it with `hasAnyDiscount`, others
  run it on every line). State the per-caller condition, and correct the spec in place if an
  earlier answer was too broad.
- A float-tolerance brief must give a test case that really produces the float error: compute it
  in node before writing it (`30*0.1 === 3` is exact; `3*0.1` is 0.30000000000000004, so test
  3 x 0.1 against 0.3 in stock, and 4 x 0.1 as "still refused"). An exact example passes on HEAD
  and the worker loses a run discovering it.
- Any frontend code that splits, sums or re-distributes decimal qty/money before sending it (an
  allocator across source lines, a cap check): brief it to compute in integer cents (`roundCents`)
  of the BASE unit the backend stores, and convert with `/ 100` only at the end, and to add a sweep
  check (1- and 2-decimal totals up to the cap, box sizes like 7/12/25, every emitted value has
  <= 2 decimals and is > 0, sum equals the total in cents). `a += b` on decimals sends
  `1.7000000000000002`, and a display-unit split multiplied back to pcs sends `7.000000000000001`;
  the backend stores 2 decimals and then refuses as "over remaining". Whole-number worked examples
  never show it. The brief covers EVERY mode that builds the payload (create AND edit) with one
  shared pure splitter: fixing only the mode under review leaves the sibling sending dust. Brief
  the reviewer to simulate it.
- A frontend preview that must show the total the backend stores (a pricing card mirroring the
  freeze): before briefing, read what each side SUMS, not only how it rounds. A backend that adds
  raw line subtotals while each line column stores 2 decimals, and a frontend that only has the
  stored lines, differ by a cent whatever rounding the preview copies. The brief's check script
  feeds the backend function the raw inputs and the preview the stored (rounded) lines; feeding
  both the same rounded lines proves nothing. A mismatch caused by the backend's summing is a
  stored-value change: ask the user (sum stored lines vs keep) before ticketing it. Same rounding
  and same inputs still differ by a cent when both sides add floats in a different order (header
  percent discount / surcharge on top): brief both sides to sum line subtotals in integer cents,
  and have the check script include percent-discount and surcharge cases. Changing HOW a shared
  total helper sums (cents instead of floats) is a contract change for every caller: grep its
  callers before briefing and put each one in the file list, above all callers that subtract or
  compare their own float sum with its output ("discount = raw line sum - subtotal"). The two no
  longer cancel, so an exact 0 turns into -9e-10 and prints as "-Rp 0". A builder who writes off
  such a caller as "float noise, outside my files" leaves a visible bug; brief: "each caller
  computes in the same cents arithmetic, with a test that no discount gives exactly 0". If the user
  picks the change, the brief lists every reader that POSTS the stored total (journals,
  receivables, payables, auto-approve) to check before editing, states that already-frozen
  documents keep their totals (a deploy-notes line), and puts the preview check script in its
  verify commands so the FE and BE are proven equal on the same raw inputs.
- A worker that implements a decided rule with a narrower technical reading (posts on
  max(approval date, document date) instead of "today"): accept or reject it the same turn, log it
  in `decisions.md` as "(PM, technical)" with the reason, and name the approved reading in the
  review brief so the reviewer does not flag it as a deviation.
- A builder that carves an EXCEPTION into a user's business rule ("the rule blocks X, except the
  retry that records a failed payable") is a business question even when the reason is sound: ask
  the user keep/close as options with what each breaks (the exception's leak vs the debt that can
  never be recorded), recommended first, and have the reviewer prove the exception cannot
  double-post before commit. Never accept it silently as a PM technical call.
- A clarify call that times out with empty answers: record each question as OPEN in the spec
  (with the PM recommendation and what the current code does), build nothing that depends on it,
  keep dispatching the independent tickets, and repeat the open questions as option tables at the
  end of every later report until answered. Never read silence as the recommended option.
- A builder that ADDS content the brief never asked for to an outward-facing document (an extra
  free-text row on a print sent to a vendor or customer): treat it as a business question, not a
  style deviation. Ask the user keep/drop with the leak risk spelled out (what users could type into
  that field), recommended option first, record the answer as a decision row, and route the edit
  into the next frontend ticket's brief.
- A ticket that seeds permission codes that existed only in the enum ("seed the missing codes,
  Admin gets everything"): before briefing, grep the frontend menu (`ability.can(<CODE>`) and the
  route table for each code. A code whose menu item has no route (and often no backend) becomes a
  visible "Empty Page" entry the moment Admin holds it. List those items to the user with the
  seeding question as options (hide the menu items until built / keep visible + changelog / seed
  but keep off Admin), recommended first; never let the side effect surface only in review.
  The hide ticket keeps the items' declarations and gates (one exported set of hidden keys,
  filtered inside the existing recursive menu builder so its empty-group rule drops a submenu left
  empty), and its brief and review include a FULL sweep of every menu key's link against the route
  table (not only the seeded codes), plus the menu key count before/after with every permission.
  Menus built from an old app often carry pre-existing dead links (a singular path whose working
  page lives under a plural route elsewhere); put them to the user as one extra question
  (hide / repoint / leave), never fold them into the approved hide silently.
- Picker modals that list source lines: filter `remaining > 0 || alreadyPicked` (picked rows stay,
  disabled), with "remaining" taken from the server's progress field; verify in the server that the
  figure already excludes other active documents (one-active-child rule) before trusting it.
- Before cutting a server ticket that only feeds a UI default ("preselect the main X"), check what the
  forms already load: if every form fetches the full list and the rows carry the flag, the default is
  frontend-only (one shared hook, create mode only, set once, never overwrite edit/router/user values).
- A ticket that lets a user edit a document's date AFTER it posted stock: brief it to grep every
  table that copies the posting date (adjustment header, its lines, lot/batch movements, report
  caches) and move them all through ONE new method on the stock service (no raw stock SQL in the
  document service), inside the document's transaction after its row lock, then re-check the
  never-below-zero balance per product+warehouse (a move across a REPLACE/opname row changes the
  replayed balance). Edits that feed a posting (date) apply BEFORE the posting at the first step.
  It touches posted stock, so it gets a red-team review (lock order, lot-level balances, bypasses).
- An edit payload on a workflow step ("modal can change X, Y, Z") needs the brief to define
  "absent" vs "cleared": absent fields leave the row untouched (legacy rows must not 400), a present
  group of related fields is replaced as a whole through the same validator create uses, and step
  requirements are checked on the row AFTER the edits. Ask the reviewer to try explicit `null`s.
  The webapp brief for that modal must say what the user sees is what is saved: compare each field
  with its prefill; unchanged -> omit, changed -> send, emptied -> send an explicit clear (`""` for
  text the server trims to null, `null` for ids); when one field of a whole-replaced group changes,
  send the whole group. "Omit empty fields" alone makes clearing impossible and re-sends untouched
  prefilled notes into every step's history. Capture the step at modal open, not from the live row:
  a refetch mid-edit otherwise switches title, fields and endpoint.
- A new snapshot column (a name copied from users/master data at save) must be at least as wide as
  its source column: check the source entity's length. A narrower `varchar(n)` turns a long source
  value into a DB error the error mapper does not translate, i.e. a 500 on save.
- A ticket that adds a required field (NOT NULL column, mandatory choice) to a document: grep every
  server-side creator of that entity (direct `manager.create`, raw SQL inserts in port/seed scripts,
  imports, recurring jobs, "create from X") and every HTTP suite that posts it, and list them in the
  brief. Keep the field optional in the DTO with a server-derived default (from the contact/master
  data) and enforce "must choose" only in the form; a server-required field breaks every caller that
  never sent it. On UPDATE the default must come from the stored row, not the master data again, or
  an edit that omits the field silently flips it to today's master value. Put any rule derived from
  the field (e.g. due date from payment type) in one exported pure helper used by every creator.
- A request to MOVE a choice from the create form into a later workflow step ("pick the delivery
  method only when starting it"): before briefing, ask the user as pickable options, in ONE clarify
  call: (a) does the create form drop it entirely (column becomes nullable + every reader shows a
  "not decided yet" label) or keep it prefilled and editable later; (b) which dependent fields move
  with it and which stay because other documents read them from creation (a cost an invoice sums);
  (c) whether system creators (quick-create buttons, recurring jobs, imports) keep sending the choice
  and acting at once. Then grep every reader of the column (PDF labels, report filters/grouping,
  list filters, seeds) for null-safety, and every cross-field rule tied to the choice at create
  time ("no shipping cost for pickup"): it can no longer be checked when the value is typed, so ask
  allow / refuse at the later step / auto-clear. The server must still accept the choice on create
  for system paths and reject "act now" without it. Record new decision rows that name which older
  rows they supersede. The step that now sets the choice must read the EFFECTIVE value after its
  edits for every branch (one-step vs two-step paths), and re-resolve dependent fields for the new
  value so the old shape's fields cannot survive, legacy snapshot columns included (an old
  driver-name snapshot otherwise prints under the new method). Before the brief, list EVERY field
  tied to the choice, not only the ones the user named (a tracking number belongs to the shipper):
  a field left only on the create form becomes unreachable once the choice is gone there. Also
  brief: report/list filters get a "not decided" option (`IS NULL`); the step's history note records
  the choice and any change; what reverting the step keeps (the choice stays and the next run of
  the step may change it, or it is cleared); and a test that re-sending the SAME choice with no
  dependent fields keeps them (the webapp always re-sends the choice, and a wrong "changed?" check
  then wipes every row's fields).
- A child document that writes a choice back to its parent (invoice sets the order's type where
  still NULL): brief it to lock the parent row inside the create transaction (`FOR NO KEY UPDATE`
  keeps FK inserts unblocked), then re-check the "one active child" rule and re-read the parent's
  value there; pre-checks outside the transaction stay only for fast 400s. Without it two parallel
  creates pick different values and one skips the guard tied to that value (credit check). Require
  an HTTP check firing N pairs in parallel (exactly one 201) and mutate by removing the lock.
- Tickets that extend list search/filters with linked documents: brief one-to-many links (a
  parent's children, e.g. an order's delivery notes) as `EXISTS (subquery)`, never new joins (joins
  duplicate rows and break the pagination total), excluding soft-deleted rows inside the subquery,
  and the search kept inside the existing `Brackets` so access filters and `includedIds` still
  apply. In raw SQL fragments, quote the outer query-builder aliases (`"order"."id"`,
  `"purchaseOrder"."supplier_id"`): `order` is reserved and unquoted camelCase aliases are
  case-folded, which gives a 500 only at runtime. Require the suite to assert no duplicate ids and
  `total == rows`, plus a non-matching string returning 0 rows. Contains-matching a bare-number
  document number also hits other documents whose numbers contain those digits; tell the user.
- Before briefing a fix that tightens a shared helper (filters, guards), grep both repos' docs and
  tests for the behaviour it changes. Separate the security part (access/visibility filters) from
  convenience behaviour the docs promise (e.g. selected or archived values stay in dropdowns), and
  put that split in the brief, so the worker does not have to stop and ask.

## 2. Baselines while the wave runs
- A test run on the shared tree mid-wave is NOT a baseline: failures there belong to whoever is
  mid-edit. Steer workers to list them as "seen on shared tree, not mine" instead of chasing them.
  When the last sibling returns, re-run that typecheck yourself on the final tree before the gate;
  the sibling's errors usually vanish once it finished, and the report's "exit 2" is then void.
- A clean HEAD export lacks untracked inputs tests read (e.g. SQL under an untracked `docs/`): copy
  or symlink them in, otherwise missing-file failures look like regressions.
- Run the suites the gate skips (e.g. HTTP specs) once on clean HEAD; pre-existing failures become a
  backlog row and the comparison baseline, not a ticket's blame.
- HTTP suites share one DB and leak state (a suite flips a global setting such as oversell, or leaves
  open orders on a shared fixture product), so a later suite can fail only because of what ran before
  it. Compare only runs on a fresh DB in the standard suite order. A new failure seen in an ad-hoc
  order is not a regression until a control run of plain HEAD in that same order passes; ask the
  worker for that control run before blocking the ticket.
- List endpoints capped at a page size (`limit=200`) that a suite compares against a second capped
  list are the typical victims of accumulated data: rerun that suite ALONE on a fresh DB of the branch
  and of main before investigating code.
- Completion notices for a worker's OWN background processes (env up, suite batch) arrive in the PM
  turn: grep the baseline summary for each suite the notice shows failing. Same counts as baseline =
  acknowledge in one line and wait for the report. A suite that is green (or has fewer FAILs) in the
  baseline = steer the worker at once with the baseline numbers and ask for the fresh-DB HEAD vs fix
  control run before it reports; don't wait for the report to discover it.
- A suite that fails in the combined gate but not in the baseline: before blaming a ticket, start a
  backend from `git archive main` (and from HEAD) against the SAME gate DB and rerun only that suite
  3-4 times on each. Identical failures on main = the DB's accumulated data trips the test (record it
  in the log as DB-state, not a regression); fails only with the branch = regression. Cheaper and
  more conclusive than reading the diff for a link. Cheaper first step for a suite the repo docs
  already call order-dependent (PDF pagination, page counts): rerun it ALONE twice on the gate's
  own backend+DB; if only FAIL names already in the baseline remain, log it as order-dependent and
  commit; a new FAIL name that survives the solo rerun goes to the main-vs-HEAD comparison.
  The solo rerun is MANDATORY (not optional noise-dismissal) when the ticket edits code that suite
  exercises (a print/PDF change vs the PDF suite): "known flaky" is only accepted after it passes
  alone on the gate's DB.

- A full-jest failure in a spec whose module NO file of the wave touched (`git status --porcelain |
  grep -c <module path>` = 0): run that spec alone 3 times, each on a fresh throwaway DB, from one
  script file. All green = pre-existing flake: read the failing assertion for the cause (e.g. two
  rows created in the same millisecond ordered by `createdAt`), add a cleanup board row with that
  `file:line`, and commit the wave. Any red solo run = investigate before commit.
- A worker that reports its throwaway DB was left behind (its `dropdb` hit an approval prompt):
  drop it yourself through the worker's own drop script (`bash runs/<id>/db-drop.sh`) before the
  gate, and keep "drop the DB via a script file, not inline" in every brief.
- A PM gate started BEFORE a fix round landed (review -> fix worker while the gate still runs):
  its full test run no longer covers the tree. Kill it once its mutant lines are in (keep those
  results; they tested code the fix did not touch), drop its leftover scratch DBs in the re-gate
  script, and re-gate with the fix plus one mutant for the fix itself. Never commit on the stale
  run's green.
- A worker result carrying a tool-level "edit FAILED" flag (a patch whose old_string did not match)
  while its prose says done: `git diff --stat -- <file>` before gating. Empty diff + the fix landed
  elsewhere = log it as harmless; a changed file the report never mentions = read the hunk first.
- A worker notice showing `prettier --write <file>`: count its hunks against HEAD
  (`git diff -U0 -- <f> | grep -c '^@@'`, plus `--stat`). Only the worker's own added block = fine;
  extra hunks in old lines = unrelated reformat, have them restored before the gate. A NEW file the
  worker created is always fine to format whole.

- ONE suite at `0 pass / 0 fail (exit 1)` or `N pass / 0 fail (exit 1)` in an otherwise healthy
  gate = that suite crashed (other suites prove the backend was up). Get the real error from the
  gate's OWN DB, not a fresh one: from the gate copy dir, `set -a; . ./.env; set +a`, start
  `node dist/main` with `APP_PORT` overridden to a free port (the env file sets the port, a `PORT`
  var is ignored), wait for any HTTP status, run only that suite with `API_URL` pointing there, kill
  the backend; all in one script file. A first-page lookup (undefined) or an oversold shared seed
  product ("Tersedia: -N") = a test-fixture bug: route it into that ticket's fix-up, re-run only
  that suite on the post-gate DB after the fix (no code re-gate needed when only the test file
  changed), and keep committing the other tickets of the gate. A fix-up that cures the first crash
  can expose the next one further down: brief the fix to sweep the whole suite for both patterns.
  Keep a reusable `rerun-suite.sh <db-id> <port> <suite>` that exports the SAME env the gate does
  (`API_URL`, `TEST_DB`/`TEST_SCHEMA`, PG* vars), saves full output and prints exit, seconds, PASS and
  FAIL counts: without the env the rerun dies on "needs TEST_DB" and tells you nothing. Do not offer
  the user a cause ("probably the per-suite timeout") before that rerun's timing and last lines are
  in; a crash at 8 s is a fixture bug, not a timeout. After fixing the lookup, prove it on the SAME
  post-gate DB (copy the fixed test into the gate copy, rerun solo): that DB holds the polluting
  rows, a fresh one does not.
  A suite green in its builder's solo run that crashes only after the rest of the gate is the
  classic case: a ticket's NEW case in another suite (a future-dated transfer) leaves a row that a
  "newest row" lookup picks up. When one ticket's test change breaks another ticket's suite, the fix
  goes in the broken suite's lookup, not in the new case.

- A jest gate limited to the touched modules' paths misses suites in OTHER modules that drive the
  changed service (a notification spec that approves a mutation request). Run the FULL backend jest
  (no path list) at least once per wave before commit, or add every module whose specs import the
  changed service (`grep -rl <ServiceName> --include=*.spec.ts`) to the gate paths. More gate,
  mutation, fix-brief and commit pitfalls: `references/gate-and-mutation-pitfalls.md`.
- Widening a gate's test paths beyond the recorded baseline (a shared helper moved into another
  module pulls that module's suites in) makes every failure there unattributable. Before reading
  them as regressions, run exactly those suites on a `git archive <base-sha>` copy and on the branch,
  fresh DB each, same order, and `diff` the sorted `● ... ›` lines: identical = pre-existing (board
  row for main's owner) and the copy becomes the baseline for those paths.

- PM gate on a worktree with several workers' edits: copy it as it is on disk with
  `git ls-files -co --exclude-standard -z | xargs -0 cp --parents -t <copy>` (tracked + untracked, no
  `.git`), symlink the main checkout's `node_modules`, then typecheck/unit-test the copy. Never gate by
  `git archive HEAD`, which misses every uncommitted ticket.
- Recheck the PM gate script's paths before every gate: after a merge, follow-up work may live in a
  different checkout (main checkout vs worktree) than the one the script was written for, and the
  gate then passes on stale code. Derive the gate's file list from `git status --porcelain
  --untracked-files=all` inside the script, never a hard-coded list copied from the previous gate
  (a `sed` clone of last gate's script keeps it): a later fix round that adds a file (a new helper
  in an existing util) is then missing from the copy, tsc fails, and every suite reads 0/0.
- Prove the suites hit the backend you started: choose a port that is not already listening
  (`ss -ltn`), and abort the gate when the backend process is gone. Another app on the port makes
  every check fail (e.g. "bad token") or pass against the wrong server; that run is invalid, not RED.
- Count server errors from the logger's status-line format (e.g. `Status:.*5xx`), never a bare
  `500` grep: validation messages like "max 500 characters" inflate the count.
- Judge race/interleaving suites on FAIL count only: which request wins decides which checks run,
  so their pass count differs between gates (131 vs 132 with 0 fail is not a regression).
- After every gate, check that EACH new suite of the gated tickets has a line in the gate's
  summary. Suite runners iterate a filename glob (`[0-9][0-9]-*.mjs`), and the first suite past
  the glob's width (`100-...`) is silently never run while the gate reads clean. Widen the glob
  (`[0-9][0-9]-*.mjs [0-9][0-9][0-9]-*.mjs`), then run the missed suite solo on the gate's own DB
  before committing its ticket.
- Count `SKIP` lines next to PASS/FAIL. Suites that need extra env (a throwaway `TEST_DB`/
  `TEST_SCHEMA` + PG* vars for direct SQL setup) print SKIP and exit green without it; export them in
  the gate script, guarded to the scratch DB name, or the new checks never ran.
- Brief every NEW suite whose feature depends on optional config (a tenant code, a setting flag) to
  set that config itself through the API (the way an existing suite does) and FAIL, not skip, when it
  cannot. A worker proving RED by setting it with SQL on its own DB hides that the suite exits 0 on
  HEAD and fix alike in the gate. Check what else the leftover config turns on in the shared gate DB
  (older suites with the same skip guard now run for real and may need fixture fixes in the same
  ticket).

- A wave gate that adds jest paths the baseline never ran (e.g. `hrd` because a ticket touched one shared
  hrd file) shows failures with no baseline to compare. Before blaming the wave, run exactly those suites on a
  `git archive <merge-base>` copy and on the branch, fresh DB each, and diff the failing-test lists; record the
  main-side list as an extra known-failures file for every later gate.
- Commit each reviewed ticket while later waves build in the same tree: stage by explicit path list only, and
  check first (`git diff --stat`) that no file in the list is also being edited by a running worker.
  Then prove the STAGED set alone in a detached throwaway worktree (`git worktree add --detach
  $TMPDIR/chk HEAD`, `git diff --cached > p; git apply p` there, symlink `node_modules`, tsc + the
  touched modules' jest on a fresh DB, remove the worktree): the shared-tree gate also saw the next
  wave's edits, so it cannot show that the commit stands on its own.

## 2a. PM mutation checks on HTTP suites
- Apply ONE mutant per backend run. Suites usually crash on the first failed check (the next step
  dereferences a 400 body), so a second mutant stacked in the same run is never exercised; a run that
  shows only the first mutant's failure proves nothing about the second.
- A review finding "the suite would still pass if guard X were removed" is closed only by one PM
  mutant PER guard named (role filter, active-membership, tenant scope), each in its own run; a
  combined break passes even when only one of the guards is tested.
- Brief isolation tests with REAL counterexamples: a revoked member of this tenant, an ACTIVE member
  of another tenant only (create a throwaway tenant the way existing suites do). An account with no
  membership anywhere is already dropped by the membership join, so it passes with the tenant/status
  filter deleted and proves nothing.
- For a ticket that adds per-variant rules (allowed/rejected fields per method, snapshot fallbacks,
  trimming), write one mutant per rule in a single script up front, anchored on lines grepped to occur
  exactly once; a rule with no failing mutant is a test gap to brief back, not a pass. When the
  target line repeats (an argument line like `transactionalEntityManager,` used by 3 calls), address
  it from a unique neighbour (`sed '/deleteFile($/{n;n;s/^ *manager,$/  undefined,/}'`) and print
  that address with `sed -n` before the run: a plain `s///` mutates every copy and the caught
  mutant no longer says which guard is tested.
- Pick the mutant form that still typechecks: a boolean guard -> `(<condition> OR true)` in SQL or
  `if (false)` in TS (bound params stay used); a guard whose first clause NARROWS a type for the
  body (`if (x !== null && y > 0) throw f(x)`) -> mutate only the other clause (`y > 1e12`), since
  `if (false)` drops the narrowing and the body no longer compiles; one link of a fallback chain (`a || b || c`, one link
  per line) -> delete that line. A row lock -> delete the `lock: {...}` line; never swap it for a
  weaker mode (`for_key_share`), which still conflicts with the competing path's `FOR UPDATE`, so a
  surviving mutant there proves nothing about the race test. Never insert a literal (`null ||`): it fails the typecheck, the
  backend never starts, and the run shows "backend not running", not a caught mutant. Assert the sed
  changed the file (`cmp`), else the run is void.
- When a review hands off a risk to the NEXT ticket ("if DV-next reuses this validator, legacy rows
  will 400"), decide it as a spec decision row before writing that ticket's brief, and put the
  decision id in the brief; otherwise the next builder meets it as a STOP mid-run. A helper the
  review calls "exact only while the caller refuses X" (an amount helper that also counts pending
  receipts) becomes an ORDERING rule in the caller's brief: run every refusal on the locked rows
  BEFORE calling the helper, comment that dependency at the call, and add a test per precondition
  (X present -> refused, nothing computed). Cheaper and safer than narrowing the helper's filter,
  which would silently diverge from its sibling count query.
- When a reviewer REPRODUCES a defect that a later ticket owns (a probe on the committed code shows
  phantom stock that the guard ticket will close), write into that later ticket's brief that its
  test for the case MUST be RED on the earlier ticket's commit, citing the probe. The fix is then
  proven against the real gap, not a hypothetical one, and the board records that nothing merges
  between the two commits.
- Prefer mutating the PM gate's own scratch copy (the `worker-env`/gate dir that already holds HEAD +
  the ticket's files and a migrated DB): `sed` the anchor there, rebuild + rerun only the guarding
  suite with `rerun-suite.sh`, restore from a `.bak`, then `cmp` the copy's file against the real
  tree. The real checkout is never touched, so no restore can be missed and a reviewer reading the
  tree never sees the mutant. Only if no gate copy exists: mutate the worktree, build, restore at
  once (sha256 match) before running the suite, and steer any reviewer reading those files first.
  When the fresh review is dispatched while in-tree mutants run (the usual case for jest-only
  gates), name the mutant SHAPES in the review brief up front (`if (false)`, a guard line become
  `;`, a lock line deleted, a helper returning the raw field) with "re-read a minute later before
  reporting": reviewers then flag nothing false, and they still catch a real missing guard because
  it does not come back on re-read.

## 2b. A worker cut off mid-ticket (rate limit, timeout, OOM)
- Workers gone with reports stuck at IN PROGRESS and a batch result of `status=unknown` ("owner
  exited"): check `delegate_task action=list` and `journalctl --user | grep -i oom` before
  re-dispatching. If the app was OOM-killed, re-dispatching the same fan-out kills it again: lower
  the parallelism first (section 1). Grep the dead transcripts' tails for RED/GREEN results and log
  them on the board as leads, but have the resumed worker re-run them; a dead worker's numbers are
  not evidence.
- First prove what landed: `cmp` every changed + untracked file against the last PM gate copy (loop
  over `git diff --name-only` + `git ls-files --others --exclude-standard`). All identical = the dead
  worker changed nothing: re-dispatch the same brief with one context line ("previous attempt died,
  nothing landed, overwrite its partial report") and skip the critical-review step below.
- Two or more workers lost in one run (owner exit or 429): tell the user once (app restart or rate
  limit) and drop to one worker at a time until the run is quiet again.
- Otherwise its partial edits stay in the shared tree. Kill its scratch backend, leave the edits alone (no
  revert), and dispatch a FRESH worker with: the same brief, the partial build report, the tail of
  the dead worker's transcript, and the instruction to review those edits critically against the brief
  and the real code before finishing. Half-applied edits hide real bugs (an edit applied to a
  pre-lock copy, broken indentation) that a "just finish it" brief would ship.
- The resumed ticket gets the normal fresh review; its review must look for leftovers and dead code
  from the first run.
- A REVIEWER lost with no report file: confirm its backend pid is gone, then re-dispatch with the same
  review brief plus an appended "Run notes" section: create the report skeleton in the first minutes
  and append each finding as it goes; the env vars its suites need; what the PM gate and mutation
  already proved, so it skips the full regression and spends its time on code reading and targeted
  probes. The second run is usually faster and finds more.
  A reviewer lost WITH a partial report (some tickets reviewed, verdict table empty): keep the file,
  and dispatch a fresh reviewer scoped to the tickets it did not cover, told to append its sections
  and fill the whole verdict table without re-reviewing the finished ones. Gate results already in
  go into its brief so it stays static (no jest/build).
- A worker that stopped after writing only a PLAN (no code) is a cheap restart: read its plan,
  accept or reject each design choice, append a dated "PM update" section to the SAME brief with the
  rulings (rejected approach + why, the prescribed one), and dispatch a fresh worker told the plan is
  advisory only. Typical rejection: a guard that must hold on every writer path (no posting before an
  account's opening date) placed in a hidden ORM subscriber or DB trigger; prescribe one explicit
  check function called from each posting path instead, listing those paths, so readers of each
  service see the rule and tests can target it.
- An owner-session exit kills the PM's own background gate jobs too, not only the workers: the
  process id comes back `not_found` and the log stops before its last marker (e.g. `GATE_DONE`).
  Check every running gate log's tail after such an exit and re-run the gate from the start;
  partial numbers (tsc, jest) are not a gate. The killed gate leaves its backend running (pid file
  next to the gate's DB name): kill it before the re-run, or the new gate's port/DB setup collides.
  An interface switch in EITHER direction (desktop <-> terminal) counts as an owner exit: it kills
  in-flight reviewers and gates the same way (the gate shows exit -15 / SIGTERM). Recovery: grep the
  tree diff for leftover mutant shapes, drop the killed gate's scratch DBs, re-run the gate, and
  re-dispatch the reviewer with run notes (skeleton first, append findings) if its file is empty.
- A worker killed by a 429 AFTER it wrote a complete build report and its own test run finished
  (the orphaned process notice shows the counts) is done, not cut off: read the report, verify its
  load-bearing claim in the code yourself (`file:line`), and go straight to the PM gate + fresh
  review. Re-dispatching repeats the work and spends the rate limit again.
- A worker lost AFTER its own final gate finished (summary file complete, process gone) is not
  cut off: do not re-dispatch. Diff the files it touched, read every changed existing test (fixtures
  added vs assertions removed), write the build report yourself marked PM-written with what was lost
  (its deviation/STOP notes), then run your own gate and the normal fresh review.
- Other tickets' reviewed files can still be committed meanwhile with explicit path lists; the
  combined gate runs again before the resumed ticket commits.
- Whole wave killed by a rate limit: record per ticket on the board which files hold its partial,
  unverified edits, the reset time and the resume plan ("resume at cap 2, nothing committed before
  gate + review"), then tell the user and stop dispatching. On resume, re-check `git status` and
  whether the base branch moved upstream, then dispatch the resumes with the RESUME brief above
  (draft = owned but untrusted; every other partial ticket's files listed as not yours). Expect the
  resumed worker to find a real bug in the draft (a type-mismatched join giving 500s) at least
  sometimes; that is why it must re-run the neighbouring existing suites, not only its new one.
- A worker whose green ran on a scratch copy of an older HEAD (a sibling committed meanwhile, or a
  new tenant migration landed) is not gated yet: run the PM gate on current HEAD + its files before
  the re-review or commit, and say so to the reviewer.

## 2c. A worker whose test run never happened
- A worker reporting "blocked by an approval prompt / not retried" leaves the HTTP evidence missing,
  not failed. Run the gate yourself from a script file (both backends it left running, one line per
  suite with exit/pass/fail plus the FAIL lines, deadlock grep, then kill the backends); check each
  suite file name exists first, since guessed names silently skip a suite.
- Every suite failing with `fetch failed` / connection refused is the same void run: usually the
  backend was started on a DB that had not yet applied the branch's new migration and refused to
  boot. Migrate first, then start the backend, then run suites; steer a worker or reviewer back
  instead of reading it as RED.
- Every gate/mutation script that creates a scratch DB exports `PGPASSWORD` from the env file and
  runs `createdb ... < /dev/null || exit 1`: without the password the client prompts, the
  background job prints `Password:` forever and no step after it runs (put the same line in the
  workers' shared rules file).
- A count of zero is evidence only if the tool actually ran. Every suite at `pass=0 fail=0` means
  the backend never started (read the setup log: usually the scratch DB was not created because the
  DB-create step did not run before the backend-start step; chain both in the gate script). A lint
  "0 errors" piped through `grep -c` is void when the formatter flag errored (e.g. a formatter that
  is not installed); re-run with the default formatter and report its real exit code.

## 3. Cross-ticket fallout
- Prevent that at brief time: when a decision changes visible output (a print line, a label, a
  filter), grep the HTTP suites for the old expectation (`grep -n '<label or regex>' test/api/*.mjs`)
  and put each `file:line` to update into the ticket's file list. When the user's decision covers one
  state and neighbouring states are left implicit (prints for "not started" but nothing said about
  voided), record your reading of them in the same decision row marked as the PM's reading and say
  it in the reply, so the user can overturn it.
- A change that intentionally alters a rule (a dropdown now hides X) fails existing checks that encode
  the old rule ("list is complete = every row with status S"). That is not a regression: name the
  check (`file:line`), show it passes on main, and have a small follow-up update only that check to
  the new rule, keeping the file's style. Leave its pre-existing failures alone.
- One ticket's new guard can break another area's existing test (e.g. a test that builds now-refused
  input through the service). The worker must STOP; the PM decides (usually: build that input as
  legacy data by SQL in the test, expected amounts unchanged), records it, and dispatches a tiny
  fix brief in parallel with the reviews.
- A ticket that moves shared helpers into another file (extracting a hook/util so a second screen can
  reuse it) breaks every older ticket's check script that imports them and the gate scripts that
  still run those checks. Brief the mover to carry the old checks' cases into its own check file and
  name the gate scripts to repoint; the PM repoints them before the next gate.

- A review that APPROVES the diff but shows the bug still reproduces through other files (a
  tolerance added to the ledger check while pre-checks in sales order / import / transfer still
  compare raw floats): commit the approved diff, keep the finding open, and route each remaining
  path into the open ticket that already owns that file (extend its brief) or one new small ticket
  for files owned by committed tickets. Tell the user the count change and why. Prevent it at brief
  time: a fix to a guard (tolerance, status check, permission) lists every place that pre-checks the
  same condition before the guarded call (`grep` the guard's inputs, e.g. `getCurrentBalance(`
  callers), so the worker fixes or names them all.

- A ticket that changes an API contract many existing suites call (a required new id replaces the old
  one) breaks those suites at the request itself. Cut a tests-only `<id>s` ticket to adapt them and run
  it beside the code review; its brief requires one logged rule change per assertion that encodes the
  old rule and leaves pre-existing failures alone. Gate code + adapted suites together (code alone
  buries real regressions under contract noise), then commit twice from that one gated tree: code +
  its new suite, then the adapted suites.

## 3a. User reverses a decision while its ticket is built but not committed
- Save the ticket's diff before removing it (`git diff -- <its files> > runs/<id>/<id>-dropped.patch`),
  then restore ONLY those files from HEAD in a script (`git show HEAD:<f> > <f>` per file; checkout,
  stash and reset stay forbidden), and print `git status` to show the sibling tickets' files are
  untouched. Mark the row DROPPED with the decision id and the patch path, update the spec row in
  place ("first answered b, changed to a after <reason>"), write the accepted side effect into the
  module doc, and re-gate the remaining tree from scratch: the earlier gate covered the dropped code.
- A review note "X was not checked" (an edit form's error display) becomes a verify-first ticket:
  the brief asks for the file:line trace of what the user sees today through the shared hook, and
  allows "verified, no change" as a valid outcome with that trace as evidence plus manual QA steps.
  Code changes only if the trace shows a gap, copying a form that already does it right.

## 3b. User changes a decision after the ticket is committed
- Record a new decision row that says which earlier one it revises, and for which surface only
  (e.g. "report shows X again; invoice keeps excluding X"). Then a small `<id>b` ticket on the same
  branch with its own review + gate + commit. Never amend the committed ticket.
- Before briefing, ask the split the first decision blurred, as pickable options: "show it in the
  list" vs "count it in the totals", and "this screen only" vs "the other places the rule applies".
  Excluding an item from totals and hiding it from a list are different user decisions; ask both
  when a fix filters VOID/cancelled rows out of a report.
- "Listed but not counted" brief: rows stay in the detail view and the totals skip them through a
  predicate keyed on row DATA (status label, document number), never on object identity, which
  silently re-counts after any copy/sort; grouped/aggregate views drop them; add a summary count of
  listed-not-counted rows; when the user filters on that status explicitly, totals describe them.
  Have the worker cite every consumer of the totals (UI total row, XLSX/PDF export) and STOP if any
  sums rows client-side.

## 4. Commit
- Reviews only read files, so dispatch them while the PM gate runs; commit per ticket once its gate
  and review are both in. A ticket whose review finds a MAJOR test gap is held (uncommitted, its
  files untouched) for a small test-fix ticket, while its siblings commit and a dependent frontend
  ticket starts against its API contract, which the fix brief must not change.
- Rolling commits (tickets finish at different times): gate each group of reviewed tickets as
  `HEAD (already-committed tickets) + this group's files` with `scripts/gate-vs-baseline.sh`, then
  commit the group ticket by ticket. Each gate is cumulative over everything committed so far, so a
  fresh full gate per ticket is not needed, and the next group's builders and reviewers keep running
  meanwhile (only the gate's backend counts toward the memory cap). A ticket that waits on others
  (shared file) gets its brief rewritten with re-verified `file:line` refs right after they commit.
- Ask reviewers of a NEW suite whether it restores every global setting it flips (tax rate, credit
  sale, allow-without-X) and leaves no open shared state (cash register, open orders): a leftover
  setting silently changes every later suite's outcome in the shared gate DB. Fix it as a test-only
  follow-up before commit.
- A reviewer finding a MAJOR pre-existing bug inside a group the user already approved for this run
  (e.g. a missing lock in the locking group, no business rule involved): add it as its own ticket
  without asking, record it in `decisions.md` as "(PM, within approved group X)", order it after
  the ticket that owns the shared file, and tell the user in the next report. Anything that changes
  visible behaviour or a business rule still goes to the user first. Minor findings go to the backlog.
- Collect a wave's MINOR review notes into one cleanup ticket per side (backend/frontend) with its own
  file list and run it in the next wave; a cleanup per ticket multiplies gates and reviews. When the
  NEXT ticket mirrors the reviewed one (supplier side after customer side), fold the minors into its
  brief instead ("also in this ticket", with the exact extra files allowed): it reads those files anyway,
  and applying the fix to both sides keeps the mirror identical. A race-coverage minor ("only one
  ordering was ever observed") is briefed as a forced-order test plus a PM-visible proof that it fails
  with the lock removed.
- Read every green fix-round diff yourself before gating it (`diff -u <gate copy>/<f> <f>`). The
  worker fixed the scenario the review named, not its neighbours. For each new guard keyed on a
  link or status ("refused while bound to a live invoice"), walk the reverse transitions: parent
  cancelled, parent re-created, child re-linked. A link that survives its parent's cancel reopens the
  same hole one step later (cancel A -> new invoice B never re-binds -> guard no longer fires). A gap
  found = a `<id>c` brief on the same tree with that exact sequence as a test that must be RED first;
  gate all fix rounds together.
- Review follow-ups get their own tiny brief (`<id>b`, `<id>c`) with an exclusive file list and append
  to the same build report; the original ticket's review covers the follow-up, so review the pair
  together once the follow-up lands instead of reviewing twice.
- A fix brief that names a failing test cites the file from the gate/worker log (`grep -l '<test
  title>'`), never from memory: a guessed sibling file name sends the worker to the wrong suite.
  A reviewer's MAJOR that rests on reading lock order only (not reproduced) is briefed as "VERIFY
  first with file:line, reproduce in a race spec, then fix"; if the reviewer is wrong the worker
  says why and stops for that item.
- Put "STOP if <invariant the fix relies on> does not hold" (a lock the path must already take) in
  fix briefs: a worker that stops there costs a minute. Verify its claim in the code (callers of the
  method, which locks it takes), decide as a "(PM, technical)" spec row, append a "PM decision after
  the STOP" section to the SAME brief (helper to add, final lock order, races to add), re-dispatch.
- A review returning CHANGES while the builder cap is full: write the fix-up brief at once (build on
  the uncommitted tree, one item per finding, a forced test for any race finding that must fail
  with the old order), mark the row "FIXUP queued" on the board, and dispatch it when a builder slot
  frees; never exceed the cap for it. Decide reviewer "needs PM decision" minors in the brief as
  "(PM, technical)" spec rows by copying the nearest existing guard in the same service (e.g. the
  Rp 0 skip already used for last-price updates), and send the rest (indexes, perf) to the backlog.
- When one ticket's review finding is a PATTERN (e.g. a status write that bypasses the audit log),
  record it as a spec decision, grep every other built-but-uncommitted ticket's diff for the same
  pattern, and fix all of them in ONE follow-up brief before their reviews run; pre-existing
  instances outside the run's files become one backlog row, not more tickets.
- Local-commit runs (no push): first one combined gate on a scratch copy of HEAD + EVERY changed and
  untracked file (`git status --porcelain --untracked-files=all`), fresh DB, unit + full HTTP suites,
  then `diff` the per-suite summary lines against the main baseline. Identical existing lines + all new
  suites green = gate passed. When the baseline already has red suites, also compare FAIL lines by
  name: strip each line's payload after ` :: ` (ids, timestamps differ per run), `sort -u`, then
  `comm -13 baseline gate` = new failures (regressions), `comm -23` = failures the wave fixed. Export
  `TEST_DB`/`TEST_SCHEMA` AND `PGHOST`/`PGPORT`/`PGPASSWORD` (the scratch cluster) in the gate:
  without the first pair suites needing direct SQL fail as "needs TEST_DB" on both sides; without
  the PG* vars their `psql` calls hit the default socket and the suite dies midway. Read a summary
  line `N pass / 0 fail (exit 1)` as a crash, not green: open that suite's output before diffing. Then one script commits ticket by ticket with explicit path lists
  (`git commit -- <paths>`), author set via `GIT_AUTHOR_*`/`GIT_COMMITTER_*` env, asserting the branch
  first and printing `git status --short` at the end (must be empty).
- Webapp-only tickets have no HTTP gate: run `tsc -b` and the repo's check scripts on the real tree,
  then re-run the worker's logic/script test yourself. First `diff -q` each ticket file in the
  worker's scratch copy against the working tree (a stale copy makes its green void), then run it in
  fix mode (all pass) and HEAD mode (record the FAIL count as RED). Browser behaviour stays listed as
  NOT verified.
- One `files.txt` per ticket. Before launching, assert the union equals `git status --porcelain`
  (tracked + untracked) and no file is in two lists.
- Write the gate's file list with sha256 (`gated-sha.txt`) when the gate starts; the commit script
  reads its file list from that file, runs `sha256sum -c`, asserts the tree's changed+untracked set
  equals it, and only then stages. That ties the commit to exactly what was gated and reviewed.
- PM pre-commit checks (sha re-check, formatter on new files) go in a script from the start: an
  inline loop with pipes and `$(...)` gets flagged for approval even though it only reads. Edit the
  board/log files (`tickets.md`, `decisions.md`) with the patch or write_file tools, never an inline
  `python3 - <<EOF`, a `sed -i` one-liner or an execute_code script that rewrites the file: those can
  hit the same approval prompt (and when the user is away it times out), so a blocked board edit
  leaves the board stale while work moves on. Several row changes = several `patch` calls in one turn. If such a
  prompt is blocked, keep reviews and scratch-copy gates running but hold every commit after it, and
  ask once with the held commits plus the fix-or-ship choice for the open review minors, recommended
  option first, so one "go" answers all.
- A changed file that is in no ticket's list: grep every worker transcript of the run for its path
  before anything else. No worker touched it = the user's own parallel work in the same checkout:
  log it on the board as "not ours, never stage", name it to the user once, exclude it from every
  gate copy and commit list, and leave it untouched (never revert or format it). If the user then
  says to commit it, give it its own commit (separate from every ticket) and a board row so the
  final changelog step includes it.
- The same applies to a single unexplained HUNK inside a file a ticket owns (a reviewer flags an
  edit the build report never mentions): before blaming the worker, check the worker's transcript
  for a patch/write touching that line (`grep -n "<file>" task-N.log | grep tool`, read the patch
  diffs) and compare the file mtime with the user's other edits. No worker edit = likely the user's
  in-progress change: do not revert it yourself, hold that ticket's commit, and ask the user with
  options (restore / keep as intended, with the exact consequence of each, e.g. what a helper does
  with an empty argument). The other tickets of the wave still commit.
  When the user confirms the change is intentional, implement the INTENT the codebase way, not the
  literal edit: read the helper it calls for an existing option (e.g. a `withPrefix: false` flag
  instead of an empty prefix that both prints a stray separator and restarts a counter keyed on the
  prefix), grep code and suites for readers of the old format, record it as a spec decision, and
  ship it in the owning ticket's commit with a changelog line.
- Protected instruction files (CLAUDE.md, AGENTS.md) need the user's approval per edit; a timed-out
  prompt means the edit did not happen, by any path. Put the exact proposed text in the run report,
  tell the user once (approve the next prompt or paste it), and keep committing: a docs-only line
  never holds a ticket.
- A review finding that is really a tax/finance rule goes to the user as options (recommended first,
  consequence each). If the user picks a non-recommended option, record it as "user chose X against
  PM recommendation Y" with the consequence in the spec and `decisions.md`, drop the fix from the
  fix-up brief, and do not re-argue it.
- Template for the per-ticket-set gate (fresh DB, tsc, jest, all HTTP suites, summary diff, crashed
  suites, FAIL-line `comm` vs baseline): `scripts/gate-vs-baseline.sh`. Run it in the background
  with notify; it holds one backend, so it counts toward the memory cap.
- ONE chained job (through the long-job wrapper): for each ticket in dependency order, worktree from
  the current HEAD + that ticket's files (untracked inputs symlinked), gates, extra suites on its own
  DB, sha-check files vs gated, stage exactly the list, commit, push; stop at the first red. Each
  commit is then green on its own base.
- PM wording/comment fixes after a review go in before the job starts, never between gate and commit.
  A reviewer's "new formatter error on line N" in a file that is clean at HEAD: copy the file to
  scratch, run the formatter on it, `diff` copy vs result and confirm only line N moved before
  gating; on a file with formatter debt at HEAD, fix line N by hand instead.
- Commit gates on files that already carry formatter debt at HEAD: `prettier --check` on them fails
  forever and tempts a whole-file reformat. Gate on NO NEW debt instead: per touched file count the
  lines of `prettier <f> | diff <f> -` for HEAD (piped via `--stdin-filepath`) and for the working
  copy, abort only when the count rises, and keep that per-file table in the run log.
- List touched files with `git status --porcelain --untracked-files=all` in scripts, never `--short`:
  only porcelain is a stable, config-independent format, and without `-uall` a new directory is one
  entry (`dir/`), so a lint/format step filtering by extension silently skips every new file in it.
  Print the file count the gate checked.
- After the job: mark the closed backlog rows on the board in the same pass.
- A user's "merge to develop and push" before the run is finished: merge the committed, gated
  tickets only, without touching the shared tree (`git-branch-integration` step 8b'), keep the
  workers running, and plan the second merge (rest of the tickets + changelog) at the end.
  First run `git rev-list --count <base>..HEAD` and read the project's push/merge rule: with 0
  commits ahead, or a rule that keeps the PM off `main`, do nothing and answer with a short table of
  readings (start building / merge another branch / change the rule), recommended first. A terse
  follow-up like "go all" then means the first reading: say so in one line, record it in
  `decisions.md`, and dispatch.
  Before running it, check `git status`: an uncommitted file belonging to a finished ticket
  (a PM prettier fix, an unstaged test) would silently stay out of develop.

## 4b. Merging `main` into the run branch mid-run
1. Assert a clean tree and `main` == `origin/main`; list `git log <branch>..main` and the files BOTH
   sides changed since the merge base (`comm -12` of the two `git diff --name-only <base> <side>`).
2. Start `git merge --no-commit --no-ff main` yourself and leave a conflicted merge in progress. Brief
   ONE fresh worker (read-only git only) with: each conflicted file, the behaviours from EACH side that
   must survive (cite the run's decision ids), how to join diverged signatures (fold the new param
   into the options object, update every caller including auto-merged files), new code from main must
   follow the run's lock order and fail-safe paths, and STOP on a business conflict.
3. Also check collisions git does not flag: two new test suites with the same numeric prefix (rename
   ours), doc sections both sides edited, new migrations (verify on a FRESH DB so they run).
4. The worker verifies in an `rsync` copy of the working tree (no `.git`/`node_modules`); a HEAD
   export lacks the in-progress merge. Then fresh review, gate, PM commits the merge from a script
   that asserts the branch, that `.git/MERGE_HEAD` exists and that no `^<<<<<<<`/`^>>>>>>>` is left,
   `git add`s the resolved files and the renamed suite, `git rm --cached` the old suite name, then
   `git commit --no-edit` and prints `git rev-list --count HEAD..main` (must be 0). Ask whether the
   run's other repo needs the same merge. If the user already merged it himself, don't redo it.
   Verify instead: clean tree, `git rev-list --count <branch>..main` is 0, typecheck and the repo's
   check scripts pass.
5. Shipped behaviour on `main` can contradict a decision recorded earlier in the run (e.g. main
   re-checks something the run decided not to re-check). The worker keeps main's version and
   reports it; the PM puts it to the user as a decision. State the exact condition from the code
   ("only for CREDIT orders"), not a summary. Then update the decision row in place, marked revised.

## 5. Docs ticket and the final check
- A docs/changelog worker can run beside a code worker in the SAME worktree when the file lists are
  disjoint and each brief names the other's files as untouchable. Brief the code worker not to edit
  the changelog files; the PM adds that ticket's changelog line when the docs worker is done.
- A docs/runbook ticket that touches no source can run during the commit job, but it reads a HEAD that
  is still moving: after the chain finishes, bump the commit ids it wrote to the final one before its
  review and commit.
- End-of-run changelog: dispatch ONE docs worker after the last ticket commits, with a must-include
  list (every user-approved item that has no ticket of its own, e.g. the user's own edits that were
  committed, an intentional format change; each behaviour change finance or users will notice) and
  a separate "Deploy" bullet at the top of the server log: every migration on the branch found by
  `git diff --name-only <base>..HEAD -- <migrations dir>` (not from the board), which ones change
  data, which must run with the app stopped and why, no-backfill notes, and which report totals
  change. Brief it to take facts from `git show --stat <sha>` and the build reports, not the board
  summary (board counts drift: "8 files" was 9). The PM reads the user-facing entries before
  committing (no endpoints/tables/files there), and the webapp typecheck must pass on the entries file.
  Brief the docs worker to (a) describe every still-open user question as OPEN (a line like "the
  preview now equals the stored total" silently presents an undecided rule as shipped), and scope
  every equality claim ("screen equals saved", "lines add up to the total") to the data it holds
  for: rows copied from another document (work-order lines copied from a quote at its quantity)
  keep their old values until re-saved, so the claim is false on them until then, (b) take UI
  terms from the app itself (menu path from the menu-items file, the module name earlier client-log
  entries use), never the code/English name, (c) word idempotent deploy steps as "run first in
  every case", not "where X", and (d) end its report with a "claims taken from commits/spec, not
  verified in code" list. The docs review then checks each listed claim at `file:line`, verifies the
  deploy block by script (`git diff <base>..HEAD -- <enum files>` = the exact ALTER values; added
  payload rows = the listed permission codes, none missing or extra), and greps the client entries
  for anything touching an open question. Apply its wording fixes yourself (docs-only), then re-hash
  the gated file list and re-run the frontend typecheck on the entries file before committing.
  When the user later answers questions the docs list as OPEN, the ticket that implements the
  answers also rewrites those doc lines (developer changelog known-gaps, client changelog, module
  READMEs) as decided, including any "no code change, already the behaviour" answer. Otherwise the
  merged branch ships docs that still call a decided rule open.
  When the PM writes changelog prose with the patch tool, type plain `"` in `new_string`: text copied
  from a patch diff shows quotes escaped (`\"`), and pasting that writes literal backslashes into
  Markdown. Grep the edited files for `\\"` before the commit script runs.
- Every progress line to the user ("N of M done") is recomputed from the board right before writing
  it: count only rows whose status is DONE with a commit sha, and keep M fixed unless you name the
  row that was added. A ticket that is approved but still held for a fix-up or gate is not done;
  counting it, or bumping M, makes the next status answer contradict this one.
- "Is it all done?" / "what is done?" after a long run: answer in USER terms first, not ticket ids
  and shas. Lead with one line naming the feature and where it is (develop, not deployed), then a
  numbered list of what users can now do (menu path, what they pick, what the system does, the new
  rules they will hit), then "what is NOT done" (open requests, deploy, unverified flows). Ticket ids,
  commit shas and gate numbers go after, or only when asked. A table of S1/W1/X rows reads as jargon
  and gets "wait, what is done?" back. When two requests ran in one thread, say plainly which one was
  built and which one is still waiting.
- Merge-approval message: fetch first and report whether the base branch moved
  (`rev-list --count develop..origin/develop`, `merge-base --is-ancestor`), commits ahead per repo,
  the deploy notes, what was NOT verified (browser flows, named), and the exact merge steps you will
  run; then ask one yes/no question. Carry any open question for the NEXT feature at the end, not as
  a blocker.
- Before telling the user the wave "works": run the WHOLE suite (unit + HTTP) on final HEAD in a clean
  worktree, because each ticket's gate ran only its modules. Re-run every failing spec on the
  pre-feature merge-base (`git merge-base HEAD origin/main`): same failures on both = pre-existing
  (backlog row), HEAD-only = regression. Report what tests cannot show (screens, prod-sized data).
