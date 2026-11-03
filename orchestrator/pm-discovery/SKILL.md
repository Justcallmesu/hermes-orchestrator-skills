---
name: pm-discovery
description: "Use when asked how to build or port a feature. Verify first."
---

# PM discovery: verify before you design

Run this before any design, spec or recommendation. Each step exists because skipping it once
produced a wrong spec that would have passed review.

## 1. Find the decisions that already exist (before forming an opinion)
- Search the knowledge docs, ADRs, specs and code comments for the feature name and its synonyms
  (including any local-language name, entity name or enum member). Example:
  `grep -rniE 'refund|chargeback' docs/ src/ --include=*.md --include=*.ts`
- Read every hit in full context (at least 10 lines around it), not just the match line.
- List each recorded intention as a VERIFIED fact with its citation ("design-v9 §8: refunds go through the approval step").
- A recommendation that goes against a recorded decision must say so explicitly:
  "This contradicts <doc:line>, which says X. I recommend Y because Z." Never contradict silently.

## 2. Cite exactly
- Read ONE file per numbered read (`cat -n file`, `sed -n 'a,bp' file`, `grep -n`). Never `cat -n a b c`:
  numbering runs on across files and every line number after the first file is wrong.
- Before writing the answer, re-open every `file:line` you cite and confirm the line says what you claim.
  A cite that lands on the wrong line is a false VERIFIED claim, even if the fact is true.
- Write the FULL path in every cite. Never shorten with `...` (`app/.../x.ts:10`): an abbreviated cite
  cannot be checked by anyone, including the script below.
- Run `scripts/check-cites.py <answer.md> --root <prefix>=<dir> ...` (prefix = the name your cites use,
  dir = the tree you read) and fix every FILE and RANGE error. IDENT warnings are hints: re-open that cite.

## 2b. Find the template before designing a shape
Before proposing a new entity, status machine or flow, search the repo for an existing one with the
same SHAPE (header + lines with a derived status, document → approval → confirm, reserve → convert,
post-commit side effect). Name it in the design: "follows <file:line>". Inventing a parallel
pattern when one exists is a design defect even if it works.
- Record the search: which candidates you looked at, why this one wins, and what you do NOT copy. A
  template can carry a flaw (an unlocked read, a missing status check); say which part you skip and why.

## 2c. Reused code has guard clauses: list what it refuses
Before a design depends on an existing method, helper or entity method, read its guards (throws,
asserts, validators, DB constraints). For each one list the inputs the NEW flow can send that it
rejects: zero or negative amounts, null or missing links, over a limit, a wrong status, an inactive
parent. Each becomes an acceptance criterion or a DTO rule at the point where the user can still fix it,
not an error that surfaces later in a different step.

## 2d. Old app: find the live path first
When comparing with the old application, establish which code path is live before describing its
behaviour: versioned or duplicate files (`*-v2`, `*-new`, `legacy`), commented-out blocks, routes that
nothing calls. Describe and list defects of the live path only, and name the dead one so nobody ports it.

## 3. Scope is the user's call
These are business scope, so they go to the user as options even when one answer looks obvious:
- New document/entity vs extending an existing one.
- Which locations, roles, item types, or modules are in or out.
- Granularity the user will see: partial vs all-or-nothing completion, one permission vs several.
- What happens to related records when this one is cancelled, denied or corrected.
- The exits of every status: can a pending item be cancelled, does a cancel or reject need a reason, can a
  decided item be corrected and how. List each exit as a question with options, even when one looks obvious.
Give your recommendation first, with its consequence; do not decide it in "technical decisions".

## 4. Follow corrections downstream
For every rule of the form "no undo", "immutable once X", "corrected by a new document", "cancelled by Y":
- List every report, total, balance, journal and status that reads the original record.
- For each one, say whether the correction flows into it. If not, it is a risk: the number is wrong
  until someone nets it out by hand. Put it in the risks section or ask the user.

## Before you hand in
- [ ] Prior decisions searched and quoted (step 1)
- [ ] Every cite re-checked against the file, full paths, `check-cites.py` has no FILE/RANGE errors (step 2)
- [ ] A "Template search" block in the answer: candidates, the winner and why, what is NOT copied (step 2b)
- [ ] Guard clauses of every reused primitive read; rejected inputs turned into criteria (step 2c)
- [ ] Old-app comparison is against the live path (step 2d)
- [ ] Scope questions asked, not decided, including every status exit (step 3)
- [ ] Corrections traced to every report/total (step 4)
