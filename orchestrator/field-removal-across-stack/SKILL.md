---
name: field-removal-across-stack
description: "Use when asked to remove a field or revert a change."
---

# Remove or retire a field across UI, API, DB (or revert a shipped change)

For "revert <this changelog line / feature>" see the section at the end; the same
map -> ask scope -> record -> dispatch spine applies.

Trigger: "remove <field> from <document>" (e.g. a tracking number on a delivery order). A one-line
ask hides a multi-repo change and possibly permanent data loss, so the scope is the user's call.

## Procedure
1. **Map every usage in every repo** before answering. Grep the field's UI label, camelCase AND
   snake_case names, and its local-language word (`grep -rni 'trackingNumber\|tracking_number\|resi\b'`),
   excluding look-alikes (`resid`, `resiz`). Expected spots: form fields + payload builders, detail
   page, list/report columns (combined labels like "Ekspedisi / Resi"), shared TS types, DTOs (create
   AND edit/verify), entity column, service helpers/validation, PDF templates, import templates,
   sample-data seeder, legacy-port raw inserts, API test suites, docs (CLAUDE.md), changelog.
2. **Find the decision that introduced it** (grep the spec decision tables near the field) so the
   new decision can say what it supersedes.
3. **Ask scope with options** (recommended first, each with its consequence):
   - Hide from UI only (column + data stay, reversible; report column relabelled).
   - Remove everywhere incl. a drop-column migration (data deleted permanently, both repos).
   - Remove from input only (old values still shown).
   Restate the picked option before acting (the user often answers tersely).
4. **Record the decision** in the feature's `spec.md` decisions table with a new id that names the one
   it supersedes, the exact surfaces touched, and the data consequence.
5. **Check old-client behaviour**: read the global validation pipe (`main.ts`, `whitelist` /
   `forbidNonWhitelisted`). With `whitelist: true, forbidNonWhitelisted: false` a removed DTO field
   is silently stripped: harmless for a pure data field, but when the field TRIGGERS a side effect
   (an opt-in flag like "also round / also notify"), a cached old bundle saves without the effect and
   no error. Then keep the field on the write DTO only to refuse it (`true` -> 400 "page updated,
   reload") and assert 400 + nothing written. With `forbidNonWhitelisted: true` old clients get 400
   until the webapp deploys, so order the deploy or keep the DTO field ignored.
6. **Dispatch one worker per repo in parallel**, each brief listing the verified `file:line` spots and
   saying "grep to confirm, there may be more". Server brief:
   - new migration timestamp strictly after the newest file in `src/migrations/<scope>`; copy the
     header style of the latest migration; `down()` re-adds the column nullable and states data is
     not restored; never edit the baseline migration;
   - remove the key from raw-SQL inserts (legacy port, seeders), not just the TS field, or those
     scripts break on the dropped column;
   - tests: delete checks that exist only for the field, strip it from payloads of checks testing
     other things, fix expected report strings;
   - verify = type-check, lint on changed files, unit tests, build. No migration run, no API suites,
     nothing that writes a DB unless the user allows it; report these as NOT verified.
   Webapp brief: types, form field + prefill + payload logic, detail rows, comments; add a NEW
   changelog item (never rewrite a past release's entry). Final grep in each repo must show only the
   new migration, the baseline migration and changelog lines.
7. **Data-destroying scope** -> a fresh reviewer red-teams both diffs before commit.
8. Commit per repo with explicit paths; push only when told. Run commit+push as one script file:
   check branch, `git fetch`, print `git rev-list --left-right --count origin/<b>...HEAD` (behind > 0 =
   stop and integrate), `git add <paths>`, `git diff --cached --stat`, commit, `git log -1` with author,
   push, `git status -sb`. Report hash, author, push range and what is still unverified.

## Revert a shipped change named by its user-facing text
Trigger: the user pastes a changelog sentence (often Indonesian) and says "revert this".
1. **Locate the change, not just the text.** Grep the sentence in the repos (`CHANGELOG.md`,
   webapp `ChangelogEntries.ts`), then `git log --all --oneline -S "<phrase>"` for the changelog
   commit, then the run's `docs/<run>/tickets.md` + `spec.md` (grep the topic words) to get the ticket,
   decision ids, audit finding and the code commit hash. `git show --stat <sha>` + the diff of the
   source files.
2. **Split the line into its separate behaviours.** One changelog sentence often bundles 2-3 unrelated
   fixes from one ticket (e.g. an access check + a settings guard + a sync rule). Table them: #,
   behaviour, files.
3. **Find what built on it since.** `git log <sha>..develop -- <files>` and grep the helper/param it
   introduced: later fixes often copy the same rule to a sibling (customer -> supplier) or reuse a
   shared param. Note what was ALREADY in place before the commit, so the revert does not remove more
   than the line describes. Check release state ("Belum dirilis" vs a released version).
4. **Ask scope with options** (recommended first, consequence each): which behaviours, include the
   later siblings or not (inconsistency if not), branch vs develop. A security/access or money-guard
   revert reopens what an audit closed: say exactly what a user could do again.
5. **When the user asks "explain X" before choosing, answer that and stop.** Explain each behaviour in
   plain terms: who is affected (the permission matrix from the access service), before vs after per
   endpoint (list / detail / create / delete / void), what stays restricted elsewhere, and what a revert
   reopens. Ask whether something real is blocked; often the right fix is data/config (grant the user
   access) rather than removing the guard. Then re-ask the pending scope question in one line.
6. Record the chosen scope as a decision before dispatching; the revert gets its own changelog item
   (never delete the past entry if it was released).

## Pitfalls
- An empty answer from the clarify tool is NOT a choice: don't proceed, ask again in chat with the same
  options.
- Removing the field's helper can leave a sibling variable (e.g. "expedition changed") still needed
  by other fields: tell workers to keep surrounding logic and stop if removal changes non-field
  behaviour.
- "Keep the column, stop reading/writing it" (TypeORM `select: false`) is the zero-risk retire option
  when production data matters; see `deploy-data-scripts`.
