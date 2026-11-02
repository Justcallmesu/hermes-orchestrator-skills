---
name: pm-release-readiness
description: "Use for port/feature progress or browser-QA handoff."
---

# Release readiness: progress reports and manual-QA handoff (PM side)

Covers two recurring asks: "how far is the port / the feature?" and "write the prompt so another
agent (e.g. Claude Code + Claude in Chrome) can browser-test it". Read the project's `PROJECT.md`
first (`pm-workspace-resume` if paths look stale).

## 1. Feature-branch status
1. Branch, HEAD vs `git ls-remote origin refs/heads/<branch>`, commits ahead of `main`, `git status`.
2. Read the dated `## CURRENT` block of `STATUS.md` and the board's "TODO (user)" / "NEEDS-USER" rows.
3. Test evidence: the last full-suite logs (`grep -h '^Tests:' runs/final-verify/*.out`). Failures that
   also fail on the pre-feature baseline are not the feature's; say so with both numbers.
   Take that baseline with the same gate script on the clean new branch BEFORE builders edit it;
   when builders are dispatched at once, their brief's first step is to wait until the baseline's
   code copy exists (the gate copies the worktree at start).
   A suite that fails more on the branch than on the baseline is not a regression until it has
   been re-run ALONE on a fresh DB, like the baseline: suites with capped lists ("latest 200") fail
   from data earlier suites piled into the same DB.
   Evidence counts only with `0 skip` on the feature's own suite: API suites often skip whole
   sections (direct-DB checks) when an env var such as `TEST_DB`/`TEST_SCHEMA` is unset and still
   print green. Grep the suite's skip conditions, export them in the gate script, and assert schema
   changes directly (`information_schema.columns` nullability/default) instead of trusting a report.
4. Report: build state, test numbers, what only the user can do (browser checks, deploy SQL by a
   human, merge go-ahead), backlog count and whether any of it blocks.
4a. "How many tickets left?" mid-run: count COMMITTED tickets from `git log` + the board, not from
   the last status line. Approved-but-uncommitted (held for a fix-up) is not done, and a split or
   fix-up row does not add to the total. A wrong "N of M" that the user notices has to be corrected
   openly in the next answer: say which earlier figure was wrong and the right one.
5. "Detail me the tickets you finished": build it from the board and
   `git log --no-merges main..<branch>` per repo (never from memory), grouped by repo. Per ticket:
   id, the user-facing bug numbers they know (e.g. WhatsApp numbering), plain-language effect,
   follow-up tickets folded in, commit sha. Then side work (merges, off-branch tickets with their
   author), checks run, NOT verified, skipped by the user, and found-but-deferred rows.
6. "Turn it into text format": the user pastes reports into chat apps. Give one fenced plain-text
   block: a header (date, branch, status, push/merge state), `=== SECTION ===` headings, one
   `Txx – Bugs a, b – commit <sha>` line per ticket with `-` bullets under it, no markdown tables,
   bold or links. Keep the content identical to the table version.

## 2. Port parity vs an old app
The old app may not be a git checkout; compare trees, not history.
1. Inventory both sides by SCREEN (old webapp `routes/<Area>/` + `views/<Area>/` vs new `Views/`), and
   by backend module.
2. Collect recorded decisions before calling anything missing: grep the knowledge docs for
   `not ported|replaced by|superseded|out of scope`. A recorded "not ported" is a decision, not a gap.
3. For the rest, count each old name's hits in the old webapp vs the new frontend + backend (old 20 /
   new 0 = likely missing). Put the grep loop in a script file: long inline loops trip the command
   scanner.
4. Report three groups with citations: ported, decided not ported, likely missing. Label the last group
   ASSUMED (name search only; renamed features show as false gaps). Offer a fresh-agent gap matrix
   (old route -> new equivalent or none) and let the user decide port / drop / later per row.
5. "Check deeply": fan out read-only auditors, one per functional area, from one shared brief file;
   merge their reports into a summary with a settled-% per area. Recipe, status vocabulary and
   counting rules: `references/port-gap-audit.md`.
6. Old screens with no live route (a router file the old `App.tsx` no longer renders, a commented menu
   entry) are OLD-UNUSED, not gaps: check the old app's live router before counting a screen. A
   name-match-only first pass overstates the gap list for exactly these screens; correct it in the
   deep report and say which earlier claims were wrong.
7. Follow-up on one report family ("how about the vehicle/operator report like the old app"): diff
   columns, tabs and drill-down routes, then split gaps into frontend-only vs data-model changes;
   recipe in `references/port-gap-audit.md` §4 (§4b when the gap is money shown from another
   document: stored link instead of a guessed join, shared price-redaction predicate).

## 3. Browser-test prompt for an external agent
Write it as a file beside the board (`docs/<feature>-tickets/BROWSER-TEST-PROMPT.md`), then summarise.
1. Collect EVERY manual smoke list: `grep -lniE 'smoke|browser|manual' runs/*/build-report*.md
   runs/*/review-report*.md`, cross-checked with the board's user rows. A frontend fix whose smoke list
   lives only in its build report has no board row and is easy to drop; include it and say it was missing.
