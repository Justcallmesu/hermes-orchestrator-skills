---
name: pm-discovery
description: "Use before designing a feature or writing a spec. Verify first."
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

## 2b. Find the template before designing a shape
Before proposing a new entity, status machine or flow, search the repo for an existing one with the
same SHAPE (header + lines with a derived status, document → approval → confirm, reserve → convert,
post-commit side effect). Name it in the design: "follows <file:line>". Inventing a parallel
pattern when one exists is a design defect even if it works.

## 3. Scope is the user's call
These are business scope, so they go to the user as options even when one answer looks obvious:
- New document/entity vs extending an existing one.
- Which locations, roles, item types, or modules are in or out.
- Granularity the user will see: partial vs all-or-nothing completion, one permission vs several.
- What happens to related records when this one is cancelled, denied or corrected.
Give your recommendation first, with its consequence; do not decide it in "technical decisions".

## 4. Follow corrections downstream
For every rule of the form "no undo", "immutable once X", "corrected by a new document", "cancelled by Y":
- List every report, total, balance, journal and status that reads the original record.
- For each one, say whether the correction flows into it. If not, it is a risk: the number is wrong
  until someone nets it out by hand. Put it in the risks section or ask the user.

## Before you hand in
- [ ] Prior decisions searched and quoted (step 1)
- [ ] Every cite re-checked against the file (step 2)
- [ ] Existing template for the shape found and named (step 2b)
- [ ] Scope questions asked, not decided (step 3)
- [ ] Corrections traced to every report/total (step 4)
