---
name: codebase-bug-hunt
description: "Use when asked to find hidden bugs. Gate, fan out, verify."
version: 1.0.0
author: pm
license: MIT
metadata:
  hermes:
    tags: [audit, bug-hunt, review, lint-triage]
    related_skills: [pm-discovery, thin-orchestrator, approval-safe-shell-runs, to-tickets]
---

# Codebase bug hunt (read-only audit -> ranked report -> next steps)

## When to Use
Requests like "check the frontend and backend for hidden bugs, report for next step", "audit
this repo", "find latent bugs".
The deliverable is a severity-ranked list of VERIFIED findings plus next-step options; no code
changes, no commits, no DB writes.

## 1. Orient (one batch of calls)
- Find PROJECT.md; if absent read each repo's CLAUDE.md/AGENTS.md top section (business rules
  + gotchas) and offer to write a PROJECT.md later. Note the decided business rules: reviewers
  must not report them as bugs.
- `git status --short`, branch, last commits per repo (confirm a clean tree and what you audit).
- Size the code (file count, LOC, module list, test dirs) to decide how to split reviewers.

## 2. Static gate on scratch clones (background)
- `git clone` each repo into the scratch dir and install there; never install/build in the
  user's tree (adds node_modules/dist, may rewrite lockfiles).
- Put steps in a script file and run `bash script.sh` in background with notify (inline chains
  trigger approval prompts). Log each step to its own file; echo exit codes + tails.
- Steps: install, `tsc --noEmit` (server) / `tsc -b` (webapp), eslint, unit tests, project
  checks (e.g. `check:options`).

## 3. Triage lint by rule, not by count
- Raw lint totals are mostly prettier/`any` noise. Count by rule:
  `grep -oE '(error|warning)  .*  [@a-z/-]+$' lint.log | awk '{print $NF}' | sort | uniq -c | sort -rn`
- Then read the code behind the bug-prone rules only: `restrict-template-expressions` and
  `no-base-to-string` (often SQL/string built from values), `no-floating-promises`,
  `no-unsafe-enum-comparison`, `react-hooks/rules-of-hooks`, `no-constant-binary-expression`,
  `exhaustive-deps` (stale closures). A lint hit is a lead, not a finding, until read.
- Hand-rolled SQL helpers that interpolate values (`` `${key} ILIKE '%${value}%'` ``) are the
  classic hidden critical: grep their caller count and whether user input (search params)
  reaches them; check the DB role's grants to size the blast radius.

## 4. Fan out read-only reviewers in parallel (delegate_task, one batch)
- Split by risk area, ~5-6 children: backend per domain (e.g. sales / purchase+inventory /
  auth+tenant+finance+reports), frontend per domain, frontend infra + API contract sweep
  (every frontend URL+verb exists on a backend controller).
- Each context: absolute repo paths; READ-ONLY (no edits, formatting, git, DB, servers);
  scratch-notes dir; the decided rules that are NOT bugs; a concrete list of bug classes for
  that area (money/stock math, decimal strings from pg, check-then-insert races, side effects
  outside the transaction, status recompute missing on delete/cancel, tenant scoping,
  permission guards, timezone date shifts, FE/BE total-formula drift, payload vs DTO, cache
  invalidation, double-submit); "fewer real findings beat many speculative ones; no style".
- High-yield bug classes, grouped by area (concurrency, money, stock/lots/units, imports,
  platform/security, frontend), are in `references/bug-classes.md`. Paste the matching group into
  each reviewer's context (or into the shared CONTEXT.md); named classes get traced, unnamed ones
  get skimmed. Add each new verified class there, deduped, when a hunt ends.
