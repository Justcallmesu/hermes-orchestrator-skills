---
name: explain-system-behavior
description: "Use when asked why/how the system does X or how to reach it."
---

# Explain why the system does X

Trigger: "why is there a <check/validation/side effect> in <document> when <state>?", "why does X happen here?",
"is <balance/total> only created by <document>?" (e.g. are payables/receivables only counted at invoice).
The user wants two answers: is X intended, and is it right. Answer both, from code, before proposing any fix.
For "which documents feed this balance/total" questions, follow `references/derived-balance-audit.md`.

## Procedure
1. **Project context.** Read `PROJECT.md`; if absent, read each repo's `CLAUDE.md`/`AGENTS.md`, especially the
   "business rules decided with the client" section. Those rules are what the behavior must agree with.
2. **Find the gate and every call site in one batch.**
   `grep -rn '<gateFn>' <server>/src` plus grep the webapp for the user-facing text (local-language error
   message, label) to learn where it surfaces. Also grep bug-audit/spec files in the workspace root/`docs/`.
3. **Call-site table:** user action -> runs or not -> `file:line`. Cover create, confirm, edit, re-open,
   import/system-generated and convert-from-upstream paths. A path that skips the gate while a nearby comment
   says it re-checks is a likely bug.
4. **Audit the gate's inputs against the business rules.** A money/stock gate computed from figures the rules
   call provisional (e.g. prices that are only finalized on a later document) is a design flaw even when the
   code matches its comment.
5. **Audit the aggregate it compares against:** status filters (drafts/cancelled counted?), double counting
   (the record being confirmed is already in the total and gets added again), all-or-nothing joins (a partly
   converted record drops out entirely).
6. **Cross-check known findings:** cite bug-audit ids that cover the same function and whether the active
   branch's spec has them in or out of scope; mark the mapping ASSUMED when numbering schemes differ.
