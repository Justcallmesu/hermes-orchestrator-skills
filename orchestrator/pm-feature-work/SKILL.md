---
name: pm-feature-work
description: "Use before designing a PM feature; grill decisions first."
version: "1.0.0"
author: "Suwanto Ardi Winata (PT. Grha Digital Indonesia)"
license: "UNLICENSED"
tags: ["pm", "feature-work", "grill", "spec", "tickets"]
related_skills: ["thin-orchestrator", "pm-discovery"]
---

# PM feature-work: from request to worker handoff

The PM side of a feature: discovery → grill decisions → spec → tickets → handoff to fresh workers.
This runs BEFORE the worker kit (thin-orchestrator, to-tickets). It is the phase where wrong
business rules get caught — tests catch wrong code, not wrong requirements.

## When to Use
Use this skill at the start of any PM feature request before a spec, a ticket list, or a worker
brief is written. Trigger it when the user asks to add, change, or wire together a feature (for
example: a new document type, a new status/approval, a payment or ledger move, a report, a
reporting filter, or a UI form), or whenever a decision a designer would otherwise take silently
would bake in a business rule. Re-run it after a pause or a resurface of the feature.

## 0. Grill before you build
When asked to design or write a spec for a feature, do NOT start with the design. First convert every
open business question into 2-4 concrete options with its consequence, recommend first, and get the
user's explicit confirmation. A bare "sure" or "go" is NOT a decision — before acting you must
state which option you are taking, out loud. A single letter ("A") sent after a form with several
open Qs: take it as "all recommended" only when every open Q's recommended option is labelled A (a
yes/no Q counts when its recommended answer is the one marked recommended), say that reading in the
first line, record each id as "user '<letter>' read as recommended", and invite a correction.
To make this safe, label the recommended option A in every Q you ask. An answer naming ONE id of several ("Q20 B")
decides only that id: record it, re-ask the rest (plus any new Q the answer creates) and build nothing.
This user often switches to English mid-thread: reply in the language of the last message. If the user does not respond to a question, ask again
rather than assuming. Genuinely technical questions you may resolve yourself, but surface them. Do
not design or write a spec until the direction is confirmed.

## 1. Discover first
- Before the grill, show the user what the module ALREADY does on the latest `origin/main` (and say you
  searched every branch and archived repo): a short table of the form fields / entity columns / reports
  per variant (e.g. per contract type), then the exact gap. Users often believe a module is already
  complete and will send you back to check; leading with the inventory answers that up front and keeps
  the decision questions to the real gap.
- **Revision of an existing flow** ("we need to revise the X flow", "do you understand?"): reply with an
  understanding check, not code. (1) Restate the request as numbered requirements R1..Rn. (2) Map each R to
  what the code does today, with cites: the entity columns, the service transition, the UI control
  (popconfirm vs modal) and every consumer of the field (PDF, reports, list filters). (3) Flag each R that
  is already built (e.g. a modal that already exists for step 2), and each R that conflicts with the
  domain meaning of the variant it targets (e.g. fleet/driver attached to the customer-pickup method).
  Present the conflicting ones as Q-options with the domain-sensible choice recommended first, and never
  silently "correct" the user's mapping. (4) For any step whose editable fields feed a side effect that
  already happened (date used by an earlier stock posting), ask whether to lock or propagate the field.
  (5) For "record one user column, the last one wins", name which existing column survives, what stops
  being written, and what undo restores. History is kept elsewhere.
  (6) For every new field on a multi-step flow, ask at WHICH step it becomes required (create / start /
  finish). Default recommendation: optional until the completing step, because staff often do not know
  the driver, vehicle or receiver when the document is created or dispatched.
- **Batch of small UI/master-data changes** ("fix X, check other places too, also move field Y, also default Z"):
  answer with one section per request, each laid out as current behaviour (cited) → fix → Q-options. Then:
  (a) Sweep for siblings. Grep the shared component the bug lives in (e.g. every caller of a picker modal)
  and list each sibling with the same defect in a table. If one sibling already does it right, name it as the pattern
  to copy. Keep "already added" rows visible but disabled, since that exists to stop duplicate source lines.
  (b) Moving a field (product → unit level, etc.): grep EVERY consumer of the column, in server and webapp,
  including imports, shares, reports, POS, data-port/seed scripts (`src/scripts`) and the API test suites.
  Grep both spellings: the camelCase property AND the snake_case column (`default_cost`) — raw SQL in
  reports, scripts and `*.sql` checks only use the latter. Scripts that INSERT the column break once it is dropped. Suites that set it as a fixture must move it to
  the new field, and suites whose assertions relied on its hidden role must set the new field to the old
  effective value, or they pass while asserting nothing. Check the validation pipe (`whitelist`,
  `forbidNonWhitelisted`) so you can say whether an old client still sending the field is rejected or silently stripped. Look for a hidden second role, such as a cost field the code also uses as the
  selling-price floor. A new field that would take over that role makes "what is the fallback when empty?"
  a business question. Backfill is a Q too, asked as SEPARATE Q ids per dimension, because each one changes
  release-day behaviour differently: (1) parent → child copy scaling: the same number on every unit, or
  × conversion. Same-number makes larger units wrong until edited, so say so. (2) Whether the NEW rule
  field is seeded from the old value or starts at 0 = off. Starting at 0 switches the rule off for all
  existing rows; spell that out as its own Q. The user often picks the minimal backfill (same number,
  default 0, "users edit later"), so do not pre-commit to the behaviour-preserving option. Record the
  accepted gap as a risk in the spec. A picked backfill overrides the 5b no-backfill default.
  Also ask: which documents enforce the rule? Grep every caller of the shared check and state its
  trigger PER caller (e.g. quotation/SO only with a discount, invoice/POS on every line): callers wrap
  the same helper in different conditions, so a one-line summary of "when the rule applies" is usually
  wrong for some documents. If the user names fewer than the code enforces today, point out the bypass gap.
  List every OTHER price source that can sit below the new limit (customer-group prices, promos,
  shared-copy pushes) and ask how each relates to it, recommending "reject saving a price below the
  limit": otherwise a valid group price makes every discount, or every invoice line, for that
  customer fail. Is there a cross-field check against the sibling field (floor ≤ sell price)?
  Decide update semantics for the new child fields in the spec before the brief: on UPDATE an OMITTED
  field keeps the stored value, an explicit value (incl. 0) is applied, a new child row defaults to 0.
  "Omitted = 0" lets an old browser bundle (still open after deploy), a script, or a partial payload
  silently switch a rule off on an unrelated edit, because the validation whitelist strips the old
  field without an error. Keep the webapp sending every field anyway.
  When the moved field also changes MEANING (a cost that becomes a selling floor), the webapp brief must
  list every label, error text and prop name that still states the old meaning ("Harga minimum (modal)",
  `minimumPrice`): grep for them, because the typechecker does not flag wording.
  For a pre-fill that depends on two fields set in sequence (product, then its auto-picked unit), the
  brief must say: read the dependent field from the form inside the effect (`form.getFieldValue`), not the
  render-captured value; otherwise a product switch fills the OLD unit's price, and a filled price is never
  corrected afterwards.
  Who owns the new field on shared or copied master data? Recommend per tenant when the field it
  replaces was per tenant. Then check every cross-field rule that mixes a shared field with a per-tenant
  one (main tenant pushes the sell price, copy owns the floor). Do not block the push on a copy's data,
  and do not rewrite the copy's value silently: reject the copy's next save and list it as a spec risk to the user.
  (c) Making a field auto-fill ("auto-select the main X"): list every form that has the field. Default
  only on create, keep the saved value on edit, and keep any existing smarter default first (fall back to it).
  Ask whether list/report FILTERS are in scope too. Recommend no, because a pre-filtered report quietly hides other
  locations. Ask separately about OPTIONAL tag-style fields (e.g. the warehouse on an expense). Recommend no
  default there, since it labels every record with the main location unless someone clears it. On forms
  with two fields of that type (source/destination), ask which one to fill. Recommend source only.
  Before adding a server filter for the "main" flag, read each form's Model: if it already loads the
  full option list and each row carries the flag, pick the main one client-side in ONE shared hook
  (set once on create, only when the field is empty, never after the user clears it). Add a server
  filter only when a form gets a paged/searched list that may not contain the main record.
