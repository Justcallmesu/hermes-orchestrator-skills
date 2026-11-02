---
name: legacy-port-progress-audit
description: "Use when asked how far a port is from the old app."
---

# Port progress audit (old app -> rewrite) + feature-branch status

For status questions like "how is the porting progress" or "I added X, what still needs testing".
Read-only. One report, then offer next steps; change nothing.

## Procedure
1. **Locate the trees from `PROJECT.md`** (repos, old-app paths, port status docs). If its paths are
   gone, search `~/Projects` for `*/PROJECT.md`, use what exists and report the stale lines.
2. **Branch the user just mentioned:**
   - branch, `git log --oneline -3`, `git log main..<branch> --oneline | wc -l`,
     `git ls-remote origin refs/heads/<branch>`, `git status --short` (code vs untracked docs);
   - the dated `## CURRENT` block of the feature `STATUS.md` (it beats an older overview file) and the
     board rows waiting on the user (`grep -nE 'TODO \(user\)|NEEDS-USER' tickets.md`);
   - last full-suite evidence (`grep -hE '^Tests:|^Test Suites:' runs/final-verify/*.out`). Attribute
     failures with a base-vs-head pair: same failures on the pre-feature commit = pre-existing;
   - "needs testing" = browser smoke lists workers could not run:
     `grep -rlniE 'smoke|browser' runs/*/build-report*.md runs/*/review-report*.md`; list each with path.
3. **Port coverage in two evidence tiers** (against `origin/main` after `git fetch` when main has
   moved since the feature branched: other developers port whole areas on main, and a feature-branch
   tree reports them missing):
   - VERIFIED: the knowledge/port docs (`grep -rniE 'not ported|replaced by|out of scope'` over the
     knowledge dir gives recorded drop decisions, cite file:line).
   - NAME-MATCH ONLY: list old screens (old web routes + views) and old backend modules; grep each
     feature name as a `PascalCase|kebab-case` alternation in old web, new frontend, new backend, and
     count files. Zero hits in the new code = "probably missing".
   - Label the second tier unverified: renamed or merged features look missing; short generic names
     (`bot`, `Notification`, `Return`) give false hits.
4. **Report:** answer first (is the branch done, what blocks merge), then a check -> result table, the
   user's to-do table (smoke item + file path), a port table by area (ported / decided not ported
   with cite / probably missing), stale paths, and 2-3 next-step options with a recommendation
   (consolidated browser checklist; a fresh agent building an old-route -> new-equivalent gap matrix
   the user marks port / drop / later).

## Pitfalls
- For a deep audit ("check deeply", "all modules", "table of not-implemented / stub features"),
  browser-QA prompts and triage of a returned QA report, follow `pm-release-readiness` (§2-4 and its
  `references/port-gap-audit.md`); this skill is the quick pass. A request for stubs or missing links
  ("X doesn't create a receivable") is always the deep path: name matching cannot see side effects.
- Module status docs lag the code: "design only", "phase N not built" and "report not ported"
  claims each need a grep of the module/entity in the code before they go in a reply (an entity,
  service or `TODO(phase` marker settles it). Answering from docs alone produces confident wrong
  rows that the next answer must retract; after a context compaction, re-verify instead of
  repeating the summary's claims.
- The rewrite often replaces an old snapshot table with a renamed record entity or a live query
  (`*Report` table -> `*Record` entity, or "no table here, computed live from X"). Before calling an
  old table/report "not ported", grep the concept STEM (`Condition|Uncountable|Usage|Position`) across
  new entities, services and frontend Axios configs, and grep the knowledge docs for `computed live|
  no table|no snapshot`. An exact-name miss is not evidence of absence.
- For "how is X used across modules" (a report, a total): list old writers (grep the old
  `generate*`/`save` callers of the table) and readers, then new writers/readers per stored column, in
  one table. This surfaces both missing sources and two writers colliding on one column: a
  SET-from-source recompute next to an `increment`/`+=` writer on the same column erases the
  increment on its next run, and per-writer tests never catch it. Grep the column assignment itself
  (`totalXHm +=`, `increment(..., 'totalXHm'`): an old service that writes a report-table row next
  to the total often never touches the total, so "the old app fed the total from N sources" needs
  one cite per source.
- "Are all reports done / linked?" has two halves; answer both in separate tables:
  1. **Data sources**: run `scripts/old-report-writers.sh <old-modules-dir> <serviceVar>...` to list
     every old call site that writes a report row, with its enclosing method. Dump ~25 lines of
     context around each hit (the `case <STATUS>:` branch tells you the event) and skip commented-out
     calls. Then map each event to the remake writer (`grep` the record helper / recompute callers)
     or to an existing backlog row; a source with neither is a new finding.
  2. **Navigation links**: grep the old frontend views for `navigate(`/`<Link` on each report row
     (row -> TSR, work order, detail) and compare with the new view; every new link must be
     permission-gated.
  Before reporting a link as missing, check the other unmerged branches for the report's select list
  (`git show origin/<branch>:<service>`): a parallel branch may already add the ids the link needs,
  so the cheap option is to add the link at that merge.
- Before sizing a missing source as "needs a new input/modal/screen", grep the existing form for
  the field (it may be shown only for one status, e.g. `isBreakdownTarget`) and the DTO/service for
  the payload key (the backend may already store it for the other statuses). Size it as "show the
  existing field for more cases" when that holds, and name what is broken TODAY because the value is
  never sent (e.g. report HM columns empty), not only the missing future source.
- An existing port-gap report is only as good as its baseline SHA: compare it to `origin/main`
  (`git rev-list --count <baseline>..origin/main`, then skim `git log` for feature merges) before
  quoting it; a stale one is re-run, never repeated. For a quick question ("what's missing?"), the
  cheap re-run is: pull the report's MISSING rows (`grep -hE '\| *MISSING' <report-dir>/*.md`), then
  re-probe each row read-only against the remote tree with `git grep -liE '<stem>' origin/main --
  backend/src frontend/src` and `git ls-tree -r --name-only origin/main <dir> | grep -i <stem>`. This
  works from any checked-out branch without a checkout. Put all the probes in one script file.
  Report three groups: still missing (with the cite), built since the report, and not re-checked
  (ASSUMED).
- "Which module is missing?" usually has the answer "no whole module, N features inside existing
  modules". Compare the old and new module/view directory lists first and lead with that answer,
  then give the feature table grouped by area.
- Probe hits that are NOT evidence a feature exists: a permission enum value nothing else
  references (grep the enum key in the module's services/controllers), a commented-out relation
  or entity (`// @ManyToMany(() => Bast`), FAQ/menu/NavigationEnum text, seed CSVs, a hard-coded
  `can<Action>: false` action rule, and a controller that has only `:id/status` routes when the
  feature is edit/delete (list its `@Put|@Patch|@Delete` decorators). Filter those paths out of the
  probe and read the hit line before you count a feature as ported.
- A name-match pass marks old screens as missing that had no live route in the old app (router file
  not rendered by `App.tsx`, commented menu entry): check the old live router before listing them.
- Port / drop for a missing feature is the user's business scope call: list it, never decide it.
- Shell `for` loops with nested `$(...)` trip the approval scanner; keep probes plain or put them in a
  script file run with `bash <file>`.
- Reply in the language the user last wrote in; identifiers and paths stay English.