7. **Deliver** (reply in the user's language):
   - one-line verdict: "Intended, because <cite>" / "Not intended".
   - call-site table, then numbered defects, each VERIFIED with `file:line` or ASSUMED with what would confirm it.
   - if the right placement is a business rule: options table (recommended first, consequence each) and one
     decision question. No fix, spec or ticket before the user picks.
   - say plainly what was not run (read-only analysis, no repro).

## "How do I access / can it do <feature>?" (where is the menu, can it do bulk)
1. Find the feature's `docs/<feature>/spec.md` + `tickets.md` (grep `docs/` for the feature words), then
   check the CURRENT code, not the spec: menu entry (`UseMenuItems.tsx`), route file, permission codes,
   deep-link buttons. A shipped spec can be partly undone by a later feature's decision; grep the other
   specs for the feature name and run `git log --oneline --all -S "<MenuKey>"` to catch a removal commit.
2. Answer with: the menu path + URL, any deep-link entry point, the permissions needed (a new
   permission is usually granted to no role, so "I can't see it" = role grant), and what was removed with
   the decision id and commit. Also say whether it is merged or deployed, and what was not browser-checked.
3. "Can it be done in bulk?" is ambiguous when one feature has several steps (creating the documents vs
   settling them). Read the create DTOs (`<ids>: string[]` vs a single `<parent>Id`) and answer with a
   per-step table (step -> bulk yes/no -> `file:line`). Say how to do it today, and offer to scope the
   missing bulk step as a new feature instead of assuming it is wanted.

## "What is <domain concept> in the app?" (e.g. freight, credit note)
1. Find its origin first: the commits that added it (`git log --all -i --grep=<term>`), the glossary
   (`CONTEXT.md`), knowledge docs, and the old app (grep the old trees; "the old app had none" is a
   finding).
2. Answer as a question -> answer -> source table: where it is entered (screen + field label + tooltip),
   whether it is in the document total, when it is booked, which journal rows, partial / reversal /
   return behaviour, whether it enters stock cost, which special documents never carry it. Then one
   worked journal example with real-looking numbers.
3. End with the open accounting questions for finance, max 3. Say plainly that a general standard
   (e.g. PSAK capitalisation rules) is general knowledge, not something confirmed for this client.

## When the user answers "I don't know, can you handle it?" on a business question
That delegates the call; it is not a blank cheque to skip evidence.
1. Verify the current behaviour in code for each question (cite file:line) and check for an old-app
   precedent and a recorded glossary/decision intent.
2. Pick the recommended option and record it at once in the spec decisions table: "user delegated,
   PM chose option A", the rejected options with their consequences, the evidence.
3. Prefer the option that keeps the documented intent (glossary, the other developer's design) and
   makes the app's own numbers agree (document total = what the journal books); defer options that add
   new fields or payees nobody asked for.
4. Turn the practical consequence into a user rule plus a small UI hint ticket when users could enter
   data wrongly (e.g. "a courier paid separately is not entered in this field").
5. Cut the code ticket, dispatch it, and tell the user which other developer's module it touches.
   A ticket that changes a stored document total (invoice, payable) must make the brief list every
   reader of that total for the worker to grep (lists, reports, dashboards, payment/credit-note,
   cancel, return) and put the sum in ONE shared function; have the reviewer prove by hand, plus a
   random sweep, that the journals of a fully received document sum to the new total to the cent
   with partial receipts, discount and tax, and name the edge case where they still differ (e.g. a
   document with goods 0 but a surcharge) as a board row for the user.
   Reply with a decision table (id, question, decision, why), what runs now, how it affects any pending
   browser run (start now vs wait), and the questions still open with your recommendation each.

## Pitfalls
- State every condition the code puts on a behaviour, not just the event. Read the gate's early
  returns (e.g. `if (paymentType !== CREDIT) return`) before describing it: "credit is re-checked
  when a reopened order is edited" is wrong if it only runs for CREDIT orders, and the user will
  have approved a rule he never meant. Use a when/condition/`file:line` table. This also applies when
  you pass on a worker's report or put a decision to the user.
- "Does a fully <delivered/received/invoiced> document still show in the <child> form?": compare the
  dropdown's filter with the save-time cap. Dropdowns often filter on the parent's STATUS, and that
  status may count only posted children (verified, not pending), while the save check also counts
  pending ones. If they differ, the user picks a document that can't be used and only gets the error
  on save. Report both `file:line`, the cases where they differ, and whether data integrity holds
  (the save check) or only the UX is off. Check the audit/ticket board for an existing row first, and
  answer "is it in the tickets?" explicitly. The fix options must cover BOTH levels: the parent
  dropdown (hide a document with nothing left on any line) and the line picker (hide lines with 0
  left, vs today's greyed-out rows). The user's default is to hide what can't be picked, at both
  levels; a one-level option gets a correction.
- "I can't <search/filter/do X>, add it": verify before planning. Read the current implementation
  (`file:line`) and `git log -S` for when it landed; if X already works, say so first. Check the
  user's example against the real data format (read the number generator: prefix, date digits,
  serial width) since a mistyped example looks like a missing feature. Then give a per-screen table
  ("can do now" / "cannot yet") so the user picks the scope, and ask which screen he actually used.
- "After cancelling X the user cannot <redo Y from the parent>": check each layer separately. First
  the server picker or create path, with a scripted API probe on a develop backend (create, cancel,
  list, re-create). Then the webapp gates, i.e. the hooks that hide the action button. "Has child"
  hooks that ask `?parentId=X&limit=1` count cancelled or void children, so the server can allow the
  action while the UI hides it. Also check whether the cancel mutation invalidates the parent
  module's queries; if it doesn't, the picker stays stale until a reload. Run a read-only DB query
  for real rows in that state too: legacy data often has the parent cancelled as well, which
  explains "it doesn't show" without any bug.
- When the user points at a line as the cause ("I think it's this WHERE clause"), evaluate it with
  the concrete row values (e.g. a cancelled row has `deleted_at` NULL, so `status <> 'CANCELLED'` is
  false, the subquery is empty, and NOT EXISTS is true). Show it as a per-row truth table. Say plainly
  whether it is the cause, then list the conditions that can still hide the item (status set,
  approvals, settings, paging/search). Don't agree just to move on. If the user proposes a rewrite
  ("fetch where all children are deleted or cancelled"), check whether it is logically the same
  condition (`NOT EXISTS(live child)` == "every child dead, or none") and say so before changing
  anything; offer a shared named predicate instead when the same rule is copied in several places.
- "It appears when I set `deleted_at` by hand" does not prove the server clause is wrong: a
  soft-deleted row vanishes from EVERY default ORM query, including the webapp's "has child" list
  call that hides the button. Ask which version prod runs and check it against the fix commit
  (`git tag --contains <sha>`): an older deploy explains the server side by itself. Advise undoing
  the manual soft-delete (the record drops out of lists, detail and reports) and give an interim
  path that works today (e.g. the create form's deep link with the parent id).
- Limit vs remaining: for "is the credit/stock limit reduced by X?" say the configured limit never
  changes; what moves is the remaining amount (limit - exposure). Answer with a step table (draft,
  confirm, invoice, pay, cancel -> owed, remaining) so double counting or the lack of it is visible.
- Quick "why is X 0/wrong" questions: report what code + read-only DB queries show and ask before
  spinning up scratch backends, dev servers or a browser repro; the user stops long repro chains.
- Check the UI before claiming where the user saw it: if the screen shows no figure, the only surface may be
  an error message; say so and ask for a screenshot rather than guessing.
- "Does correction document X (return, credit note) take from upstream doc A? It should be B": answer the
  anchor question, then check what the client's reason implies. A reason like "so it is cut from the
  customer's bill" is a money rule, not a picker change. Before you offer options, audit every reader of
  that balance with `references/derived-balance-audit.md`: outstanding, payment cap/PAID status, credit
  limit, recap/statement printouts, cash-flow and tax reports. Options that only move the FK miss the real
  requirement. Keep the physical side (stock warehouse/lot/conversion) on the document that actually
  posted it, and map the new anchor's lines back to it.
- A follow-up ask in the same thread ("then can you also make X") is a separate request until the user says
  otherwise. Give it its own `docs/<feature>/spec.md` and decision ids, cross-link the two specs, and keep
  its questions out of the first request's client list. Folding it in mixes two scopes and gets a correction.
- When the user must forward questions to the client, hand over a ready-to-paste WhatsApp message in
  Indonesian: a greeting with the topic, `*bold*` numbered headings, one plain sentence of what the
  system will do plus a worked example with real-looking numbers, options `a./b./c.` with `_(saran
  kami)_` on the recommended one, and a closing reply template (`_1 ok, 2 ok, 3a, 4a_`). No file paths,
  code terms or English jargon. Put it between `---` lines so it copies cleanly.
- "Users did <workaround> in the old app (e.g. same product twice, one row at price 0 as a bonus) and
  now can't <bill/ship> the ported data": the workaround usually hits a NEW gate the remake added
  (no duplicate product rows, minimum-price floor, qty caps). (1) Read the importer to see the shape
  the ported rows really have; it often copies legacy lines one-to-one. If you can't tell, list each
  possible shape and the gate that rejects it, with the exact error text, then ask for the document
  number or error to confirm. (2) Grep for a concept that already models the workaround elsewhere
  (e.g. a POS free-item flag or promo kind) and check the docs' "not done" notes. Base the permanent
  option on that concept instead of inventing a new one. (3) Answer with a no-code interim path the
  user can use today, plus its limits, then 3-4 permanent options (recommended first). Ask the
  side-effect questions the flag raises: who may set it, its return/refund value, how it shows in
  margin reports, and how ported rows get backfilled.
- Don't stop at "it's by design": the user's surprise usually points at a mismatch between the gate and a
  later business decision (e.g. prices moved to another document) that nobody re-checked.