- **"Add column(s) X to report/list Y"** (column picker already exists): (1) find WHO builds the
  column list. A generic report page that renders whatever columns the server returns means a
  server-only change, and the picker, per-user hidden columns and Excel/print exports follow
  automatically; say so, since it sizes the ticket. (2) Find where the value is stored on the source
  row (often a snapshot column, plus a free-text or legacy fallback column for other variants or
  older rows) and grep the webapp for an existing label helper that already defines the fallback chain.
  Make the report use the SAME chain so report and screens never disagree. Don't copy a print-only
  fallback that would repeat a value already in a sibling column. (3) Ask as separate Q ids: which
  views get it (detail only, recommended, vs also new group-by views, which need their own
  totals/shipping rules), and whether it is shown or hidden by default (check whether the picker
  supports a default-hidden list before you offer it as free; when preferences store HIDDEN keys,
  a new column is automatically visible for every user, including those with saved preferences, so
  "shown" costs nothing and "hidden" needs a default-hidden mechanism). Filtering by the new column is its own
  scope item. (4) Mark the PDF/print width of the wider table ASSUMED until a real export is checked;
  have the worker save the export and report legibility (narrow columns wrapping mid-word = backlog
  row, not a blocker). (5) Acceptance fixtures: one row per variant, plus a row where BOTH sources of
  each fallback chain are set (plate + free text, current + legacy name), or a swapped-order mutant
  survives. Legacy-only columns the API no longer writes need a direct DB update fixture behind the
  suite's TEST_DB guard. Also assert grouped views do NOT get the column and `hiddenColumns=<keys>`
  still exports.
- **"Port X from the old app, but do it the way project Y does"**: build a THREE-column inventory
  (old app / reference project Y / target on `origin/main`) before any option. Grep each side for the
  mechanism's library and call sites (`package.json`, `git grep -l <lib> origin/main -- <src>`), and
  read the matching gap-audit docs (`docs/port-gap/**`), which list what is still missing. The target often
  already has part of X built the OLD way, so the job becomes "convert N existing + port the rest".
  Lead the reply with that finding. Run `git log origin/main -1 --format='%h %ad %an' -- <file>` per
  existing file: when another developer wrote them in the last days, ask a coordination Q (agree the
  method with them first, recommended, vs build in parallel on a branch), or you rewrite work they are
  still adding to. Also ask, as separate Q ids, what scope to convert (all existing + missing,
  recommended for one mechanism app-wide, vs missing-only, which leaves two mechanisms). Ask separately
  about old items with no backing entity in the target: recommend out of scope, each its own feature.
  Ask separately about items of a different kind (reports vs documents) that the reference handles
  another way.