2. Read each list in full. Per section: ticket, source file + item numbers, a short guide, and the
   instruction to run every numbered item from the source. Copy each expected result's wording
   verbatim when summarising: a shortened check changes its meaning ("fits the viewport at a ~375px
   phone width" became "drawer at ~375px width" and the tester failed a correct 900px desktop drawer).
   Name the viewport size or role each check needs.
3. Check which DB can serve the run, read-only (table counts in the `.env` DB and other local DBs). An
   empty or pre-feature DB cannot exercise the screens and the dev DB must never be written. Default:
   throwaway DB, backend started on it with synchronize, seed, and a hard stop if the startup log shows
   the real DB.
4. List the data to build through the UI (every document chain the lists need, edge cases such as a
   document with 0 lines). States only a deploy script creates get ONE allowed SQL statement on the
   throwaway DB, logged in the report; steps needing legacy data are BLOCKED, never worked around.
5. One role per permission tier the lists test, created in the app; the agent asks the user to type
   every password and never writes one down (repeat that the report must not contain passwords or
   where the seed password lives). Users of different tiers at once need separate browser
   profiles: the app keeps its session in localStorage, so a second login in another tab logs out
   the first (concurrent-edit / 409 checks are impossible in one profile).
5b. Checks that assert a request or response BODY (a key absent from a PUT, fields in a GET) need
   DevTools Network body inspection or a DB query; browser-agent network tools often show only
   method/URL/status. Say which evidence counts for each such check.
5c. Order the data build so states are not consumed before every role sees them: a review-queue item
   resolved early by the admin leaves nothing for the view-only role; master-data changes (box size)
   go BEFORE the dependent document reaches a terminal status if the check needs it editable. Tell
   the agent to make one fresh fixture per destructive check. Re-runs: §3c.
5d. Before dispatch, check the seed runs on a fresh DB (`yarn seed` against the throwaway DB);
   a seeder that assumes rows nobody seeds stalls the agent at setup. Put the workaround (create
   the rows through the app's own screen) into the prompt and a backlog row for the seeder.
6. Rules in the prompt: no repo edits, commits or fixes; output only under
   `runs/browser-check-<date>/`; PASS / FAIL / BLOCKED per step, screenshot + request/response for a
   FAIL; a "needs the owner's call" list for conventions reviews flagged as acceptance questions; stop
   the dev servers; ask before dropping the DB.
7. Log the prompt on the board. When the report arrives, each FAIL becomes a fix ticket on the feature
   branch; all PASS leaves only the merge / production-build decisions.
8. Size it when asked "how many / how long": count tickets and numbered checks per section, estimate
   setup + data build + checks (~1-3 min per check for a screenshot-driven browser agent) + report as a
   range, name what stretches it (password prompts while the user is away, a long document chain
   that can block a whole section, context exhaustion), and offer a split into 2-3 sessions writing
   one report.

## 2b. Version bump + changelog ("bump the version and add changelog")
0. Size the bump before running anything: `git rev-list --count origin/main..origin/develop`,
   `git log --first-parent --oneline origin/main..origin/develop` and `git diff --name-only
   origin/main origin/develop -- src/migrations`. A bump releases EVERYTHING on develop since the
   last tag (other people's features, migrations, app-stopped steps), not just the feature that was
   just merged. Then ask where, in one form, recommended first: prepare the release on `main`
   locally (merge develop, release script, no push), release on `main` and push (= deploy when the
   workflow triggers on `main` + `package.json`), or bump on `develop` only (commit + tag + push
   develop, no deploy). Also ask minor vs patch with the resulting numbers per repo.
   For the develop-only choice: run the release script on `develop` in the main checkout (preflight:
   on develop, clean, == origin, the target tag absent locally AND on the remote), typecheck the
   webapp after the script stamps the in-app entries, then push `develop` fast-forward and the new
   tag by name (`git push origin v<x>`; plain `git push` does not send tags). Report that the later
   `main` release must reuse these versions and tags (re-running the script would bump again), and
   that the changelog date is the machine's clock (`new Date()` in the script), which may differ
   from the conversation's date.
1. Clean tree in each repo; read the repo's release script (`scripts/release.mjs` or what
   `PROJECT.md` names) instead of bumping by hand: it moves "Belum dirilis"/"Unreleased" under the
   new version, stamps the in-app changelog entries file, commits and tags.
2. Before running it, tidy the unreleased notes: merge entries that repeat each other (follow-up
   tickets add overlapping lines), add user-visible fixes found in review (e.g. a race fix) as
   "perbaikan", keep the in-app file free of endpoints/tables; commit that separately. Type-check
   the webapp after editing the entries file.
3. Bump kind: new feature = minor, fixes only = patch; each repo bumps from its own version.
4. Run with `GIT_AUTHOR_*`/`GIT_COMMITTER_*` env set to the confirmed author (the script commits
   and creates an annotated tag with whatever identity is active). A repo doc naming a different
   author than the user is not confirmation: ask before the first commit, then set it with
   `git config --local` (leave the global config alone). Fast-forward any worktree branch
   to the release commit. Report version old -> new, commit, tag, and that nothing is pushed
   (`git push --follow-tags` only after the user's OK).
5. An empty "Belum dirilis" entry right after a release is by design (the script opens it for the
   next changes). Before explaining where users see it, read the changelog page's filter: it may be
   shown only in dev builds (`import.meta.env.DEV`).

## 2b-i. "Merge the run branch into main, bump, changelog" (one request)
Order matters; each step is its own commit so the user can review them apart.
1. Per repo: branch `main`, clean tree, no worktree holding `main` (`git worktree list`), and
   `git log <branch>..main` (commits that landed on main meanwhile, e.g. a side ticket).
2. `git merge --no-ff --no-commit <branch>`. Resolve conflicts so BOTH sides' behaviour survives
   (e.g. main hides fully-used rows, the branch disables already-picked rows: filter AND disable),
   with one comment naming both rules. Never take one side.
3. Gate the uncommitted merge on an `rsync` copy of the working tree (fresh DB, the suites both
   sides touched + the run's new suites), typecheck/unit/check scripts on the real tree. Only then
   commit the merge from a script asserting `.git/MERGE_HEAD` and no conflict markers.
4. Changelog commit: technical lines in each `CHANGELOG.md` "Belum dirilis" (one line per area, its
   test suite), user-facing items in the in-app entries file (plain language, no endpoints, kind
   `baru`/`perbaikan`/`perubahan`). Verify each line against the code it describes (the migration's
   actual WHERE, the util's actual rule), not the board or spec summary: a draft line said "same
   product + unit" where the backfill matched product only. Write in the language the file's
   existing entries use (read the top entries first; these repos keep technical notes in
   Indonesian too). Typecheck the webapp after editing the entries file. Recipe for a feature's
   own changelog ticket: §2b-v.
5. Release script per repo (2b steps 3-4). Author: the identity the user named for this request or
   the repo docs' current rule; it can differ from the run's earlier commits, so ask if unsure.
6. Report a table per repo (merge sha, release sha + version, commits ahead of origin), the bump kind
   and why, the conflict and how both sides were kept, the gate numbers, NOT verified, and the
   user's next steps (backup, deploy, `git push --follow-tags`). Offer to delete the run branch.

## 2b-iv. "Merge to develop and push" (approved)
00. "Merge it, I want to test in develop" while the feature is still UNCOMMITTED, browser QA is
   pending, or it contradicts an earlier user decision (e.g. "commit only after QA passes, no
   merge"): run no git command, not even a read-only probe script, and do not load the merge skill
   or write merge scripts first: the reply below is the FIRST action of the turn. Reply first with a short table
   of what has to happen or be accepted:
   - commit first;
   - the QA gap: untested code lands in develop;
   - server + webapp must land together when the payload contract changed;
   - develop may have moved, which means a re-gate;
   - changelog not yet written, so a second merge follows;
   - push = the team gets it, and possibly a deploy.
   Then give options, recommended first: test on the running QA stack without merging; local
   `--no-ff` merge with no push; merge + push. The user reads jumping straight to tooling as
   treating a big step as trivial. Record the chosen option in `decisions.md` as a change of the
   earlier decision.
0a. Preview first (`git fetch`; `git rev-list --count HEAD..origin/develop`; `git merge-tree
   --write-tree --name-only HEAD origin/develop`). If develop moved and CODE files conflict, the
   approval does not make it a one-script merge: say so in the same turn (which features landed,
   which files, how each hunk will be resolved, push held until gate + fresh review), then follow
   `git-branch-integration` steps 3-4 and 8b (develop INTO the feature, resolve, gate merged vs
   develop alone, review, commit the merge on the feature, then `--no-ff` into develop + push).
   The final report adds post-merge leftovers as numbered user calls (e.g. stored statuses a new
   rule does not recompute on existing rows: leave vs one-time backfill).
0. Before RECOMMENDING the merge, list open client questions of any related feature that touches the
   same money or readers. If an answer could invalidate the merged logic (a cash payout the client may
   turn into a bill deduction), recommend holding on the branch, or say plainly that develop then
   becomes undeployable until those answers land. Merged-but-wrong money code blocks every deploy of
   develop and must be removed with migrations later.
1. One script, per repo: on the branch, no tracked changes, `fetch`, local develop ==
   origin/develop, `merge-base --is-ancestor develop <branch>` (true = the branch gate still holds;
   false = re-gate the merge result), typecheck both repos, `checkout develop`, `merge --no-ff`,
   assert `git diff --quiet HEAD <branch-sha>` (merged tree == gated tree), `merge-base
   --is-ancestor origin/develop develop`, `push origin develop:develop`, re-fetch, print local ==
   remote. Read `.github/workflows` first and say whether develop pushes deploy (usually only main).
2. "Finish run B, then merge and push" while a finished, gated feature A awaits merge approval: the
   instruction covers A too only if the user said so; otherwise state the order you take (A first so
   B branches from it) before acting, and record it in `decisions.md`. Approval covers develop only.
3. Report: merge sha per repo, local == remote, no deploy triggered, NOT verified (browser flows),
   the release-time notes (migrations, app-stopped steps, finance notice).
4. Merge locally first and ask "push?" as its own one-word question (gate summary + shas + "push does
   not deploy" from the workflow `on:` block). Expect `origin/develop` to have moved by the time the
   user answers: the push script's fast-forward assert stops it. Report that in the same turn (who
   landed what, which files conflict, "push held"), merge `origin/develop` into local develop
   uncommitted, resolve changelog-only conflicts by script, re-gate the staged tree including the
   incoming commits' new suites, then commit and push without asking again: the user's "push" still
   covers the same feature on the newer base. Code conflicts are different: stop and ask
   (`git-branch-integration` step 8). A suite that came in with the incoming commits and fails on
   the merged tree: run it on a plain `origin/develop` copy (own DB) and diff the FAIL labels; same
   labels = inherited, so commit, push, and add a board row for that feature's owner. In the reply
   say it is not this feature's failure and give both runs' counts.

## 2b-iii. "Merge to main, I want to check" (local only, no release, no push)
1. Per repo: `git fetch`; assert `origin/main` is an ancestor of `main` and `main` of each feature
   branch; note which checkout holds `main` (`git worktree list`). The user's own checkout may sit on
   another branch: never switch it.
2. Single branch on top of main: fast-forward without a checkout, `git fetch . <feat>:main`.
   Several branches into one repo: add a temp worktree on `main` (`wt/<repo>-main`, symlink
   `node_modules`), `merge --ff-only` the first, `merge --no-ff` the rest with the confirmed author.
   Both forms are refused once the user's own checkout holds `main` (they switched to check it):
   then merge in their checkout, only after asserting it is on `main` and clean; never if dirty.
3. Parallel branches nearly always conflict only in the unreleased changelog blocks (both append
   to "Belum dirilis" in `CHANGELOG.md` and the in-app entries file): keep both sides' entries, no
   markers left, then typecheck + check scripts on the merged tree before committing the merge.
   Re-merging a branch that REWORDED its own already-merged line conflicts on that line: keep main's
   other entries and take the branch's new wording (keeping both duplicates the item). Resolve with a
   small script that asserts exactly one conflict block per file and no markers left, rather than
   piecemeal marker edits.
4. Remove the temp worktree afterwards, then give later shell calls an explicit `workdir`: a
   terminal session left inside the deleted directory fails every command.
5. Report per repo: new `main` sha, what it contains, conflicts and how both were kept, commits
   ahead of `origin/main`, that no version bump or push happened (push = deploy, §2c), and how the
   user checks it (`git checkout main` in their checkout; any new migration to run). A running QA
   stack built from one feature worktree does not contain the other branch: say so.

## 2b-v. Feature changelog ticket on the branch (last ticket before merge)
1. Draft all texts in one scratch file under `runs/X/` first (in-app entries, each CHANGELOG.md),
   check each claim against code, then patch the three files at the top of "Belum dirilis".
2. The server deploy line carries, in order: migration name + what its backfill touches, the
   read-only pre-count to run first (and who decides), "app stopped", settings users must switch
   on themselves (default OFF settings do not ship enabled), and "server + webapp ship together"
   when payload shapes or rounding changed on both sides.
2a. "Is the pre-count SQL needed, or is there another way?": answer from the migration itself.
   When its backfill is narrow (only ported rows matching one pattern), flag-only (no money, stock
   or quantity columns) and reversible by one UPDATE, the count is a safety check, not a gate. Say
   that, name the one risk the count would reveal early, and offer options: deploy to the training
   DB first and check real documents in the app (recommended when training mirrors live), let the
   PM run the read-only SQL once access works, or skip. Mark "training mirrors live" as ASSUMED.
   Prove the prepared SQL on a local DB first: wrap it in `BEGIN TRANSACTION READ ONLY` ... `ROLLBACK`,
   repeat the migration's WHERE verbatim in each CTE, and on a non-ported DB fake the mapping table
   with a TEMP table holding one known document, so every query runs and returns the expected count.
3. The in-app entry names the setting path the user must enable ("Pengaturan > Sistem") and what
   did NOT change (e.g. purchasing untouched) when a rule is side-specific.
4. Commit from a script that hashes the changed files, typechecks the webapp, and commits both
   repos with the shared commit script.
5. Repo agent-instruction files (`CLAUDE.md`, `AGENTS.md`) are approval-gated writes. If the
   prompt times out, do not retry or route around it: leave the proposed text in the ticket report,
   tell the user where it is, and write it only after an explicit yes.

## 2b-vi. "How do I do <business case> with the new feature?" (user's own numbers)
Answer from the branch's code, not the spec summary:
1. Read the allocation order and the eligibility rule (file:line).
2. Walk the user's exact amounts through it: which invoice gets what, which keeps a remainder,
   which box to tick, which setting limit applies.
3. Name the screen steps (e.g. switch order to "as listed", pick the target invoice last).
4. Then state what the feature does NOT do with those numbers and the refusal message the user
   would see. Name the different concept it actually is (write-off/discount vs rounding) as a
   separate feature to scope.
5. End with one question that tells the two readings apart, and note that the example was not
   clicked in the browser.
6. A symptom report while the feature is unmerged ("it can't be rounded", "it reset"): first
   ask which URL/stack they used. `develop` and the user's checkout still run the OLD code until
   the merge, so a check there tests nothing new; name the QA stack URL that has the feature.
   Then list the causes the code allows for that exact symptom as a table (cause, what the user
   sees, fix), and ask for a screenshot showing the amounts and the disabled control's tooltip.
7. When the symptom persists on the QA stack, stop guessing and replay the user's exact amounts on
   the stack's PREVIEW endpoint: a read-only `.mjs` probe that imports the suites' test client
   (login inside the script, no password in the call), run via `bash <file>`. Show the split it
   returns as a table (amount, rounding per invoice), whether your amounts or another input caused
   the symptom, and what the code does instead.
   When the complaint is "the number is wrong" (a 0,5 where they expected 1), first compare the
   fixture's stored amounts with the user's example. If the fixture is the cause, own the mistake
   in one line, fix the fixture, re-run the probe and lead with the corrected table. Do not
   explain the rule over the wrong data. A complaint that "it should be counted"
   often means the user expects a different ALLOCATION rule (each picked invoice paid down to a
   round figure) rather than a bug: say that, and give rule options with a worked example, not a fix.

## 2b-ii. "Is there any breaking change?"
Answer in two layers, verdict first:
1. Semver-breaking: removed/renamed endpoints or fields, required new inputs, new migrations,
   deploy-order dependency between server and webapp. Usually "no" for a fix release; say why.
2. Behaviour changes users or old data will notice, as tables: inputs now refused (who hits them),
   numbers that change on EXISTING data immediately (computed live, stored status not recomputed:
   name it and suggest telling finance before deploy), screens that show more/less.
3. End with what is not affected and the one integration question (other API clients such as
   import tools or scripts) you could not check.
4. "Explain the finance notice" (a fix makes live-computed reports change for PAST periods), in
   the user's language:
   - Lead with what changes and what does not: the documents and the amounts billed stay the same;
     only the report figures change, because the report was miscalculating before.
   - Show a before/after table of which surfaces counted the item (invoice, receivables, each
     report), plus one real example from the ticket's test (document vs report figure).
   - Say WHY old periods move: reports are recomputed from the documents every time they open,
     not archived, so last month's printout no longer matches.
   - Give one row per figure: which ones rise and under which setting (tax only when "X kena PPN"
     is on), and which stay unchanged by decision (cite the decision id).
   - Add the external-filing risk as ASSUMED: if past tax returns were filled from this report, they
     may be understated; if they came from the tax invoices, they are likely fine. Finance or their
     tax advisor decides any correction; the PM does not.
   - Mention any display gap left in the backlog (columns that no longer add up).
   - Close with a short paste-ready message for finance, in plain language with no technical terms.

## 2c. Push ("is it good enough for push" / "push now")
1. Before answering "ready to push", read `.github/workflows/*.yml` triggers. A workflow on
   `push: branches [main]` + `paths: [package.json]` means a pushed version bump IS a production
   deploy (build, migrations on every prod DB it names, tag). Say that first, with the DBs and the
   backup step it runs, then the verified / not-verified table; never-browser-tested screens are
   the main residual risk, so offer "browser check first" (recommended) vs "push now".
   When the push carries everything on develop (other features, app-stopped migrations, manual
   backfills, new permissions), ask once more in a clarify form naming those consequences, with
   "prepare the deploy steps first" recommended; an explicit "push now" there is the OK.
2. On the user's OK, push from a script: per repo assert branch `main`, clean tree, HEAD tagged,
   then `git push origin main --follow-tags`; afterwards `git fetch` and confirm `origin/main` ==
   HEAD and `git ls-remote --tags origin <tag>` exists.
   When the release commit + tag already sit on `develop` (develop-only bump, §2b) and no checkout
   holds `main`, push the develop sha straight to main: preflight every repo first (`origin/develop`
   == the released sha, its `package.json` version, `origin/main` an ancestor of it, 0 commits
   `origin/develop..origin/main`, tag present on origin), then `git push origin <sha>:refs/heads/main`.
   No local main, no merge commit, no second release bump.
3. Push is not done until the deploy is: `gh run list -R <owner>/<repo> -L 2` to get the run ids,
   then a background script with `gh run watch <id> --exit-status` per repo (notify on exit) and
   `gh run view <id>` for the job list. Report each run's result, duration and jobs; mention
   workflow deprecation annotations as a backlog item, not a failure.
   Then read the deploy job's log (`gh run view <id> --log | grep -iE
   'dump|backup|migrat|applied|seed|restart|version'`, strip ANSI) and report what the deploy
   actually did: the backup dump paths, which DBs/tenants migrated, whether the app was restarted
   BEFORE or AFTER the migrations (after = old code served during the migration window, which the
   changelog's "app stopped" steps warn about), and the version/commit the API answers.
4. List what CI did NOT do, from the release's changelog deploy notes: manual backfill scripts
   (dry run, then apply with the app stopped), permission grants to roles other than Super Admin,
   finance notices, settings to check (e.g. a cap setting the new feature needs at a minimum value).
   Close with the short production smoke the user should do (one new document per changed flow,
   one legacy-data path, the changelog page) and record the push + run ids on the board.

## 3a. Final whole-feature check before pushing `main` ("check all")
Per-ticket reviews see one diff each; bugs that live BETWEEN tickets (a column one ticket reads
and no ticket writes) only show up when the whole feature is read as it will land. Run this after
the main-into-feature merge is committed and before asking for the push OK. Push nothing meanwhile.
1. Mechanical sweep from one read-only script: local HEAD == `origin/<feature>`; `origin/main` is an
   ancestor (fast-forward); every ticket sha is in HEAD; `git rev-list --count HEAD..origin/main` = 0;
   no conflict markers (`git grep -nE '^(<<<<<<<|>>>>>>>) ' HEAD`); worktree clean; files changed by
   BOTH sides since the base; leftover throwaway DBs dropped; the user's checkout sha and its
   uncommitted files unchanged; open board rows.
2. Fan out 2-3 FRESH read-only reviewers in one call, split by flow area (e.g. totals/linking/QC;
   reports/frontend/deploy) plus one INTEGRATION reviewer (files auto-merged from both sides,
   transactions/notifications of the other side, constructor order of hand-built services in specs,
   both changelogs intact, deploy note order). Each traces flows end to end through callers, gets
   the spec decisions and the board's known B-rows ("do not re-report unless worse"), writes its
   report to its own file as it goes, and returns SHIP / SHIP WITH FOLLOW-UPS / DO NOT SHIP with
   file:line and a concrete failing scenario per finding.
3. Tell every reviewer to verify each column/field the feature READS has a non-spec WRITER
   (`grep -rn '<field>\s*=\|<field>:' src | grep -v spec`). Specs that seed a column directly pass
   all gates while production always reads NULL/0; tests must seed through the real write path
   (submit the report, approve the QC), not by setting the column.
4. Before acting on a blocker, re-verify it yourself in code and the old app, including what the
   "unset" column actually holds in the table: an ORM transformer may store 0, not NULL (one project's
   `ColumnNumericTransformer` does), so fall back with `COALESCE(NULLIF(col, 0), other)` and assert
   unset in raw SQL with `COALESCE(col, 0) = 0`; a fix built on `IS NULL` still returns 0. Then a fix
   round with one shared definition, red-then-green tests, regate, re-fetch `main` (it often moves
   during the round: merge it again and regate), and a fresh SHA for the push OK.
   Findings that are not fixed become board rows (user call with options vs tech, low).
5. Reply: push or not first, then the blocker in plain language (cause, effect if shipped, fix),
   a reviewer/verdict table, and any user call with options, recommended first.
6. Every open user decision in a status or "what's left" reply is self-explaining: what the
   question means, why it matters (which screen/number goes wrong), one concrete example with
   numbers, and the options table with consequences. A bare board id plus a one-line gloss
   ("B26: is any unit km-metered?") gets "what is this?" back and costs a round trip.
7. When the answer to a fact question ("are there km units?" -> yes) opens a design choice, record
   the fact as a decision id, verify in code what the system can and cannot tell apart (e.g. no
   meter-type field on the entity, which inputs share one field, which totals the wrong unit would
   reach), then ask the follow-up options plus any scope question that changes the recommendation
   ("are those units on HM contracts?") in the same reply. Batch decided items touching the same
   file into one ticket, built after the open choice is answered. When the user picks the small
   option but the scope answer shows the big one is the real fix (picked "hint only" while the units
   DO reach contract totals), build the small one and put the uncovered paths on the board as a
   user-call row naming the real fix; say both in the reply.
8. A worker that stops on "something else reads X for this purpose" usually found a real path.
   When the fix only applies a decision already made, verify the path, decide it as PM (technical),
   append an "Addendum (PM)" to the same brief (file:line, rule, type pitfalls, tests) and
   re-dispatch; ask the user only when it changes what a screen or report shows.

Attack items that recurred in this kind of review, so put them in the briefs:
- A per-ticket review finding that concerns an EARLIER ticket's code becomes a board row at once;
  noted only in that review file it is lost and resurfaces as a release blocker.
- Timestamps sent as UTC (`...Z`) and formatted with plain `dayjs(at)` show in the browser's zone;
  a global `dayjs.tz.setDefault` does not affect plain `dayjs()`. Format with
  `dayjs(at).tz("<business zone>")` and test with real `Z` strings under several `TZ=` values.
  Offset-less fixtures hide the bug.
- Deploy notes: one numbered list in execution order (pre-boot ALTERs before the sync boot, checks
  that may not apply, seeds), plus rollback (an old build with schema sync re-creates changed
  column types by drop+re-add).
- Background job status: read the log's own final marker or the process status, never
  `pgrep -f "<script>"` (the polling command matches itself and reports RUNNING forever).
- Dropping a source from a computed value: also grep writers that COPY that source's field into
  another source table; the copy keeps feeding the number. Filter copies on read by identity with
  their origin (same value and time, millisecond precision after a JS Date round trip), matched
  against ANY origin row of the same owner (`NOT EXISTS ... origin.owner_id = copy.owner_id`), not
  only the currently linked one: relink paths move the FK to a later origin while the copy keeps the
  first origin's value and time, and the copy counts again. Test the relink case through the real
  writer, plus a mutation run per exclusion clause (soft-delete filter, ms truncation).

## 3b. Merge readiness ("can I merge / force merge?")
1. `git fetch`; commits each way (`git rev-list --count origin/main..<branch>` and reverse), who
   wrote main's side, and a dry run: `git merge-tree --write-tree --name-only origin/main <branch>`
   (lists CONFLICT files, writes nothing). Classify each conflict by risk (money/journal first).
2. Answer what each meaning of "force" does: force-push to main deletes the other side's commits
   (never); "take one side" silently drops a behaviour (a money bug no gate sees); a normal merge
   with untested money paths is the honest moderate-risk option.
3. Recommend merging main INTO the feature branch first, in a separate worktree, and get the user's
   yes (a merge commit is a new commit type). Procedure + gate attribution:
   `references/merge-main-into-feature.md`.
4. A main that moved means earlier status/port answers read a stale baseline: correct them.

## 3c. Targeted re-run prompt (run 2 after a partial run, a merge or a fix)
Write a separate file (`BROWSER-TEST-PROMPT-<run>.md`); never edit run 1's prompt.
1. Gate the start: state which commits must be in the user's tree (`git merge-base --is-ancestor
   <sha> HEAD` as step 1) and that the user pulls first. A re-run on a tree without the pending fix
   tests nothing new. When a ticket that changes behaviour the prompt tests is still in flight, tell
   the user the choice (run now and miss it / wait about N and include it) and add its checks to the
   prompt once it lands. Every time more commits land before the run starts, refresh the prompt's
   "when to run" line and its ancestry sha to the new head, and re-read each fixture step against
   the rules those commits added: a new lock or status rule can make a fixture impossible (an
   "approved, not received" document that must still be edited has no edit form once approval
   locks it; use the pre-approval state instead).
2. Reuse run 1's fixtures: point the agent at run 1's report sections listing DB, accounts,
   document numbers and layer ids; build only the data the gap steps need (one fresh fixture per
   destructive check; re-check master-data values run 1 changed, e.g. a box size).
3. After a merge or schema change: start with synchronize, then re-run only the idempotent seeders
   that carry new rows (permissions, settings, account settings); never users/roles, which would
   clash with the accounts run 1 created. Read the seeder entry point for the per-step command.
4. Steps = run 1's gaps by id, plus a section for behaviour the merge/fix added (new money rows:
   exact expected amounts per receipt and their sum, balanced journal, not in stock cost) and a
   section for screens the merge touched (menu union, permission-gated views, a crash smoke of the
   other side's new screens).
5. Before writing a step that needs a specific user path (reverse an approved document, deny a
   check), find the real path in the code and name the screen action; a guessed path turns the
   step BLOCKED.
6. Strict result rule: PASS only when every part was observed; a partly seen check is NOT TESTED
   with the missing part named (run 1 agents report partial observations as PASS).

## 3d. User wants to check it himself before push ("don't push yet, I want to check")
1. Push nothing; record the hold on the board. Start a QA stack from the feature worktree, not the
   user's checkout: scratch backend on a fresh throwaway DB (the side-branch runner, `FRESH=1`) and
   `VITE_PROXY_TARGET=<api> npx vite --port <free> --strictPort --host 127.0.0.1` in the background,
   `node_modules` symlinked, pid files written. Put start and stop in two script files (`qa-up.sh`,
   `qa-down.sh`).
2. Prove it is up before handing over: `curl` the webapp (200) and an auth endpoint through the
   proxy (401 = backend up, not logged in); print the branch + sha each side runs.
3. Hand over: URL, the seed login as a pointer (`file:line` of the test client), never the password
   itself; which DB it uses and that their DBs and prod are untouched. Point to any run file (test
   script, review report) by ABSOLUTE path plus a `MEDIA:` attachment, with the section line, and
   say which steps later fix rounds made stale. A bare `runs/W1/...` gets "where is this?" back.
   Include the fixture names (customer/supplier, document numbers) and one ready-made case with
   amounts.
   Build the fixtures with the user's OWN example amounts (an invoice of exactly 1.001 when they
   said "1.001 -> pay 1.000, round 1"), not convenient values such as 1.000,50. Write every
   worked example in the report with those same amounts. Why: the stack then shows a different
   result (rounding 0,50 instead of 1), and the user reads correct code as a bug. If a fixture
   already differs, say so in the hand-over and correct it on the throwaway DB before they click.
   An item price changed in SQL on that DB is enough, because invoice totals are derived from the
   items; confirm with a preview probe afterwards.
4. An ordered check table (step -> expected result) that builds its own data first (master-data
   values such as a small credit limit and a tempo), then walks each changed flow, then one edge case
   (customer without tempo / legacy data). Ask for "what you clicked, what appeared" on any mismatch.
5. Leave the stack running until the user says done, then run `qa-down.sh`. After a schema ticket
   commits, restart the backend by port, not pid file, and prove the new process and column exist
   (`references/qa-stack-on-dev-db-copy.md` "Restarting the backend").
   A scratch backend runs a COPY of the server worktree taken at start, while vite serves the
   webapp worktree live. Every later server ticket therefore leaves the stack on mixed code (new
   webapp, old API contract). Before handing QA back after server fix rounds, re-run the stack's
   up script on the same DB and fixtures. The rebuild re-copies the tree and deletes any probe
   files you dropped into the copy, so keep probes in a script outside the copy, or rewrite them
   for the new contract. Then replay the user's own failing case on the preview endpoint and lead
   the hand-over with that table (amount per row, rounding, reason code). Say that it was checked
   through the API and not clicked in the browser.
5-i. "Is it all done?" while the stack runs: answer yes/no for BUILD first, then one table of what
   only the user can do (browser check, merge go, post-deploy seeding + role grants, dev-DB fixes
   found while setting up), then the non-blocking backlog, and ask whether to do the backlog now or
   after his check results. Number every open item and pending decision id: the user answers by
   number ("3. sure 5. sure"), so each number must map to exactly one item. Write each answer into
   the spec decisions table (marked user-confirmed) before starting the work it unlocks, and say
   back in one line what each number was taken to mean. An answer that rewords a decision ("only
   appear at finish") is restated as the precise rule you will implement.
   Write numbered questions with lettered options (recommended first, consequence each) in the chat
   text itself, even when also using a clarify form: a form that closes unanswered leaves nothing
   on screen and the user has to ask "sebut pertanyaan". If that happens, repeat the full list.
5a. To check with his own data, run the stack on a `pg_dump` copy of the dev DB instead of a seeded
   throwaway DB: backend (synchronize) before seeders, stale enum values fixed on the copy only,
   proxy probed through the real API prefix. Recipe: `references/qa-stack-on-dev-db-copy.md`.
6. A new request arriving while the stack runs gets its own branch in its own worktree
   (`wt/<repo>-<topic>` from `main`): the stack serves files live from the first worktree, so
   building there changes what the user is testing.

## 3e. PM clicks the screens itself
When the PM verifies the finished webapp tickets directly with the browser tool: stack from scratch
build + preview (or the worktree's vite dev server), cookie-injected login (no password typed),
saves verified by the captured request body or a DB query, result table. Run it while the fresh code
review is in flight (both read-only), and lead the report with the user's original failing case.
Recipe: `references/pm-run-browser-qa.md`.

## 4. Triage of a returned browser-QA report
1. Save the report under `runs/browser-check-<date>/` (a pasted copy too) with its sha256; note any
   file the report names that is not on disk.
2. Re-check every FAIL against the code and the ORIGINAL smoke-list wording before calling it a
   defect: a failure caused by the PM's prompt wording is closed as a PM error, not ticketed.
3. Incidental non-feature findings: verify the cheap ones in code (cite file:line). Where the tester's
   explanation disagrees with the code (column names, field labels), mark the row NEEDS-REPRO, not a bug.
4. Count PASS / FAIL / not tested per section; untested money paths (returns, box prices, editable
   documents after a master change) block the merge recommendation. Board rows: one for the run's
   result, one targeted re-run listing only the gaps (reuse the throwaway DB), one per real finding.
5. Reply: verdict first (feature defects found or not), section table, the reclassified FAIL with the
   code cite, the gap list ordered by money risk, incidental findings with VERIFIED / NEEDS-REPRO,
   and any secret the report leaked.