- On a repeat audit, give reviewers the previous audit's fixed/known-open lists and the diff range
  since it, so they spend time on new code; ask them to list confirmed-still-open old IDs in one line.
  Also grep earlier fix runs' `tickets.md` for "Deferred" lines: those races were seen and never
  fixed, so re-check them as candidate findings (cite the deferral) instead of listing them as known.
  Write that into ONE shared `CONTEXT.md` in a new scratch dir (repos + HEAD shas, hard rules,
  decided rules incl. the ones the last fix run just decided, known lists: previous audits' numbers
  split fixed/open plus the fix run's backlog rows, bug classes, output) and make every child read
  it first; per-child context then only names the area. Re-pasting it per child drifts.
- A deeper pass ("trace deeply, take more time") after a fix run: split ~8-10 read-only areas by
  money/stock FLOW, not by folder (purchase/AP, finance/Kas/deposits, inventory core split in two
  (balance replay+locks+reservations / lots+transfers+opname), sales chain quote->POS, reports+PDFs,
  platform/permissions/tenancy, imports+migrations, webapp forms + full API contract), and run them
  in WAVES of at most 3-4 (see the rate-limit rule below). Tell each to trace UI -> controller ->
  service -> SQL -> what the user sees before reporting. Give the sales child a second job: regression review of the just-merged fixes as a set
  (`git diff <base>..<merged>`), looking for cross-ticket interactions (new lock order vs other
  writers, migration on real data shapes) that per-ticket reviews cannot see.
- Add one SYSTEMATIC child that fills a table instead of sampling: every state-changing method
  (confirm/cancel/void/delete/pay/run/receive...) with transaction?, row locked before guards?,
  guards re-read after lock?, lock order vs parent/child/stock locks, side effects outside the
  transaction; plus every document-number generator. It writes the full table to its notes file
  and reports only unsafe rows not already known. Domain children miss the methods nobody
  thought to open; the table does not.
- Read-only children cost no memory, but they DO share the account's API rate limit: the cap for
  long read-only readers is 3-4 at once (next rule), not the building-worker memory cap.
- Pass an `output_schema`: findings[] with title, severity, confidence
  (confirmed-by-reading/likely/speculative), file:line, evidence, impact, repro, fix_hint;
  plus areas_covered / areas_not_covered.
- After dispatch, report interim gate findings and end the turn; do not poll.
- Rate limit: many long readers in parallel all hit the account rate limit (HTTP 429) together
  after ~45 min, and a reader that only reports at the end loses everything (its last turn cannot
  rebuild findings from a truncated context). So:
  - run at most 3-4 readers at a time, as numbered waves recorded in a scratch `PENDING.md`
    (wave list, what died, what to re-run), starting the next wave as soon as slots free;
  - put a mandatory "SAVE AS YOU GO" section in the shared CONTEXT.md: each reader gets an id,
    creates `notes/<id>.md` with its plan in the first minutes, APPENDS every confirmed finding
    and a `covered: <flow>` line as it goes, and resumes from that file if it already exists;
  - a systematic table child appends its table module by module;
  - each later wave's context tells its readers to read the earlier waves' `notes/*.md` first and
    skip what is already recorded, so overlapping areas (concurrency table vs domain readers) do
    not report the same race twice;
  - a dead reader's partial output can still carry findings: re-check each at file:line, save them
    to `notes/<id>.md`, and queue only its NOT-covered list as a follow-up reader.
  The many `TASK FAILED` notices of one rate-limit event are one incident: acknowledge them in
  one line each, do not re-plan per notice.

## 5. Verify, then report
- Re-open every child finding's file:line before it enters the report; child output is a
  claim. Drop or downgrade what does not hold; dedupe across children.
- Batch the re-reads: one terminal call per wave that `sed -n`s the cited ranges of the top
  findings (high/medium) and greps the guard each claim says is missing. Low findings may enter as
  R (reviewer only) and be re-read before the report is written.
- Before writing the report, compare each repo's HEAD with the SHA the hunt started on; if the base
  moved, `git diff --stat <start>..HEAD`, re-check any finding in a changed file on the new HEAD, and
  name both SHAs in the report's scope line.
- When a finding was introduced by a commit outside the hunt's own fix run (`git log -- <file>`),
  say so: it changes who owns the fix and whether it is already in production.
- Findings that hinge on a business rule (discount vs tender, should X post to the cash ledger)
  go to the user as a decision question with options, not into the fix list.
- Security findings whose exploitability depends on deployment (origins, CSP, proxy) are marked
  V for the code path and ASSUMED for the exploit, saying what would confirm it.
- Verify per wave, not at the end: after each wave, re-read its findings and append them to one
  scratch `VERIFIED.md` with their final numbers (continuing the previous report's numbering),
  severity, V (PM re-read) or R (reviewer only), file:line and mechanism. Report that wave to the
  user as a short table; the final report is then assembled from `VERIFIED.md`, and a session cut
  off mid-hunt resumes from it.
- Report: gate table (tsc/tests/lint per repo, lint split into noise vs real) -> findings by
  severity with file:line, mechanism, user impact, VERIFIED vs ASSUMED (say what would
  confirm, e.g. which DB user prod runs as) -> what was NOT covered -> next-step options
  (fix order as tickets, recommended first). Fixes become tickets via the normal flow.
- Reply in the language the user last wrote in.
- If a reviewer child gets cut off (for example by a content filter on security wording), re-run its
  area as two narrower children instead of dropping it, and say in the report that you did.

## 6. Shareable report (the user forwards findings to his team)
- Number every finding once and keep those numbers stable: main findings 1..N, then the minor ones
  continue the numbering (N+1..). The user picks the scope by number ("fix 1,2,3, 6,7"), so a
  renumbered list breaks that. A follow-up audit of the same code goes in a NEW report file and
  continues the previous report's numbering (last was #54 -> start at #55), so numbers stay unique
  across both reports and a scope reply can mix them.
- The user checks findings from one complete list. After the report, also give it in chat as tables
  in severity sections (HIGH / MEDIUM / LOW, then "Decisions needed"), one row per finding with
  columns `# | Area | Bug | Status`. The Bug cell is the user-visible effect in one line, and Status
  combines V/R + Race + Decision, with a one-line legend on top. End with the suggested first fixes
  and "tell me the numbers". When asked for it in another language, translate the same tables in
  place (identifiers and numbers unchanged); do not switch to the chat-message format below.
- When asked to translate for chat (e.g. WhatsApp, in Indonesian): give ONE copy-paste code block in
  chat formatting (`*bold*`, `_italic_`, `•` lists, `━━━` separators between sections, no tables,
  no file paths). Order the sections by priority, give each item its user-visible effect and an
  example where it helps, mark the unverified items, and end with the proposed next steps. Offer the
  `━━━` lines as the places to split it.
- Expect follow-ups in the same format: the minor-bug list and any decision questions (options
  a/b with the recommended one first, closing with a "reply like *1a 2a*" line). Write them the same
  way without being asked twice.
- Once the user picks a subset, restate exactly what is in and out of scope (including items they
  skipped) before any ticket is written.
- A scope reply that mixes excludes and includes in one sentence ("sure except #24, #25. B27, B26")
  is ambiguous about the trailing items: restate the in/out lists and ask about the unclear ones
  inside the same clarify call as the business questions, never guess.
- For a fix that filters VOID/cancelled rows, write the decision question with display and totals
  as separate choices (shown + not counted / hidden / shown + counted) and per surface (invoice,
  receivables, report). One option that bundles "hide it" with "don't count it" gets reversed after
  the user tests the screen.

## 7. From picked findings to a fix run (same session)
0. "Fix everything, use your recommendations" is a standing approval: skip the clarify call, record
   every business rule in the spec as taken under standing approval (marked, e.g. `(SA)`) with the
   rejected alternative and its consequence, and still list each data change that runs at deploy
   (migrations rewriting rows, history not backfilled) for the user in the final report.
1. Split the picked items: business rules (numbering scheme, which reports change, refuse vs
   auto-cascade, hide vs build a field) go to the user in ONE clarify call, one question per item,
   recommended option first with its consequence; add the branch/commit/push rule as its own
   question if PROJECT.md or memory does not settle it. Technical fixes (lock + re-check, default
   alignment, cron check placement) are PM decisions with ids, not questions.
2. Write `docs/<run>/spec.md` (scope in/out by audit number, decisions table Q1.., lock order,
   risks such as historic report figures changing), `decisions.md`, `tickets.md`, and one shared
   `worker-rules.md` before any brief.
3. Group items into tickets by FILE, not by audit number: items in the same service share a ticket;
   a ticket whose files overlap two others waits for a later wave.
4. A run that fits one or two waves: generate all briefs in one `execute_code` loop. A run of many
   waves: write the board with every ticket's file ownership up front, but write briefs only for the
   wave being dispatched (draft the next one while it builds): later tickets reuse what earlier ones
   commit (a shared lock util, a moved helper), so a brief written at the start cites code that no
   longer exists. Either way, from a dict, appending a common footer (read
   rules/spec/audit item, report path, stop-and-ask list). Each brief names the bug mechanism with
   approximate lines, the fix shape, non-goals (sibling audit items left out), acceptance as an HTTP
   suite that is RED on HEAD (race items: N>=5 rounds of `Promise.all` pairs, exactly one 2xx,
   totals correct), and the existing suites to re-run. Template: `templates/fix-brief.md`.
5. One script creates the branch in each repo (asserting a clean tree on the base branch first) and
   records the baseline gate (tsc, unit, full HTTP suites on a fresh DB) in the background; dispatch
   the first wave right after it starts, since workers build their own HEAD copies, but cap it at
   the parallel limit in `parallel-ticket-waves` (building workers are memory-heavy; a webapp-only
   ticket and read-only reviewers are cheap). Queue the rest as numbered batches on the board.
6. When the baseline comes back, read its FAIL lines once: suites red because their fixtures predate
   newer required fields/rules (a now-required field, a removed route, a reason now mandatory) are
   one backlog row, not tickets, and every brief must tell workers to add those fields to their own
   new suites' fixtures.
7. Then follow `parallel-ticket-waves` for gates, reviews and commits.
8. A bug the user reports mid-run ("X does not appear in the picker", "button goes to the wrong
   page") joins the run as its own ticket, triaged before briefing:
   - Split server vs webapp with a scratch HTTP probe on a base-branch backend (own throwaway DB):
     script the user's exact sequence and call the endpoint the UI calls plus the create endpoint
     the button leads to. Server correct = the bug is in the UI path.
   - In the UI, check every visibility condition, not only the list: "already has a child
     document" hooks that count ANY row (cancelled included) hide entry buttons on several pages;
     list the hook's callers. Check the cancel mutation invalidates the parent's query keys.
   - Check the user's real data read-only (`SET default_transaction_read_only=on`, from a script)
     to see whether any record matches the scenario; if none does, say so and ask for one number.
   - A request that reverses documented behaviour (a code comment "redirects to X as requested")
     is a new spec decision that names the old one.
   - If its files overlap an uncommitted ticket, mark it "waits <ticket> commit" on the board.