- **"Build these N gap items"** (a list picked from a port-gap/audit table): follow
  `references/batch-discovery-fanout.md`. Always-on rules:
  (1) Before dispatching anything, re-check EACH item against the newest `origin/main` (`git fetch`,
  then `git log origin/main --since=<audit date> --format='%h %an %ad %s'` and a grep of the root
  `CHANGELOG.md` for the item's stem). Another developer often works the same gap list in parallel, so an
  item can land between the audit and the request. Mark it "already on main (who, commit)", keep only
  its leftover choices as Q rows, and add a coordination Q (tell that developer which items this branch
  takes, recommended) as Q0.
  (2) Have discovery state what the OLD feature actually DID (side effects, reachable UI, status
  guard), not what its name suggests. Gap rows named after an old field or endpoint often hide a
  different workflow ("reserved qty" = batch picking that moved stock; "manual SELESAI" = an API-only
  status with buggy side effects). Then offer "design the need" vs "rebuild the old flow" vs "nothing,
  today's flow already covers it" as options, rather than "port X".
  (3) Check that the feature has a SCREEN to live on: a print or upload for an entity whose frontend
  tab was never built needs that tab as a prerequisite Q, even when a knowledge doc claims it exists.
  (4) Present the answers as: findings that change the plan first, then only the scope-changing Qs
  in one short table, then every other Q in one compact table grouped by feature with the
  recommended option only, ending with "answer *all recommended* or list exceptions (`Q10 b`)".
  A 30+ Q batch in the full options format does not get read; the full options live in `spec.md`.
- **Ported data rejected by a new-system rule** ("in the old app users worked around X by typing it
  twice / at price 0, now the migrated document cannot be invoiced"): (1) Read the port script's insert
  for those rows to learn the stored SHAPE (one merged line vs the legacy lines copied 1:1); mark it
  ASSUMED until one real document is checked, and ask the user for one document number. (2) Give a
  table per possible shape: which guard rejects it (`file:line`) and the error text the user sees;
  integrity guards added recently (duplicate-row, price floor) are the usual cause. (3) Grep the other
  modules for the concept already built under another name (a POS free-item line, a promo kind) and
  name it as the template. (4) Options: an immediate no-code workaround for today's documents first
  (with the case it does not cover), then permanent fixes, recommended first. (5) The permanent fix
  gets its own Q for how the backfill recognizes the old workaround rows (a narrow pattern,
  recommended, vs every row that looks similar, vs manual), since a broad match converts real
  mistakes too.
- When the user accepts a recommended option but changes one part of it ("a, but follow the order
  quantity, not the delivered one"), do not shrink the qualifier to the new feature's lines: ask
  yourself whether it is a document-wide rule (how the WHOLE invoice is billed) or a carve-out for the
  new thing only, and default to the wider reading, since users state their business rule, not a
  feature exception. Record it as the user's decision and every rule you inferred around it as "PM
  reading — confirm", confirmed with one worked example ("SO 200+13, 150 delivered → invoice shows
  ...") before any ticket. Then grep the settings enum/seed payload for a toggle that already
  implements the rule (`git grep -n -i '<concept>' origin/main -- src/modules/setting src/seeders`) and
  offer "use the existing per-tenant setting" as option a before any new rule; note which tenants
  have it ON is unverified until checked.
- Before you offer or cite a base branch ("new branch from main"), find the branch features integrate
  into: `git log --merges --oneline -5 origin/develop` (feature merges land there?) and
  `git rev-list --count origin/main..origin/develop`. If develop is ahead, it is the base: discovery
  cites, the base-branch Q option, worktrees and baseline all come from it. Verifying on `main` while
  features merge to develop gives stale cites and a base option that conflicts on merge; a
  confirmed base Q built on that must be VOIDed and re-asked.
- When the current checkout is another feature's branch or has uncommitted work, still verify against the
  branch the feature will start from, without switching: `git show <base>:<path> | sed -n 'a,bp'` and
  `git grep -n <pattern> <base> -- <paths>`. Cite those lines. Behaviour on a WIP branch is not the base.
- "Explain option X to me" on an edge-case decision: answer with (1) how the rule works today, with
  the cited function; (2) a dated timeline table of the failing scenario; (3) what goes wrong per
  branch (e.g. per purpose/type) and what the user sees; (4) the options table with consequence,
  recommended first; (5) the ONE yes/no question that decides it. Abstract rule talk alone does not
  land; the timeline does.
- Ask ONE decision per numbered question. Bundling sub-questions (6a/6b/6c) into one Q invites a one-word
  answer that covers only part of it; if that happens, say which part you applied the answer to and
  re-ask the rest as new Q ids. When a short answer could fit two open questions ("when X happens"
  answering both WHEN and HOW-FAR-BACK), record your reading in the spec marked "PM reading — confirm",
  keep the default for the other one, and ask the user to confirm with a concrete example.
- A requirement such as "users whose role is X" needs a marker the code can query. Check whether roles
  are per tenant and what columns Role/User actually have. Then offer the options: a flag on Role
  (recommended), a flag on User, or a role-name match (fragile when the role is renamed).
- When the user trims a decision ("skip X for now"), state the consequence it has on the rest of the
  design (which figure becomes approximate, which label must change) and record it in the spec under the
  decision, before tickets.
- Search the knowledge docs, ADRs, specs and code comments for the feature name and its synonyms
  (including local-language names, entity names, enum members). Example:
  `grep -rniE 'refund|chargeback' docs/ src/ --include=*.md --include=*.ts`.
- Read every hit in full context (at least 10 lines around it), not just the match line.
- List each recorded intention as a VERIFIED fact with its citation ("design-v9 §8: refunds go through
  the approval step").
- A recommendation against a recorded decision must say so explicitly: "This contradicts <doc:line>,
  which says X. I recommend Y because Z." Never contradict silently.

## 2. Verify current behavior, not memory
- Read ONE file per numbered read. Never `cat -n a b c` (line numbering runs across files).
- Before writing the answer, re-open every `file:line` you cite and confirm the line says what you claim.
  A cite that lands on the wrong line is a false VERIFIED claim, even if the fact is true.

## 3. Define shape by an existing template
- Before proposing a new entity, status machine or flow, search the repo for an existing one with the
  same SHAPE (header + derived status, document → approval → confirm, reserve → convert, post-commit side
  effect). Name it in the design: "follows <file:line>". Inventing a parallel pattern when one exists is
  a design defect.
- When the template exists in two mirrored copies (customer and supplier versions of one document),
  diff their controllers and services before naming one. Mirrors drift: one side may skip row-level
  access checks on list/detail/void, or a ledger posting. Name the complete one as the pattern for
  BOTH new sides, and list the gaps of the other as a backlog row, not something to copy.

## 4. Scope is the user's call
These are business scope, so they go to the user as options even when one answer looks obvious:
- New document/entity vs extending an existing one.
- Which locations, roles, item types, or modules are in or out.
- Granularity the user will see: partial vs all-or-nothing completion, one permission vs several.
- What happens to related records when this one is cancelled, denied or corrected.
Give your recommendation first, with its consequence; do not decide it in "technical decisions".
A bare "sure"/"go" is not confirmation — restate the option you took before acting.

## 4a. New payment/settlement method (write-off, rounding, "discount to clear the rest")
- Pin the MEANING before the design: ask or restate whether it is a commercial discount (changes the
  document total/tax) or a write-off of a leftover (settles only, total and tax unchanged). Recommend
  settle-only; changing an issued total changes tax figures. When the user reframes it ("it's rounding,
  not a discount"), redo the name and the guard questions, not just the label.
- Name test: read the proposed label on EVERY side it will apply to. A cost word ("Biaya ...") is true
  for sales (we receive less) and false for purchases (we pay less = gain); recommend a neutral name
  ("Pembulatan") when both sides are in scope.
- A one-click "settle the remainder" action needs a VALUE guard, not only a permission, or one click
  writes off any amount. Offer as options: a per-company maximum setting (recommended, with a default),
  hard-coded max, none. Then the technical rules: the write-off must equal the WHOLE remainder (no partial =
  no discount in disguise), the cap is cumulative per document (cancel + redo cannot exceed it), the
  button shows only when 0 < remainder ≤ cap, and the server computes the amount (the button sends none).
- Ask up front, as its own Q: may the write-off close a document with NO real payment yet? Recommend
  "only after at least one live non-write-off payment": otherwise any document whose whole total is
  under the cap becomes a one-click free document. The guard check order is: nothing left → no real payment → not
  the whole remainder → over the cap.
- A new numeric setting that feeds a guard needs validation on the settings save (finite number ≥ 0):
  a free-form settings store saves "abc", which then reads as 0 and silently switches the feature off.
- Grep consumers that pick "the latest payment" (payment-received messages, previews, receipts): they
  must skip the no-money method, or a re-send shows the write-off (Rp 0,50) as the payment received.
- Copy the existing no-money method (an advance/deposit usage): no cash/bank movement, no payment detail
  fields, excluded from cash flow, still listed in payment reports with its label, no "payment received"
  notification. Grep every column typed by the shared payment-method enum (deposits, refunds, bulk
  headers): the new member is accepted there too unless each create refuses it.
- Before telling the user who can edit a new setting ("superadmin"), read the settings controller
  guard: most settings follow a grantable permission and only a few are owner-only. State it as an
  option (O-id), not a fact.
- Bulk settlement with "also write off the leftovers": the user picks the documents to write off one
  by one (a per-row checkbox in the bulk table, none ticked by default; the create body carries an
  explicit `<x>InvoiceIds` list that must be a subset of the paid ids, else 400). Do not offer one
  global "write off all leftovers" flag: users cannot exclude a document and are confused by which
  ones the system rounded. A picked document that is not eligible at save refuses the WHOLE save with
  one 400 naming every refused document and its reason (what the user saw = what is saved); never
  skip it silently. **Tick first, amount follows** (the shape users accept; recommend it at the
  first grill): a box is tickable from the moment the document is selected, decided from document
  inputs only (unit, cap incl. earlier write-offs, paid-before rule), never from the payment
  amount; on tick the write-off shows at once and the payment amount auto-fills to Σ targets of
  ticked + Σ remainders of unticked (still editable). An amount too small for the ticked documents
  refuses the save with one message naming the shortfall ("Jumlah bayar kurang Rp X untuk faktur
  yang dibulatkan"), never a silent un-rounding. Money-dependent eligibility (box enabled only when
  the preview's money reaches the document, ticks shown muted as "not counted at this amount") was
  built first and users rejected it twice as "my tick reset" / "why can't I round this".
  A tick is the user's intent: keep it while the document stays selected (clear it only on untick,
  unselect, unselect-all, contact change); a ticked box is always untickable. Never prune ticks
  from preview results: a debounced preview also fires on mid-typing values ("2", "20", "200"
  while typing 2000), so pruning wipes ticks. Derive the sent set per render, not in an effect;
  the preview must work with an empty amount (amount optional on preview only) and list every
  selected row in write-off mode; a failing preview must not lock the form (the user can still
  untick, and "pay all" fills the full outstanding). Auto-fill reads the CURRENT preview's
  per-row target and reason (a document that turned over-cap since the tick contributes its full
  remainder and shows why); targets stored at tick time are only a fallback before the first
  preview, or the form underpays it silently. Do not disable the other boxes while a preview
  loads: tickability is inputs-only and already known, so quick successive ticks settle into one
  preview; only Save waits for a current preview. A ticked document still short of money shows
  its write-off muted with "applied once the amount is enough", not as a normal value.
  When a user reports a reset/vanishing UI state, first say whether it is the approved rule or a
  bug, trace the transient states (debounce, loading, error) in the code, and offer the rule
  change as options before any fix round. One write-off payment PER picked document, linked to
  the bulk (no allocation row, bulk total and bank movement unchanged), built from explicit fields,
  never by spreading the bulk header DTO (that copies bank, reference and detail fields onto a
  no-money row). Voiding the bulk cancels them too. Spec eligibility as a NON-throwing function that
  returns the refusal REASON and shares its maths and message texts with the throwing guard, so
  preview, bulk refusal and single-document guard never disagree.
  When an explicit pick list replaces an implicit set ("every allocated document that received money
  in this bulk"), restate each filter the implicit set applied as its own spec rule or Q (may a picked
  document that gets NO money from this bulk but was paid earlier be written off?): the subset check
  against the paid ids alone silently widens eligibility. In the brief, convert every existing test
  that asserted the silent skip into BOTH paths (picked -> 400 + nothing written, not picked -> 201 +
  no write-off), and note that an allocation run fully pays every document except the last, so a
  fixture with several eligible tails needs prior partial payments on the others.
  Adding such a guard ahead of an existing one changes which refusal text users see (a never-paid
  pick now gets the new message, not the old "no real payment" one): read the worker's report for
  moved expectations and tell the user which message changed, on which path, and that the
  single-document path keeps the old one.
- Per-row write-off over a SEQUENTIAL allocator (fill each document fully, in order): only the
  last document the money reaches can ever have a tail, so ticks on the others never count and
  users see "n ticked but not counted". At grill time, ask how a tick shapes the allocation:
  "write off first, then allocate" (a ticked document's money target = remainder floored to a
  unit; ask the unit with a worked example, since users mean "drop the hundreds", not cents;
  ask separately whether the cap setting is only a cap or also the unit, recommending cap only),
  what happens when money is short of a target (recommend: refuse the save naming the shortfall,
  per "tick first, amount follows" above) or above the sum of targets (recommend: while any tick
  counts, cap the amount at the auto-fill value, Σ targets + Σ other remainders, and refuse more
  with "lepas centang Bulatkan untuk membayar penuh"; users read an editable amount that silently
  shrinks their write-off as a bug, so a "surplus fills ticked tails" pass and its "paid by surplus"
  reason code should not be built), whether documents whose remainder is under one unit
  (1, 10, 999) may be ticked, and whether a tick counts while another selected document stays
  unpaid. For the under-unit Q recommend "yes, when the document already had a real payment
  before this bulk" (target 0: it gets no bulk money, only surplus may reach it, and the whole
  remainder is written off within the cap). Users expect any small leftover to be roundable and
  push back hard on "remainder below the unit cannot be ticked". Never-paid stays blocked, so a
  small document cannot close for free. The spec must then waive "a ticked document must receive
  money from this bulk" for exactly these documents. The preview must also list a zero-money row
  that is tickable, or its box can never be ticked. Create must still record the write-off for a
  document in the bulk with 0 money and no allocation row. Grep every screen that reads the bulk
  back (detail page, print) for a payment→document lookup built from the ALLOCATIONS: a 0-money
  document has none, so it shows the payment number and no document link. Make the detail read
  return each payment's own document (id + number, joined in the same query), with the
  allocation lookup as a fallback, and ship it in the same release. Note also in the release note
  that a bulk whose total must be > 0 cannot write off old remainders alone; the single-document
  write-off covers that case. Do not answer the user's numbers from
  the spec summary: walk them through the real allocator first (a read-only preview call on the
  QA backend proves it). Then require in the spec, because each one otherwise breaks silently:
  - Decide which ticks COUNT before allocating, from inputs only (target > 0, tail > 0,
    earlier write-offs + tail <= cap); a non-counting tick allocates as unticked. If the client
    sends only the eligible ticks and eligibility is decided after allocating, create re-plans
    with fewer ticks and saves a different split than the preview showed.
  - Preview takes ALL ticks and returns per row amount, write-off, "possible" write-off and a
    reason code; the webapp shows the server's split (a client-side allocator copy goes stale).
    Spec the reason code for EVERY selected row, ticked or not: a contract that only explains
    ticked rows leaves a disabled unticked box with one generic tooltip, and the webapp worker
    either guesses the reason client-side or asks for another server round. Give each distinct
    cause its own code ("tail is an exact multiple" vs "surplus already paid the tail"): one
    shared code makes the create refusal text wrong for one of the two.
  - Create sends `{id, amount}` per write-off and refuses any mismatch with its own re-plan
    ("data changed"), so a payment voided between preview and save cannot widen the write-off.
  - Targets in integer cents; the plain allocator stays byte-identical for its other callers.
  Red-team this design with a fresh reviewer before the build brief, since it moves money. Put
  any eligibility patch you think of meanwhile into the red-team's questions, not into the brief:
  a post-allocation patch ("treat a cap-refused tick as unticked") is circular, because surplus
  money shrinks the tail back under the cap. Fold the red-team's business findings into ONE
  clarify form, each with a worked numeric example; a free-text answer that matches no option
  ("just the hundreds") gets a follow-up form whose options restate it on one example amount.
  Gate mutations for this rule: set the rounding unit constant to 1 (the target rule must fail),
  disable the create-vs-plan amount check (the "data changed" cases must fail), for the
  under-unit waiver restore the plain "must receive bulk money" check (the remainder-1 cases
  must fail), for tick-first disable the shortfall refusal (`if (plan.shortfall > 0)` ->
  `if (false)`; the short-amount cases must fail), and for the amount cap disable the over-need
  refusal (the "above auto-fill" cases must fail).
  Spec ONE money-text rule for the bulk page AND its server messages before the webapp brief:
  whole amounts without decimals ("Rp 2.000"), otherwise exactly two ("Rp 2.500,50", "Rp 0,01")
  (`Intl.NumberFormat('id-ID', {minimumFractionDigits: 2, maximumFractionDigits: 2,
  trailingZeroDisplay: 'stripIfInteger'})`), as a NEW helper on each side; report formatters and
  shared helpers other pages use stay untouched. A whole-rupiah helper prints a 0,01 shortfall as
  "Rp 0" and a 500,50 cell as "Rp 501" (the column then visibly adds up to more than the cap in
  the alert), and a max-2-decimals formatter prints "Rp 2.500,5".
  With the amount cap, grep every label on the page that presents a "what to pay" figure (the
  hint under the amount field, summaries above the table) and spec it for the ticked state:
  "Total setelah pembulatan: Rp X (sisa tagihan Rp Y, dibulatkan Rp Z)". A hint that keeps
  showing the full outstanding next to a lower cap reads as a contradiction to the user.
  Save must also require that the latest preview request is not in error: a query hook keeps the
  last cached success after a failed refetch, so Save stays enabled under the red alert with a
  stale plan (the server re-plan refuses it, but the form should not offer it).
  A read-only probe of the preview must send the same mode flags the webapp sends (e.g. the
  write-off flag besides the tick list): without them the server answers in the plain mode (no
  rows for 0-money documents, no target fields) and the probe "shows" a bug that is not there.
  Read the webapp's request builder before writing the probe.
  Define the shortfall X as the extra money that makes the save pass: X = R − amount, where R =
  Σ in allocation order, up to and including the last ticked document with a target > 0, of
  target (ticked) or full remainder (unticked). "Σ (target − money) over ticked rows" understates X
  whenever an unticked document sits before a ticked one (money drains into it first), so a user
  who adds X is refused again. Spec it with a three-document mixed-order example (ticked,
  unticked, ticked) and require a property test "amount + X always clears the shortfall" in both
  allocation modes.
  QA fixtures and probes use the USER's own example amounts, in whole rupiah unless the user
  speaks in cents ("1.001" means 1001.00, not 1000.50). A fixture with odd cents makes every
  screen show a write-off like 0,50 where the user expects 1, and the user reads it as the rule
  being wrong. When a user disputes a figure, first check the fixture values in the DB, then
  rerun the read-only preview on corrected data before touching the rule. Before writing
  the gate script, `ls test/api` for the exact suite file names (e.g. the refund suite's full
  stem). A misspelt suite name is silently skipped, and the gate looks green without it.
  Derive the next round's gate by copying the last one with new run/DB names (sed on the
  script), so every round runs the same suites and mutations. Build the gate's copied-file list
  from `git status --short` of the worktree at run time, never a hard-coded list: a ticket that
  adds or first touches a file (a new format helper) leaves the gate copy without it, tsc fails on
  the missing export and every suite reports 0/0 for a reason that is not the code. Before running the copy, grep the
  current source for each mutant's anchor line: when the new ticket removed or rewrote the guarded
  code, the sed silently matches nothing (`applied=0`) and that mutant "passes" while testing
  nothing. Replace it with a mutant on the new ticket's main rule, and read every `applied=` line
  in the summary before quoting the mutation result. `applied=1` is not enough either: a mutant
  must still typecheck. Replacing a guard that also narrows a type (`if (plan.maxAmount !== null &&
  plan.unallocated > 0)` -> `if (false)`) fails the build, the backend never starts and the suite
  logs `PASS=0 FAIL=0` (a connection error), which is not a caught mutant. Weaken only the business
  half and keep the narrowing (`plan.unallocated > 1e12`); treat any mutant run with 0 PASS as
  broken, read its build log, and re-run just that mutant.
- Replacing a request field (flag -> id list) with the validation pipe on `whitelist: true,
  forbidNonWhitelisted: false`: an old browser bundle still sending the old field gets it stripped
  and the action silently does nothing (no error). Read `main.ts` before the spec. Default (PM
  technical): keep the old field on the write DTO only to REFUSE it (`true` -> 400 "page updated,
  reload and pick again") so a cached bundle fails loudly instead of saving without the side effect;
  assert that 400 + nothing written in the suite. Still record "deploy server + webapp together".
- A "take the whole remainder" sentinel amount (so the server computes it once under the lock) must
  be refused for any other method and for a resolved amount ≤ 0, or a later caller pairing it with a
  money method writes a zero/negative payment. Check the public payment DTO rejects the sentinel.
- Base branch lacks another unmerged branch's change to the same rule (e.g. "what is still owed"
  now subtracts returns there): make the new guard read the remainder from the SAME helper the existing
  cap uses, so the later merge swaps one function, and record a merge note in the spec and the board.

## 5. Follow corrections downstream
For every rule of the form "no undo", "immutable once X", "corrected by a new document", "cancelled by Y":
- List every report, total, balance, journal and status that reads the original record.
- For each one, say whether the correction flows into it. If not, it is a risk: the number is wrong
  until someone nets it out by hand. Put it in the risks section or ask the user.

## 5a. Attack the design against the code before tickets
For every value, link or lock the design depends on, read where it really comes from. These cheap
checks are the ones a red-team turns into blockers:
- **Input really sent?** A DTO field being optional says nothing about whether the UI sends it on that
  transition. Grep the form/modal for the field and the condition that shows it. A design that
  reads a reading the UI only collects on one step gets null or a stale carried-over value elsewhere.
- **Link really set?** For a FK the design joins through (e.g. a TSR's contract vehicle), find
  every writer. If the only source is a client prefill, totals built on that join are close to zero.
  Offer "server derives and validates it" as an option.
- **Delete hard or soft?** Check the delete call (`remove` vs soft delete) before adding a reference
  to that row. A hard delete plus a new FK breaks the delete; with no FK it leaves dangling rows.
  Specify the cleanup. Include bulk paths that hard-delete DEAD rows (an import revert removing the
  batch's cancelled documents): a new money-history table pointing at them (allocations of a voided
  payment) turns that revert into a generic FK error. Keep the FK RESTRICT (never CASCADE money
  history away) and make the revert refuse up front with a message naming the history, like its
  existing "has payment history" check.
- **Backfill reaches every writer?** A migration backfill (e.g. "existing rows = already settled")
  only touches rows that exist when it runs. Grep for raw-SQL inserters of the table (legacy port,
  import, seed scripts): a port that runs on a fresh DB AFTER all migrations writes the column
  default, so its rows silently get the new-row meaning. Set the column explicitly in those inserts.
- **Transaction really there?** Before putting a row lock in a shared helper, trace each caller up
  to the controller. A service that opens and commits its own transaction, then runs follow-up
  writes with no manager, gives the helper no transaction (TypeORM throws on pessimistic locks).
- **Second connection on a locked row?** A row lock taken inside a transaction, followed by a call that
  opens its OWN transaction and updates the same row, waits on itself forever. Postgres cannot detect
  that. Pass the manager through, or order the call before the lock.
- **Meaning or unit change?** When a decision changes what an existing column holds (meter hours →
  clock hours), put the label change and the screens that show it into the decision's consequence
  and the frontend ticket.
- **Same source in two totals?** When a decision feeds one source into two stored totals on purpose
  (repair hours in both maintenance and uncountable), write "never add these two" on the columns and
  in the spec, and have the reviewer grep every backend/frontend consumer that sums or charts both:
  one tile adding them double-counts silently.
- **Category skipped by a total?** When a recompute skips a category (a fixed-price contract type),
  check that every report listing the same source rows applies the same skip; otherwise the report
  and the total disagree for that category. Fix it or record it as a decision row with options.
- **Right trigger event?** Before hanging a side effect (a record, a count, a total) on a document's
  create, check what the document IS: a quotation or request that can still be rejected or deleted
  (TSR → APPROVED / REJECTED / CANCELLED) is the wrong trigger. Use the event where the work becomes
  real (the approval that generates the work order), and take the event TIME from the earlier
  document when it matters (breakdown time = request created). Rejected quotes then never count and
  no delete cleanup is needed.
- **Link window across an ownership change?** A rule "attach the open record from the last N days"
  can cross an owner boundary (the unit moved to another contract, a slot got a new occupant). Ask
  which owner the attached value counts against, as options (link only within the same owner,
  recommended; link and keep the old owner; link and move it). The cross-owner case is invisible in
  happy-path tests and decides whose total carries the hours.
- **Window anchored on the right document?** A "link the open record from the last N days" rule
  measured from the NEW request misses a record whose earlier request was rejected/cancelled after
  the window passed, and the next request then writes a duplicate record (or links nothing). When
  dead links can be replaced, ask where the window anchors (the dead request's date, recommended:
  one record, downtime from the original event; no window for such records; leave it), and say
  whether the dead request's pending days then count. Then attack the reopened record itself:
  anchoring on the dead request leaves it open FOREVER (its event is always just before that
  request), so any later routine request takes it and books months of fake duration. Bound the
  takeover on both sides of the time the link died (died <= new request <= died + N, died time from
  status history, row `updatedAt` as fallback) and keep the explicit user pick unbounded.
- **Dead link via a child document?** A request can stay APPROVED while the work it spawned is
  cancelled (TSR approved, work order cancelled). List every terminal "nothing was done" state,
  parent AND child, as one shared dead-link definition used by every linker; check each state is
  terminal (no outgoing transition) so reading it under the occupant lock is safe.
- **Recompute every owner the event feeds?** When an explicit link may attach a record of a previous
  owner (unit moved, returned, swapped), the completing event must recompute the total of each
  linked record's owner, not only the request's own owner; lock them in ascending id order.
- **Slot id vs occupant?** An assignment row that keeps its id when the occupant changes (a vehicle
  swap keeps the contract-vehicle row) is not an occupant key. Any "reuse / attach the open record of
  this slot" rule must also match the occupant, or the new occupant's event overwrites the old one's
  record. Put a swap-then-event case in the acceptance tests.
- **Total built from a stamped timestamp?** When a new total reads a timestamp an endpoint stamps
  (repair end at QC approve), check the endpoint re-checks the source status under a row lock: an
  endpoint that only validates the requested decision lets a repeat call re-stamp it, and the total
  silently grows. Add the guard to the ticket.
- **Write designed out instead of ordered?** When a transition only fed a shared total by increment
  and the total can be recomputed at the later event that actually changes it, drop the write from
  the transition: a transaction that no longer touches the row cannot deadlock or self-wait on it.
  Prefer that over a lock-order rule plus a timeout test.
- **Legacy guess beside a new link?** When a report keeps a heuristic join for rows written before
  an explicit link column existed, the heuristic must skip targets another row already owns, or one
  target shows on two rows.
- **Two rules shrinking one amount?** When one rule lowers what a document bills (invoiceable qty =
  delivered − returned) and another deducts the same event afterwards (bind the earlier return to the
  new invoice and deduct its value), the units are taken off twice. Write ONE formula both paths and
  the backfill use, per source line: deductible qty = `min(R, max(0, I − (D − R)))` (D delivered,
  R returned, I invoiced); a pre-document event binds with deduction 0.
- **Lines split across parents, header keeps one FK?** When a design lets one document's lines point
  at several parent documents (a return restocked through several delivery notes) but the header keeps
  a single parent FK, every existing guard and cap that reads the header FK (un-verify, void, date move,
  returned-so-far totals, import revert) misses the other parents and lets stock be corrupted. Move
  those checks to item level (`item -> parent line -> parent`) and test with a 2-parent split.
- **Shared TS enum over several PG enum types?** One TS enum can back several DB enum types (customer
  and supplier ledgers). A new member needs `ADD VALUE IF NOT EXISTS` on EVERY mapped type, or the
  schema check drifts; put it in its own migration, because Postgres cannot use a new enum value in
  the transaction that adds it.
- **Removing a merged-but-undeployed feature?** Keep migration files some DB may already have run
  when they only add enum values (they cannot be dropped; deleting the file makes fresh and old DBs
  differ); keep the TS members `@deprecated`, drop them from seed payloads, and delete their rows in a
  new migration. Drop its tables in an idempotent `IF EXISTS` migration that RAISEs while live money
  rows exist (active payouts with real cash-ledger rows), naming the count, so history is never
  silently destroyed; add the deploy order (void them with the old version first) to the release note.
  The global migration that deletes the permission rows runs BEFORE the tenant ones, so it needs its
  own cross-tenant refusal up front (see the settlements-and-credits reference of `derived-totals-design`).
- **Same item allowed twice on one document?** (a paid line + a free/bonus line of one product) Any
  code keyed by `productId[:unitId]` instead of the line id now breaks. Check, with cites: (1) edit
  paths that pair stored lines with submitted ones by product key (lines swap values). Ask whether the
  flag may change once a child document exists. If it may, key pairing cannot work: from the payload
  alone "flip both flags" and "swap the two quantities" look identical, so a key-based pass refuses
  legal flips or pairs the delivered line with the wrong row. Specify pairing by LINE ID: the edit DTO
  takes an optional `id` per line (check the webapp edit form already holds it, so it only has to send
  it), an id must belong to this document and appear once (else 400), the id is never used as the PK
  of a new row, and a row whose product/unit differs from the line its id names is NOT paired (400
  when that line has an active child document, otherwise remove + new line, so voided child rows never
  show another product). Rows without an id fall back to key pairing (exact key incl. flag first, then
  without the flag; delivered lines first; skip a candidate below the delivered qty instead of
  throwing). Log every flag flip in the document history. Mutants: id ignored, duplicate-id guard
  removed, changed-product row paired anyway; (2) duplicate-row
  guards (widen the key with the flag, server AND webapp rule, plus React keys); (3) the price
  pipeline ORDER: a step that clears/refills the list price or runs list-price and floor checks runs
  before your "force 0" unless you put it first, so force price/discount 0 up front and exclude the
  line from every price-policy check; (4) header-discount rounding remainders that land on the last
  line (give them to the last line with net > 0); (5) per-quantity payouts (commission) that ignore
  price; (6) data-port scripts that matched child lines (deliveries, invoice lines, returns) to parent
  lines by product: ported data may already sit on the wrong line, so specify read-only SQL checks
  before the backfill. A port-script fix may only change documents that HAVE the new pattern (a paid +
  free pair of one product); every other document must port exactly as before. Port scripts have no
  tests and must not run against a DB, so require an equivalence proof in the brief: extract old and new
  matching code as pure functions, run both in node on tens of thousands of random fake transactions,
  and report 0 differences on documents without the pattern (a heuristic such as "prefer the line whose
  quantity equals the planned quantity" silently re-matches ordinary two-line documents otherwise); (7) the backfill scope (only ported documents, guarded by `to_regclass` when the
  port's mapping table exists only on ported tenants) and its idempotent WHERE; (8) every OTHER
  writer of such lines (quotation → order copy, recurring templates, spreadsheet import) as one scope
  Q, since a flag only the order form can set is lost on every copy path; and every progress/picker
  endpoint that lists those lines for a child form (delivery, invoice AND return progress) must return
  the flag, or the child form shows two identical rows; (9) a cap rule a per-tenant
  setting switches (bill delivered vs ordered qty) plus "one active invoice per order": with the
  setting off, lines delivered after the invoice are never billed and their cost never booked, so ask
  whether the setting becomes a requirement for tenants using the feature; (10) the edit-time stock
  check: growth computed per LINE refuses legal edits once a product has two lines (re-splitting
  paid 200 + bonus 13 into 190 + 23, or a unit change at equal base qty, reads as +10 with stock at 0).
  Specify growth NET per product in base units: sum(submitted lines) − sum(ALL stored lines, removed
  and replaced ones included), checked only where > 0, computed before the pairing copies new values
  onto the stored entities (the "previous lines" array points at those same objects). Test it with
  stock set to exactly the order quantity; mutants: stored lines left out of the net, growth never
  checked; (11) documents whose total can now be 0 (an all-free invoice, no shipping): grep the shared
  payment-status rule (`paid <= 0 -> UNPAID` before `paid >= total`) and the minimum payment amount.
  A 0-total document then stays "unpaid" forever, gets due-date reminders and sits in unpaid lists.
  Ask it as its own Q (count total <= 0 as paid, recommended; leave it; refuse a 0-total document),
  naming the other 0-total cases the rule also changes (100% discount). Before placing the rule, grep
  every caller of the shared status helper and ask what a 0 total MEANS in each domain: in purchasing a
  Rp 0 invoice is "price not verified yet" (a price-verification queue lists only UNPAID 0-price
  invoices), so a shared "0 = PAID" hides it from that queue and leaves real debt marked paid after
  repricing. Put the rule in the domain's own status util and keep the shared helper byte-identical
  (`git diff --quiet HEAD -- <shared util>` in the gate). Also list every place the status is hard-coded
  at creation (service create, import, other modules) and every UI button gated on the old status
  (cancel / change date shown only for UNPAID), or the server allows an action no screen offers.
- **A line flag decided on the CHILD document too?** ("set bonus on the invoice, not only on the
  order") The flag lives on the parent line today and every reader follows `child.parentLine.flag`.
  Specify: (1) a column on the child line, migration backfill copied from the parent line (old
  documents keep their meaning), and EVERY writer that bypasses the create DTO setting it explicitly:
  raw-SQL inserters (port scripts, which run after migrations and write the default) AND services
  that build child entities directly (spreadsheet import), which never see the DTO default below; (2) DTO field optional, OMITTED = the
  parent's flag, so imports, recurring generators and an old browser bundle keep today's behaviour;
  (3) one parent line may become at most one child line per flag value: widen the duplicate key to
  `parentLineId + flag` and check the quantity cap on the SUM of the split lines, never per line;
  (4) free = the child line's flag, forced before any price check; a parent-free line billed as paid
  goes through the normal price rules (and needs a price source, a Q). Its parent price is 0, so a
  "price differs from the order" variance note would be false: log the flip itself in the history
  instead ("order bonus billed: <product> <qty>" / "billed as bonus: ..."). Ask separately what a
  PAID child line at price 0 means (accept as today, recommended; refuse "mark it bonus"; silently
  convert), since the flag now gives users a second way to say "free"; (5) switch only readers whose
  row IS a child line (child PDF, child-line reports, returns per child line); parent views keep the
  parent flag, so say in the Q that the parent will not show a flag set later; (6) anything that caps
  per child line against a parent-level pool (returns against shipped qty of the parent line) must
  share that pool across the split lines inside ONE request, or one request over-draws it; and the
  per-line cap check must re-read the pool's remaining after earlier lines' slices, else the cap
  passes on a stale figure and the slicer throws a plain Error (500 instead of a 400 message).
  Before the brief, resolve the flag IN PLACE on every submitted line (explicit value, else parent's)
  so free-forcing, duplicate key, cap and price checks all read the same value; a Q22-style prefill
  for a parent-free line billed as paid needs a server price field (the parent price is 0). Ask the
  direction rule as its own Q (child may only add the flag, recommended, vs both ways).
  Webapp brief for the split: a flag switch per child row plus a per-row "add the opposite-flag
  row" button (shown only while the parent line has one row); with two rows lock both switches so
  two rows can never share a flag; flipping refills the row's starting price (parent price, or the
  server list price for a parent-free line) so a paid row never keeps a leftover 0 silently (warn,
  do not block, when that price is itself 0); the cap validator sums the sibling row and re-runs
  after a sibling edit or removal; form row keys and every detail/report table key are the CHILD
  line id (the parent line id collides on a split); parent-level figures (ordered, delivered,
  variance) show once per parent line, not on both rows; send the flag explicitly on every row.
- **"Block action X while Y" as an option?** Before recommending a refusal guard, check whether X
  is how users correct a mistake (delete / reduce / cancel of a wrongly typed document) and read the
  guard of the follow-up action the block is meant to protect (can a new document still be made
  from the freed amount?). State the harm from that cite in the option, not from the rule's name: a
  harm overstated as "can never be used again" gets a block approved, built, reviewed, and then
  dropped once the user names the correction case. When the only harm is a status shown early,
  recommend leaving it and record the side effect as a known risk.
- **Who actually gets a new permission?** Seeding a permission code usually grants it to Admin
  only; every other role sees the new action disappear (an edit/delete button nobody can use). Ask
  it as its own Q before the seed ticket, recommended first: deploy-day SQL granting it to every
  role that holds the sibling permission (CREATE_X -> UPDATE_X/DELETE_X), vs Admin-only with manual
  grants. Also diff the permission enum against the seed payload: codes with no seed row are given
  to nobody, not even Admin.
- **Same concept on a parallel branch?** Before the spec, list unmerged remote branches
  (`git branch -r --no-merged origin/main`) and grep each for the entity/column the design adds
  (`git grep -n <column> <branch> -- <paths>`). Another feature adding the same link column with a
  different rule (link at request create vs at approval) is a business clash that otherwise only
  surfaces as a 13-file merge conflict after both are built; raise it as options up front.

## 5b. Protect existing data (standing user rule)
Every spec that adds or removes columns gets an explicit "existing data" decision row:
- New columns are NULLABLE with no backfill; old rows keep their old values and old columns are not
  rewritten.
- "Required" rules are enforced in the service at the step that needs them, never as DB NOT NULL/CHECK
  constraints, so legacy rows stay valid.
- Before dropping a master-data column, confirm every document that shows it holds its own snapshot copy
  (grep the snapshot assignment), so printed history does not change; the migration `down()` re-adds the
  column nullable.
- Adding payment/settlement tracking to an amount that already exists (a refund, a fee) changes how OLD
  rows read: with no payments they all show as unpaid and land in the new "to pay" list. First check how
  reports treat the amount today (e.g. a cash-flow report counting every refund as paid on its own date).
  If they treat it as settled, ask the user and recommend a `settledOutside` flag that the migration sets on
  existing rows. Old rows then keep today's report line, and new rows move to the payment date. Derive paid
  status from the payments of ACTIVE settlement documents, never store it.
- Migration timestamps sort above the newest migration on ANY active branch, including uncommitted ones
  in the working tree, so the features merge in either order. Check the other branches' migration dirs
  (`git ls-tree --name-only <branch> <migrations dir>` plus the user's working tree) and leave a clear gap
  (jump the next prefix block) rather than taking base-newest + 1, which the other branch often already
  used. Put the exact number in the brief.

## 6. Label every claim verified or assumed
Every fact about the system in your answer is labeled VERIFIED (cite file:line) or ASSUMED (say what
would confirm it). Never present an assumption as a fact. On any feature touching money, stock, or data
migration, have a fresh reviewer re-read the plan before you hand it to a developer.

## 6a. Client-facing questions (user relays them to the client)
When the user says "I need to ask the client", turn the open Q ids into ONE ready-to-paste message:
Indonesian, WhatsApp formatting (`*bold*` headings, `_italic_` for "(saran kami)"), numbered questions,
a/b/c options with the recommended one first and marked _(saran kami)_, one worked rupiah example where a
money rule is involved, no code/entity/file names, and a closing line giving a short reply format
(`1 ok, 2 ok, 3a, 4a`). Keep the Q-id mapping in the spec ("OPEN (asked client)") so the reply can be
recorded straight back.

## 6a-i. The user does not know the answer (field practice, units, who types what)
Do not guess and do not build. Check whether the old app behaves the same (cite its fields); if so,
say plainly that waiting is safe because nothing gets worse than today. Keep the item as a board row
("user call, waiting on <role>"), and hand over the questions ready to forward to the people who
know (operations/admin), in Indonesian, numbered, one fact per question, with no code names. Then
remind the user of any other decision still pending (e.g. a push waiting for OK).

## 6b. A new request mid-thread is its own feature until the user says otherwise
A follow-up like "then can you also make X" is often a separate request, not a sub-question of the open
spec. Default: open a new `docs/<feature>/spec.md` with its own ids (R1.., not Q7/Q8 appended to the other
feature), and only add a cross-reference row in BOTH specs where they touch the same readers or money
(double-count risk). If unsure, ask "separate request or part of <feature>?" before writing. Why: folding
it in mixes the client's pending answers with the user's direct decisions and blocks one feature on the other.
When the request names an existing feature as the model ("make X doable in bulk payment, like the customer
bulk payment"), read it as "a new document of that shape for X" first, not "X folded into that existing
document". Put your reading in one line at the top of the reply ("Reading: a bulk payment document that
settles X") before the options, because a wrong reading makes every option and the client message wrong.
When the user skips the question that links the two features ("skip that one, just build this"), record the
resulting double-count risk under Known risks in the new spec, naming the reader that still counts it.
Then, before tickets, sort the new feature's parts against the OTHER feature's still-open client questions:
for each part, "which client answer would make this part wrong or redundant?" (a cash payout of an amount the
client may decide is deducted from the bill instead). Tell the user that list with a recommendation: build the
independent parts first (the mirror side the open questions do not touch) and hold, or build behind a
"do not deploy before the answers" note, the dependent ones. Why: parts built on a guess get reworked when the
answers arrive, and a merged-but-undeployed part then blocks deploy of everything else in develop.
When the client's answers DO arrive, before recording them as plain Q rows, diff each answer against every
already-built or merged feature that touches the same money/readers (backfill meaning of old rows, report
lines, payout vs deduction). Lead the reply with "do not deploy develop yet" if any clash, record the clashes
as new decision ids (D1..) with options, and keep the client's answers as decided rows.

## 7. Record decisions, then build
- A user change to behaviour an earlier, already-merged spec decided gets its own
  `docs/<feature>/spec.md` whose status line names the superseded ids ("Supersedes <old spec> R4, T4
  skip part"), plus a row in the last ticket to repoint those old rows to the new spec. Editing the old
  spec in place loses why the shipped code behaves the old way.
- "Is it all done?" / "what is done?" while several requests are in flight: answer PER REQUEST, in
  plain words of what users can now do (menu, screen, rule), then what is not done and why (waiting
  on client, not deployed). Name each request by what it does, not by ticket ids or commit hashes;
  leave the ticket/commit table out of this answer entirely. A status reply listing tickets/commits
  of one feature reads as "everything is done" and the user cannot tell which request it covers.
- "How long still?" mid-run: lead with ONE time range for the whole remaining code work and its
  assumptions (no new decisions, no rate-limit stalls), then a table per remaining stage (what users
  get, status, estimate), and end with any item blocked on the user (an access fix, a read-only check
  they must run) and whether it blocks building or only deploy. Change nothing in the plan.
- An ambiguous short reply (a typo like "push togo") that could mean a push: state your reading in
  the first line and do the non-destructive part; never push on a guess.
- Number open questions Q1..Qn in the chat reply and keep the same ids. When they are confirmed, each one
  becomes a row in the feature's `spec.md` decisions table (`docs/<feature>/spec.md`). End the reply by
  naming that path, so the user sees where the answers will land.
- Run-level decisions (orchestration, ordering, gates) go to `docs/<feature>-tickets/decisions.md`, one
  line per decision, following the thin-orchestrator convention. A decision that exists only in chat does
  not exist.
- Editing `spec.md` / `tickets.md` with a find-and-replace patch: anchor on text unique to the target
  row or log entry (its id plus a phrase), never on a phrase every entry repeats ("Waiting on
  review.", "gates running.") or a truncated table cell; the first match wins and splices the new text
  into the wrong row. Re-read the edited region after the patch.
- If the project has no `PROJECT.md`, work from the repo `CLAUDE.md`/`AGENTS.md`, say so in the reply, and
  offer to write `PROJECT.md` before the spec. When `PROJECT.md` contradicts what you observe (a
  push branch that no longer exists or is long merged), report it as stale in the reply and offer to fix
  it together with the where-to-build question. Do not commit to the stale branch.
- Only after decisions are recorded do you write tickets and hand off fresh workers (see thin-orchestrator).
- Before dispatching the first ticket, run `git status -sb` + `git log -1` in every target repo. If a repo
  sits on another feature's branch or has uncommitted work, do not build there: ask where to build, with
  options (recommended first: new feature branch from `develop` in a separate worktree; user commits the
  other work first; build on top of the other branch, not recommended because it couples the merges), and
  log the wait in `decisions.md`. A branch named for an earlier feature whose work is already merged
  (`git log origin/main..HEAD` empty) still counts as another feature's branch: a standing "PM commits
  and pushes the feature branch" grant does not say WHICH branch, and committing there leaves the new
  feature under a misleading name. Once chosen, set up worktrees + a baseline gate per
  `references/feature-worktree-and-baseline.md` before the first brief (it also holds the per-ticket
  gate → mutation → review order and the 5xx-count pitfall).
- Before the brief, read the last few commits on the base touching the files the ticket edits
  (`git log -3 --format='%h %an %ad %s' origin/<base> -- <file>`). A fresh commit by the user that
  disables something (a section commented out) leaves an existing test red: name that check in the
  brief as EXPECTED red ("do not fix, prove it fails on HEAD too"), put it on the board as a user-call
  row, and ask in the hand-off whether the removal is permanent (delete dead code + test, also clears
  the unused-variable lint it causes) or temporary (leave both). A worker "fixing" it rewrites the
  user's change.
- An option labelled "restore / same as the old app" needs a cite of the old code that writes THAT
  stored column (`total += ...`), not of a service that writes a report row beside it. When a later
  check shows a confirmed decision rested on a false premise, say so first, mark the row VOID in the
  spec with the reason, and re-ask it as a new id (Q2') before any ticket uses it; the user's "sure"
  agreed to the wrong facts.
- When a red-team of a draft spec returns blockers, mark the spec NOT buildable with a findings
  section (each item: verified by PM or reviewer-only), put the tickets on hold, and bring the
  new business questions back as options. A ticket whose fix is independent of the open questions may
  be offered to start first. Findings with no business question (majors/minors only): spot-check each
  cited line yourself, then add them to the spec as numbered amendments (A1..An, "these override the
  Design section where they differ") and make every brief cite them as binding by id; editing the
  design prose in place loses which reviewer evidence backs each rule.
- A user answer of "later / in the future" is a decision too: record it ("stays untouched in this
  feature"), state what the current design does with the leftover (e.g. a code path no longer reached),
  and add a DEFERRED row to the board, not just a spec line.
- A read-only check the user approved (real-DB counts, migrations table) that cannot run: say so
  plainly with the error, never invent its result, and make the design safe for every possible
  outcome (idempotent `IF EXISTS` migrations that RAISE on live data) so building is not blocked;
  keep the check as a board row due before deploy.
- The feature's LAST ticket writes both changelogs (per the repo's AGENTS.md) and a reviewer checks
  every claim against the feature's commits. The developer log must name changed routes, every
  removed/renamed response field as breaking, new 400s and nullability changes. The client log must
  warn when a stored total changes meaning or value on its next recompute with no backfill (which
  direction, when), and name every new automatic row or changed display unit users will see.

## 7a. Edit modals on an existing row
When a step becomes "a modal that edits fields, then changes status", record in the spec, before the webapp brief, what an EMPTIED field means.
- Default (PM technical): what the user sees is what is saved. Emptying a field the row had clears it; an untouched field may be omitted.
- On the server, decide per field whether `null` means "absent" or "clear", and put that decision in ONE helper. Optional-field validators let `null` through, so `null.trim()` and NOT NULL columns turn into 500s.
- A brief that says "omit empty fields" makes clearing impossible. A server that treats every `null` as "clear" lets one sloppy client wipe data.
- Editing a value that an earlier side effect already used (for example a date already posted to stock) needs its own refusal rules. The move must not silently change history the user cannot see: a recount in between, an expired lot, a later return. List those as spec rows and flag them for the user.

## 7a-i. Moving a choice from create to a later step ("move the method and its fields into the Start modal")
Ask these as separate Q ids before briefing, recommended first:
- Create form: drop the field (column becomes NULLABLE in a migration whose `down()` refuses while
  NULL rows exist) vs keep it and make it editable later. Name every reader that must render the
  unset state (list, detail, PDF, report group AND report filter option).
- Which dependent fields move with it, and which stay because another document reads them at
  create time (a shipping cost an invoice may bill before the step). Fields that only belong to one
  choice (a tracking number for the courier method) move with it even if the user did not name them.
- System paths that create AND complete in one call (quick-ship buttons, recurring jobs, imports):
  keep them sending the choice; refuse the one-call path without it.
- Rules that keyed on the choice at create ("no cost for pickup") become uncheckable: ask allow /
  refuse later / auto-zero.
- Then decide (PM technical, recorded): the choice is fixed after the step that sets it; changing
  it in that step rebuilds every field of the old shape (including legacy snapshot columns); undoing
  the step keeps the choice as a prefill; the status history notes the choice or the change.
- Mutants for the brief's tests: the one-call path without the choice, the step without it, a
  silent default, a change after the step, an old-shape field surviving a change.

## 7b. Pickers fed by guarded endpoints
When a new dropdown on document X lists records from another module (users, roles, accounts), check the
guard on that module's list endpoint before specifying it. If it needs an admin permission the document's
staff lack, specify a narrow lookup endpoint instead: `GET /<resource>/<purpose>` registered before `:id`,
guarded by ANY of document X's read/create/verify permissions, returning only id + display fields,
server-searched with `includedIds` so a saved value still renders. Keep the requested filter on the
admin list too if the user asked for it. Why: reusing the admin endpoint ships a dropdown that is empty
(403) for the people who use the form.
In the brief's acceptance list, make isolation tests use REAL near-miss fixtures: a member whose
membership in this tenant was revoked, and an active member of ANOTHER tenant only (create a throwaway
tenant the way existing suites do). An account with no membership anywhere is excluded by the base join
alone, so a test using it still passes after the tenant/status filter is deleted. Also test each
permission in an any-of guard with a user holding only that one.

## 7c. Printed-form changes ("blank line before X", "add a column between the signatures")
- Ask, as separate Q ids, recommended first: (1) the exact state that counts as "not yet X" (the
  status field, whether an undone step counts as not done, AND what terminal states such as
  VOID/cancelled print). Write "started" as equality with the positive status (`=== VERIFIED`),
  not `!== PENDING`: the negation silently treats VOID as started. Read what void/cancel clears on
  the row first; if it wipes the step's stamps, the print cannot tell "voided before" from "voided
  after" and the voided row should print as not started; (2) whether a known value prints
  in the heading, under/inside the signature mark, or not at all; (3) for a new description column,
  whether it prints a stored note or stays blank for handwriting. Restate any column count the user
  gives against the current form (an existing third signature column makes "4 columns" mean
  3 signatures + 1 description).
- When the user sends a photo of the legacy form, record its layout in the spec row (column order,
  relative widths, rule lines, placeholder like `(......)`, alignment) and steer a worker already
  building it with the same list instead of restarting it.
- Brief: extend the layout model with a new column type the one document opts into; every other
  document keeps its input type and must render pixel-identical. Proof = render the same set of
  other documents before and after (`pdftoppm -png`) and compare; plus `pdftotext -layout` asserts
  in the API suite for each state (not started, started per variant, legacy row, long and empty
  note). Old print tests asserting the opposite ("note not printed") are updated, named in the brief.
  Find them all with `grep -ln '<pdf route of the document>' test/api/*.mjs`, not from memory: any
  suite that prints the document may assert the old text (a plate on a not-started row), and only a
  gate on ALL of them shows it.
- Overflow test for a new wide text column: `pdftotext -bbox` word boxes, assert every word of a long
  note (include one long unbroken word) has `xMax` < the next column heading's `xMin`. Match the
  heading by its row (`yMin`), because `-bbox` does not list words in reading order. Prove the check
  can fail with a temporary full-width mutant. A `-layout` text check cannot catch overflow: its
  column split cuts the line at the heading.
- Print mutants for the PM's own check: force the "started" flag true/false, swap the name-chain
  order, null the note text; each must fail a suite. A fallback-chain order mutant only fails when
  some started fixture has TWO non-blank sources (driver user AND free-text armada); put that
  fixture in the brief, or it survives.
- PM check before review: open one rendered PNG with the vision tool and compare it with the photo.

## 7c-i. Agent-instruction files in briefs
Do not list `CLAUDE.md` / `AGENTS.md` among a worker's files to edit: writes to them need a live
user approval, a background worker's prompt times out, and the doc step silently drops. Ask the worker
for the exact text under a "Doc text" section of its report; the PM applies it in the foreground (or
hands it to the user) after the gate, and the board row stays open until it lands.

## 7d. Briefs name real routes
Before a brief names an endpoint a test must call ("Start it via PATCH /:id/verify"), read the
controller decorator (`grep -n "@Post\|@Patch" <controller>`): a guessed verb sends the worker on a
detour or into a 404 it may "fix".
Same for new test-suite numbers: `ls test/api | sort` on the branch the ticket builds from, at brief
time. Sibling features merged into the base take the next numbers, and a suite runner that globs
fixed-width names (`[0-9][0-9]-*`) silently skips 3-digit suites, so name the suites to run by file.

## 7d-i. Brief file lists vs "reuse the existing helper"
When a brief says "reuse helper X if it fits" but X is private (non-exported) in a file outside the
allowed list, the worker cannot reuse it and copies it instead, and the review flags the duplicate.
Before dispatch, grep the helper; if it is file-local, put "move X to the module's shared utils and
import it in both places" plus both files (and the utils spec) in the ticket's file list.
The same holds for fix-round briefs limited to "the ticket's own files": when a fix needs one
helper in two folders (a rounding helper used by the invoice and the return form), allow a
shared-utils file explicitly, or the worker exports it from the first feature folder and the second
folder imports across features, which costs another round to move.

## 7e. Money rules in briefs
State every money rule as ONE exact formula plus the invariant it must keep
(`applied + deposit == refund`), ask for it as a small pure function with a jest spec and an
in-code assertion of the invariant. Re-read the step before dispatch: a draft that corrects itself
mid-sentence ("... NO — simpler: ...") or an edge rule that contradicts the invariant is built
literally. Fix the spec row (new decision id) when the brief's exact form differs from it.

## 7f. Big tickets that break many existing tests
When a contract change breaks every suite that calls the old shape (a create body that now takes
a different parent id), split it: the code ticket ships with its new suite and LISTS which existing
suites now fail and why; a follow-up ticket adapts them. The gate's "new FAIL" diff for the code
ticket is then expected and named, and no merge happens before the follow-up lands.
Run the follow-up (tests only: it may edit `test/api/*` and nothing in `src/`) in parallel with the
fresh review of the code ticket (the reviewer builds a backend from the code ticket's files only and
ignores the suites being edited). Gate both together once, then commit them as two commits (code,
tests). Write the briefs of the next queued tickets while these run; dispatch them only after the
commit, since they read the committed code. Exception: a ticket in ANOTHER repo that only consumes
the gated ticket's contract (a webapp form over a new server field) may start while that ticket's
gate + review run. Its brief points at the build report's contract section and the uncommitted code
as read-only ("do not edit, do not start backends from it"). If the review changes a field or
response shape, steer that worker with the change at once rather than letting it finish on the old one.
A user decision arriving while parallel workers run (server + webapp halves of one fix round): append
the new scope as an "ADDED mid-run" section to the shared brief, then run `delegate_task
action=list` before steering. A steer only reaches a LIVE child; a sibling that already finished
never sees it. Brief that half as a small follow-up run (its own brief citing the other half's
report as the contract) and record the split on the board row.

## Before you hand in
- [ ] Grill done: open business questions presented as options with consequences, confirmed
- [ ] Prior decisions searched and quoted (step 1)
- [ ] Every cite re-checked against the file (step 2)
- [ ] Existing template found and named (step 3)
- [ ] Scope questions asked, not decided (step 4)
- [ ] Corrections traced to every report/total (step 5)
- [ ] Existing-data row in the spec: nullable columns, service-side requirements, snapshot check before drops (step 5b)
- [ ] Every claim labeled VERIFIED or ASSUMED (step 6)
- [ ] Decisions recorded in `decisions.md` before any ticket is written (step 7)
- [ ] Target repos clean or a separate worktree chosen; baseline gate recorded with known failures explained (step 7)
- [ ] Every new picker's source endpoint guard checked (step 7b)

## Notes
- Existing templates to copy, not invent: entity shape, status machines, document → approval → confirm,
  reserve → convert, and the append-only movement/ledger pattern in this codebase.
- Overlaps: `pm-discovery` (pre-spec phase, externally owned read-only) and `thin-orchestrator` (workers,
  gates, mutations, review, commits). This skill additionally owns the grill and verified/assumption
  protocol and the record-decisions-before-building ordering.
- **Versioning rule (projects whose PROJECT.md/CLAUDE.md says so, e.g. a monorepo with a develop branch):** "remove versioning so, all that goes into the develop without versioning
  and change log". In those projects features integrate into `develop` without version bumps, tags, release branches, or a
  CHANGELOG.md entry. The release flow (`scripts/release.mjs` on `main`, CHANGELOG generation) runs only on
  `main`/release, never on `develop`. When the develop branch is a WIP feature line, do NOT import release-era
  commits by merging `main` into `develop`; instead rebase the feature branch onto `develop`, keep develop-side
  values, and append only the feature's additive changes.
- **Merge conflict rule:** on a conflict between develop-side business logic and the feature's additive change,
  keep the develop-side value. The feature only adds a new dimension (e.g. a new FK, a new enum value, a new
  UI field, a new payment state); it never replaces existing business behavior.