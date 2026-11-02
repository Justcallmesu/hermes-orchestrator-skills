---
name: git-branch-integration
description: "Use when merging or rebasing branches. Per-hunk, gated."
---

# Integrate diverged branches without losing code

Applies to: merging a feature into develop, syncing develop with main, rebasing a feature onto
another base, removing release artifacts (changelog/version) from a branch.

## Procedure
1. **Map the divergence first** (read-only):
   - `git merge-base A B`; `git rev-list --count A..B` and `B..A`; `git log --oneline B..A`.
   - Check what base the feature branch was cut from (`git merge-base feature develop` vs `main`).
     A feature cut from `main` carries main's commits into develop: merging it IS merging main.
   - Read every commit subject on the other side. Do not label commits "release metadata only"
     until you have checked: release branches usually carry real fixes and features too.
   - Compare local vs remote of BOTH branches (`git rev-parse --short main origin/main`). An
     unpushed local `main` means the merge brings in commits the remote lacks: tell the user which
     one you merged.
   - List the OTHER unmerged branches too (`git branch -r --no-merged origin/main`) and, for each,
     the files it shares with yours (`comm -12` of both `git diff --name-only <merge-base>` lists).
     A parallel feature branch touching the same entity can implement the same concept with a
     different rule (two writers of one column); that is a business conflict to raise before
     anyone merges, not at whichever merge lands second.
   - When cutting NEW tickets while another branch is still unmerged, run
     `git diff --stat origin/main...origin/<other> -- <ticket files>` on the files each ticket will
     edit; a ticket touching the same service/form is ordered after that merge (dependency column
     on the board) so it is not built twice or conflicted.
   - Baseline the target alone: typecheck + unit tests on the target branch before merging, so a
     pre-existing failure is not blamed on (or hidden by) the merge.
   - A long-running feature branch: re-check `git rev-list --count HEAD..<target>` (and
     `git merge-tree --write-tree --name-only HEAD <target>`) before the final whole-feature review
     and before the first commit, not only at the end. A sibling feature merged meanwhile can drop a
     table/type the feature's migration alters (every tenant migrate then fails), take its test-suite
     number, or change a formula the feature reads; every gate run on the old base stays green.
     Give the final reviewer the target's current sha so it reviews against it.
   - A migration that adds to existing DB objects (enum types, columns of other features' tables)
     guards on the object's existence (`to_regtype(...)`, `IF EXISTS`), since another branch may
     drop it in an earlier-sorting migration; `ADD VALUE IF NOT EXISTS` guards only the value.
   - After merging the target in, list migration files per dir sorted and check for duplicate
     timestamps (`ls src/migrations/<dir> | cut -d- -f1 | sort | uniq -d`): two branches cut on the
     same day often pick the same next number, git merges both files cleanly, and the run order
     then depends on name sorting. Rename the side that was never deployed to the next free number
     inside the merge (file, class name + `name` field, test imports, changelog, spec/board mentions),
     stage it with the resolution, and say so in the report. Name the cost in the report too: every
     DB that already ran the old name (local, QA, worker, staging) runs it AGAIN under the new name
     (a backfill re-applies and can undo manual edits, and the old row stays orphaned in the
     migrations table); prod/training are safe only if they never ran it. So make the renamed
     migration's DDL idempotent in the same merge (`ADD COLUMN IF NOT EXISTS`, `DROP ... IF EXISTS`,
     `CREATE TABLE IF NOT EXISTS`): a plain `ADD` fails "column already exists" on any DB that ran
     the old name, including the gate's throwaway clone of the user's local DB. When a colliding
     migration CREATES a table and local DBs already ran it, leave its number and put it on the board
     as a user call at merge time instead of renaming.
   - When the target moved under a gated, uncommitted feature (incl. "my local copy is not synced
     with the new commits, sync it"), ask the user the order: fix what
     breaks on the new base first, commit the gated work, then merge the target INTO the feature
     (step 8b), or port the diff onto fresh worktrees from the target. On "commit locally, then
     merge develop in": commit explicit paths per repo (leave the user's unrelated dirty files,
     e.g. `.yarn/install-state.gz`), `merge --no-ff --no-commit origin/develop`, resolve, check
     duplicate migration timestamps AND duplicate test-suite numbers (rename the feature's suite to
     the next free number), gate on a throwaway DB, then commit the merge; report both shas and
     "not pushed", then give the user the migrate + restart commands for their running copy. Fix a hard break (a migration
     that fails on the new base) BEFORE the commit, proven on a clone of the target, so no commit
     carries it.
2. **Ask the user before choosing the strategy** when it rewrites history or pulls in many
   commits (rebase vs merge vs cherry-pick only the feature commit). Prefer cherry-picking just the
   feature commit(s) onto the target when the feature was cut from the wrong base. For a
   "develop should contain main" request, a real `git merge main` beats rebasing (rebase replays
   every release commit and asks for the same conflict many times).
   - Order when a feature was cut from `main` and the user wants develop to contain main: merge
     `main` into develop first (resolve once, with decisions), then merge the feature; it then
     applies cleanly because its base is already inside develop.
   - Work on a scratch branch (`git branch -f merge/<a>-into-<b> <target>`) and keep the target
     untouched until gates pass; `git merge --no-commit --no-ff` so the result is staged for review.
   - Before any recovery reset, park the bad state on `backup/<name>` so it stays inspectable.
   - Work that sits on a branch named for an older, already-merged feature: offer a new branch at
     the same tip (`git branch <new> <tip>`, push it, switch the checkout) rather than resetting or
     force-pushing the old one; nothing is rewritten and the old name can be deleted later.
2b. **Surface every business hunk in one round**: do the trial merge in a detached throwaway
   worktree (`git worktree add --detach <scratch>/wt-<name> <branch>`, then `git worktree remove
   --force` + `prune`) whenever the user's checkout has ANY uncommitted change (a `yarn install`
   rewriting `package.json` counts): a trial in their checkout either refuses or tangles their edits,
   and stash is off-limits. Run `git merge --no-commit`, dump all
   conflict hunks with line numbers to a file (awk between `<<<<<<<` and `>>>>>>>`), `git merge
   --abort`, read them, then ask ALL business-rule hunks in one clarify form (2 options each, what
   each side does + what is lost). Record answers as decision ids in a spec before resolving.
   Typical business hunks: price editable vs fixed, edit-after-delivery rules, where a
   field/gate lives (order vs invoice), cancel vs hard delete.
3. **Resolve conflicts per hunk, never per file.**
   - `git checkout --ours/--theirs <file>` keeps the WHOLE file from one side and silently drops
     every non-conflicting change the other side made in it; callers in cleanly-merged files then
     break the build. Never use it on source files.
   - Edit each `<<<<<<<` block: keep both sides when they are additive (imports, new methods);
     comment-only diffs take the newer wording.
   - A hunk that encodes a business rule (e.g. editable vs fixed price, cancel vs delete, where a
     field lives) is the user's decision: stop and ask with options, do not pick a side.
   - In a rebase, "ours" is the branch being rebased ONTO, not your feature: another reason never
     to resolve by side.
   - When one side restructured code (validation moved into row-locked transaction helpers) and the
     other added rules to the old shape, keep the restructured shape and move the other side's
     rules into it; read base, ours and theirs (`git show <ref>:<path>`) for each file first.
   - Delegating resolution: the brief lists the decisions, the "never whole-file" rule, the known
     symptoms of a bad resolution (e.g. tsc errors in cleanly-merged callers) to prove absent, and
     "stage, do not commit". When the standing worker rules forbid `git add`, say in the brief that
     staging the resolved paths is the one allowed exception for this ticket; otherwise the worker
     follows one and reports the contradiction instead of a clean index. Then verify yourself: rerun gates, run the loss check on the index, and
     grep each decision's marker (message text, method present/absent) in the merged files.
   - Review every file git auto-merged with changes from BOTH sides (the loss check's MIXED list),
     not only the conflict files: a clean textual merge can still be semantically incomplete, e.g.
     one side adds a menu item/route while the other side restructured the lookup map that item must
     also be registered in. Diff the staged file against each side and add the missing entry.
   - Both sides adding the SAME member (an entity column, a DTO field, a writer helper) in
     different spots merges with no conflict into two declarations. After resolving, grep each
     conflict file's neighbours for duplicated decorators/fields (`grep -n '<field>:' <entity>`),
     keep one, and merge their options (e.g. one side's unique index + the other's ON DELETE).
   - When one side removed or re-signatured a service/helper, grep the OTHER side's new code
     and specs for it (`grep -rn 'new <Service>(\|<removedImport>'`): its specs construct the old
     shape and only fail at `tsc`/jest, not as a conflict. Fix the spec setup inside the merge
     commit (it is the merge's own breakage, unlike inherited lint).
   - Two parallel implementations of one concept (two private writers of the same record): keep
     the shared one with the lock/invariants, route the other side's call through it with its
     extra field (e.g. operator id), and delete the duplicate helper.
   - Versioned changelog entries where both sides claimed the same next number: keep the side
     that landed on the target first at that number and renumber the other (by date order).
   - Behaviour changes ripple into tests that merged cleanly: a field one side made required, an
     endpoint the other side removed, duplicate suite numbers from both sides. List them as
     tickets; API suites need a live server + DB and are not proven by typecheck.
     Exception: the feature's OWN suites that call a contract the target removed (old request
     shape now rejected) are rewritten inside the merge, since the merged tree is red without it.
     Keep each assertion's meaning; a case the target's rule makes impossible is replaced by the
     nearest valid check or dropped with the reason in the report. Grep the feature's suites for
     the removed fields before writing the resolve brief.
   - When the target MOVED the function the feature changed (a status rule relocated into a new
     util), re-home the feature's rule into the new location; a shared util the feature
     deliberately left untouched (used by another module) stays byte-identical to the target. The
     resolve brief names the target feature's spec as the authority for its domain and adds "stop
     and ask if the target's rule changes a business outcome of ours" (a free line now refunds
     money, billing blocked). Give the fresh reviewer one focus question per re-homed rule: where
     could the combined rule change an outcome versus the target alone (status set at create while
     the target relied on the column default, a guard that now lets a target-settled document
     through), so the review proves the target's behaviour is unchanged except for the feature's case.
   - "Merge to develop and push" that hits CODE conflicts is no longer a one-script merge: tell the
     user in the same turn (develop moved, which features, which files, how each hunk will be
     resolved, push held until gate + fresh review), then run the 8b path.
4. **Gate before every commit/`--continue`**: run the project typecheck (server `tsc --noEmit`,
   webapp `tsc -b`) and ensure 0 errors. A green rebase/merge exit code proves nothing about the build.
   - A gate finding on a file the merge took verbatim from the other side is not a merge
     regression: lint/format that side's blob with the repo config (`git show <other>:<f> |
     eslint --stdin --stdin-filename <f>`, same for prettier). If it fails there too, commit the
     merge without touching it, report it as inherited, and add a board row; fixing another
     feature's code inside a merge commit mixes concerns.
   - Format-gate a merge commit on its RESOLUTION lines only: lines of the merge that differ from
     BOTH parents (`comm -12` of the `git diff -U0 <M>^1 <M>` and `<M>^2 <M>` added-line sets per
     file) intersected with prettier's unformatted lines. A plain changed-lines gate against one
     parent flags the whole other branch.
   - Have a fresh reviewer read the resolution with `git show --remerge-diff <merge>` (shows each
     hunk as resolved vs conflicted) plus the decisions list; read-only, while gates run. Green gates
     do not prove a resolution: combining two sides' rules (a validation one side added, a link the
     other side writes) breaks behaviour no existing test covers. Plan for reviewer -> fix round ->
     second fresh reviewer on the fix; each fix carries a regression test proven red on the pre-fix
     code. Keep the fix uncommitted on top of the local merge commits until the second review passes.
     Red-proof recipe for the brief: back up the fixed source files, write `git show HEAD:<f> > <f>`
     for each, run ONLY the new tests (expect the stated failure lines), restore the backups, confirm
     with `git diff` that the fix is back. Revert source files only, never the new specs.
   - A fix that changes "what counts as X" (free/open/relinkable) must give every path that decides
     it ONE shared definition (an exported check plus the same query fragment/params for the SQL
     path); two copies drift. An existing test that breaks because its setup relied on the old rule
     gets its setup reordered with assertions unchanged, and the reviewer is told to confirm the
     test still covers its title.
   - When a fix relaxes a guard the merge introduced (e.g. stop requiring a record's foreign key to
     equal the value resolved now), trace every downstream consumer keyed on that field before
     calling it done: recomputes, totals, reports, flags. A consumer that derives its target from the
     other entity (recompute the TSR's contract, not the record's) silently leaves the right target
     stale; brief the fix to cover the union of targets, locked in id order.
   - Sequence workers and gates in the scratch worktree: start a fix worker only after the gate run
     reading that tree has finished, and gate again after it; a worker editing mid-run makes the run
     prove nothing.
   - A fix worker cut off mid-run (rate limit, crash): read its partial `git diff` before
     re-dispatching, verify each finished part against the brief, and re-dispatch the SAME brief with
     an explicit "ALREADY DONE in the tree, keep it: ... / REMAINING: ..." list; a blind re-dispatch
     redoes or reverts the valid half.
   - A user decision that lands while a fix worker is editing the same files: steer that worker
     (delegate_task action=steer) with the extra change, its test (incl. the must-fail-before case and
     a negative case) and "same report", instead of a second worker; two writers in one tree clobber
     each other. Record the decision in the spec first.
   - Review leftovers that are not fixed in the round go on the board as rows split into "user call"
     (with the options) and "tech, low"; fix-round findings that are pure implementation are the PM's
     call, recorded in `decisions.md` with the rejected alternative.
   - Lint "the files this feature changed" from `git diff --name-only <base> HEAD`, not from
     `git status`: once the work is committed the status list is empty, and `eslint` with no file
     arguments lints the whole repo, burying the feature's findings under every old one.
   - Gating a merge that must not touch the user's checkout (e.g. another branch into `main`): two
     scratch worktrees, one on the plain target (baseline) and one holding the staged merge; symlink
     `backend/node_modules` + `frontend/node_modules` from the main checkout and copy `backend/.env`;
     when specs read untracked files under a TRACKED dir (deploy SQL in `docs/`), link each untracked
     entry individually (`ln -s <checkout>/docs/<x> <wt>/docs/<x>`): `ln -s <checkout>/docs <wt>/docs`
     onto an existing dir silently creates `docs/docs` and the specs still miss the files;
     point the gate scripts at them (`BACKEND=`/`FRONTEND=` overrides) with an explicit
     `BASELINE_DIR` per run, same test paths for both, then diff the failure lists.
   - Building the merged copy as "HEAD + `git diff --cached --name-only HEAD`": `--name-only` lists only a
     rename's NEW path, so the OLD file survives in the copy and runs as a stale suite. Use
     `--name-status --no-renames` (D rows = delete) or archive the index (`git write-tree` + `git archive`).
     Prefer the index archive: save the `git write-tree` id as the gated tree, and have the
     commit-and-push script refuse when `git write-tree` differs at commit time, so a late edit
     (a reviewer nit) forces a re-gate instead of shipping an untested index.
   - Suites that bind a fixed port (an SMTP test server, e.g. erp-topaz 13-authx on 2526) collide when the
     target and merged runs go in parallel (EADDRINUSE, 0/0). Re-run them alone before calling it a diff,
     on BOTH copies, with the exact env the gate exported (`TEST_DB`, `TEST_SCHEMA`, `PG*`): a solo
     re-run without them prints a setup FAIL ("needs TEST_DB") on both sides that proves nothing.
     Same FAIL on the target alone = inherited; a pass-count difference with 0 FAIL on both is variance.
     "Same" means the same failing LABELS: `grep '^FAIL' <log> | sed 's/ ::.*//' | sort` on both runs
     and `diff` the lists. Equal FAIL counts can hide one fixed plus one new failure.
   - API suites: run ALL of them on the merged branch AND on the plain target, in parallel, each
     from a `git archive <ref>` copy on its own fresh DB and port, then join the per-suite FAIL
     counts. Only a suite that fails more on the merge counts as a regression. Count server errors
     by the real status field (`Status: ... 5xx`), not a bare `5[0-9]{2}` grep, which matches
     "500 characters" in 400 messages.
5. **Measure loss after the merge** with `scripts/merge-loss-check.sh <other-branch> <target-before>
   [<target-after>]` (omit the last arg to check the staged index before committing): every file
   the other side changed is SAME / DROPPED / MIXED, target-side changes that were lost, and for
   each MIXED file how many lines each side added are missing from the result. Any DROPPED file,
   or MIXED file with missing lines, must be justified (a decision id or a kept feature) before
   reporting done.
   - A garbled line in a check's output (a path fragment under the wrong heading) is an output
     problem, not a finding: re-check that file directly (`git rev-parse :<f>` vs `<ref>:<f>`)
     before calling it lost or clean.
   - A second sync of the same target (it moved again after an earlier merge into the feature) can
     show an item BOTH sides already contain inside the "ours" hunk (theirs moved/re-quoted it lower
     down): keeping both blocks duplicates it. Assert in the resolve script that every item occurs
     exactly once (`text.count(<unique phrase>) == 1`) before writing.
   - Gate scripts take the changed-file list from `git status --short`/`git diff --name-only`, never
     a hard-coded list: a fix round that adds a file (a new helper in an existing util) makes the
     copy uncompilable and every suite reports 0/0.
   - Changelog-only conflicts (both sides appended entries under Unreleased) are additive: keep
     both blocks (ours first, then theirs), assert no markers remain, and prove it with 0 missing
     lines on both sides. No user decision needed; a conflict in source code still needs one.
     Exception: a target-side bullet that the feature deliberately rewrote or retired (the feature
     removes what it announces) is dropped, not kept beside its replacement; say so in the merge
     message. Resolve with a script that asserts the marker line numbers and the dropped line's
     opening text before deleting, so a shifted layout aborts instead of cutting the wrong line.
     In a structured changelog (array of `{ kind, text }` items), git often splits the conflict
     INSIDE a shared opening line (`{ kind: "baru",` sits above the markers and each side starts
     with a bare `text:`): concatenating both sides then yields an invalid item. Check the line
     above `<<<<<<<`; close the first side's item and reopen one for the second (`},{ kind: ...`),
     then typecheck the file.
6. **Changelog/versioning removal** is its own commit after the integration gates pass, never mixed
   into conflict resolution. Before deleting anything, ask/confirm the branch flow: if `main`
   (release) is fed by merging `develop`, deleting `CHANGELOG.md`, `release.mjs` or the in-app
   changelog on `develop` deletes them from `main` at the next release. In that flow recommend
   "keep the files, stop editing them on develop; write changelog + run release on main only",
   and offer deletion only as an explicit "remove versioning everywhere" option. Ask the scope
   (changelog file only / + in-app entries / + release script and version display).
7. **Commits and branch moves are the user's**: do not commit merges, `git reset`, or change
   upstreams (`--set-upstream-to`) without explicit approval. Keep the original feature commit sha
   in the report so it can be recovered.
7b. **An answer to the ORDER question is not an answer to the business question.** When the user
   picks a merge order ("A: X into main first, then into the feature") while a business clash was
   also pending, re-ask the clash (with the recommended option first) before resolving those hunks;
   do not treat the order pick as approval of your recommended rule. Likewise "merge X into main"
   under a project rule that the PM never pushes/merges `main` still needs an explicit push OK:
   stage and gate it, then ask push-to-main vs push-as-`merge/<x>-into-main` branch. A bare
   "merge" at the end of a feature run under that rule: ask ONE question (a: integrate, push the
   feature, open a pull request with `gh pr create` and the user presses Merge, recommended; b: the
   user overrides the rule and the PM pushes `main`), naming whether a workflow deploys on push.
   If the question times out, do the step both options share and stop there: merge `origin/main`
   INTO the feature in its own worktree (`git merge --no-commit --no-ff`, resolve, gate, fresh
   review), never touch `main`, and repeat the question with the results.
   - Auto-merged files changed by both sides need a scripted sanity pass before the gate: duplicate
     enum keys/values, duplicate seed-payload codes, duplicate entity members (`grep -oE ... | sort |
     uniq -d`), then both typechecks; save `git write-tree` as the gated tree. Brief the semantic
     reviewer per shared file with "does the target's NEW code read a field the feature now strips
     or narrows (a relation `select`, a redacted response), or rely on a status the feature's flow
     writes differently": those break silently (a print shows blank) and no test or conflict shows it.
     Also ask, per quantity/status column the feature gave a new meaning or a new sibling (a
     `closedQty` carved out of `remainingQty`): does the target add a NEW derived rule over the old
     columns ("received = qty - remainingQty" -> auto-finish the parent)? The rule compiles and merges
     cleanly but now counts the feature's portion as done. Fix it inside the merge in the target's
     rule (subtract the new column, `?? 0` for the target's stub fixtures), keep the feature's
     expectations unchanged, and add a target-side regression case.
   - A target rule that never reverts a status it derived ("SELESAI is never auto-reverted") vs a
     feature action that undoes the rule's input (deleting / reducing / cancelling a pending child
     document that already counted): before asking, (1) read the guard of the action that would
     REUSE the freed amount (does a new child document check the parent's status or only its own
     source's?) and state the real harm from that cite: often nothing is stranded and the only effect
     is a status shown too early, not "the qty can never be ordered again"; (2) list EVERY action
     that undoes the input (delete, reduce, move, cancel/Batal, the release on a denied downstream
     receipt). Then ask leave (the parent may show the status early) / re-open (changes the target
     owner's rule; tell that developer) / block, with the cited harm, and recommend leave when the
     undo actions are how users fix a mistyped document. A block on delete/reduce only is bypassed
     by cancel in one click, and blocking all of them removes the correction path; users then reverse
     the decision after the guard is built. If a block is chosen, its guard locks the parent AFTER
     the rows the target's own path locks first, so it cannot invert that order.
   - A one-time "you push `main`" override covers that merge only. Before building follow-ups,
     fast-forward the feature branch to the new `main` (`merge --ff-only origin/main`, push the
     branch), and ask again before the next push to `main`.
   - Deploy notes after the merge: re-derive every enum `ALTER TYPE ... ADD VALUE` line from BOTH
     sides (`git diff <base> HEAD` and `git diff <base> MERGE_HEAD` on the enum files). A target that
     relies on schema sync adds enum values its own changelog never lists; a feature deploy block that
     says "run first in every case" then seeds into a missing value and fails the whole seed. Add a
     grant note for any new permission the target now REQUIRES for an existing action.
7c. **Before pushing `main`, read `.github/workflows/*` for push-to-main triggers.** A release
   workflow (e.g. erp-topaz: push to `main` that changes `package.json` builds, deploys to the
   server and runs migrations + seeds on every database) turns "push main" into a deploy with
   irreversible migrations. Name that consequence (which migrations, which DBs, data deleted) and
   get an explicit OK in the same turn before the push; a plain "merge to main and push" is not it.
8. **Push only on an explicit request, fast-forward only**, from a script: fetch, assert the current
   branch and a clean tree, assert `git merge-base --is-ancestor origin/<b> <b>` (else STOP: the
   remote moved), push `<b>:<b>` (never force), fetch again and print local vs remote sha. Push only
   the branch named; mention other unpushed branches instead of pushing them.
   - Target moved between your local merge and the push (others push to develop within minutes):
     the STOP is correct, never force. Preview `git log <b>..origin/<b>` and `git merge-tree
     --write-tree --name-only <b> origin/<b>`, tell the user in the same turn (which features
     landed, which files conflict, push held until re-gate), then in the checkout holding `<b>`:
     `git merge --no-ff --no-commit origin/<b>`, resolve changelog-only conflicts by script (step
     5), stage, save `git write-tree` as the gated tree, gate a `git archive <tree>` copy (both
     typechecks, the feature's suites AND the incoming commits' new suites), commit only if
     `git write-tree` still equals it, then re-run the push script. Re-fetch right before pushing.
   - Structured in-app changelog: when your side already carries an item from an EARLIER develop
     merge and the incoming side re-quoted or moved that same item, the conflict block holds it in
     ours while theirs keeps it elsewhere; "keep both" then duplicates it. The resolve script asserts
     each item's distinctive text occurs exactly once and drops the copy from ours.
8b. **"Merge the feature into develop" (the safe path)**: if the work is still uncommitted, QA is
   open, or the request reverses an earlier commit/merge decision, stop before any git command and
   lay out the prerequisites and options first (`pm-release-readiness` §2b-iv step 00). Otherwise:
   commit the feature on its branch (one
   commit per repo when later tickets edited earlier tickets' files), `git fetch` and merge
   `origin/develop` INTO the feature ("pull first" means this, never a rebase), THEN write and commit
   the changelog on the feature, then gate as in step 4. Changelog first guarantees a conflict: develop's
   own commits almost always add lines under the same "Unreleased" heading. Changelog content, per
   the repo's rules: the technical log (`CHANGELOG.md`, one bullet per fix with endpoint/migration/
   test-suite names, migrations that must run at deploy called out) and, where the app has an in-app
   user changelog, plain-language items in the users' language with no file/endpoint names, including
   any consequence users will notice (e.g. past report totals change). Insert them with a small script
 that asserts the "Unreleased" anchor occurs exactly once, and typecheck a structured (TS) changelog.
 Do not put a formatter `--check` on the structured changelog in a `set -e` commit script unless
 it passes at HEAD: such files often keep an escaped-quote style prettier rejects, and the check
 then aborts the run before any commit; check `git show HEAD:<f>` first, follow the file's style.
 A feature whose code lives in one repo still owes the user-facing note in the repo that holds the
 in-app changelog: cut a same-named branch there from `origin/<target>` (worktree), commit the
 note, and merge/push both repos in the same script so the note never ships without the feature.
   A server gate is needed again whenever develop's new commits touch a file the feature changed
   (`comm -12` of both `--name-only` lists), even when git merged it cleanly. Then from a script in the
   checkout that holds `develop`: assert it is on `develop`, clean, equal to `origin/develop`, and
   that it has not moved since the gate: `develop` is an ancestor of the feature head, OR (for a
   follow-up commit after an earlier merge) `git diff --quiet develop <feature>~1` holds. After
   the first `--no-ff` merge, develop's merge commit is never an ancestor of the feature, so the
   ancestor test alone wrongly reports "moved" on every follow-up; tree equality with the
   previously gated feature head is the real "nothing new on develop" proof. Then
   `merge --no-ff <feature-sha>`; assert `git diff HEAD <feature-sha>` is empty (the merged
   tree IS the tested tree); then the step-8 push. A "commit, then merge to develop, then push"
   script runs ALL its read-only checks first (fetch, target == origin, target ancestor of the
   feature, clean trees, in every repo) and only then its first write, the pending feature commit
   included: a commit placed before a failing preflight leaves the run half-done (committed, not
   merged) and the next script must start from that new state. Before running it on several repos, preview each
   (`git fetch`; `git rev-list --count <T>..origin/<T>`; `git merge-tree --write-tree --name-only
   <feature> origin/<T>`): a repo whose target moved needs `origin/<T>` merged INTO the feature first
   (changelog conflicts per step 5, typecheck), the others go straight through. The script checks
   every repo before merging any, and fast-forwards a local target that is merely behind its
   remote. Ask first whether to push or stop before it, and
   say the feature branch itself stays unpushed unless asked. When the target has NOT moved since
   the gate (`develop` == `origin/develop` and an ancestor of the feature head), no re-gate is
   needed: a final typecheck of both repos plus `scripts/merge-no-ff-and-push.sh <branch> <target>
   <repo>...` (asserts, `--no-ff`, tree equality, fast-forward push, local vs remote sha) is the
   whole merge. That script asserts the FEATURE branch is checked out in each repo dir; when the
   feature lives in a separate worktree and the main checkout holds `develop` (the usual PM
   layout), it stops at preflight. Use a two-path variant instead: preflight the worktree (on the
   feature, clean, == origin, `origin/develop` ancestor) AND the main checkout (on develop, clean,
   == origin), then in the main checkout `merge --no-ff <feature sha>`, assert tree equality, push.
   Read the release workflow's `on:` block first and tell the user whether the push
   deploys (a push to `develop` usually does not; a push to `main` may run migrations).
8b'. **"Merge to develop now" while workers still edit the run branch's tree** (a mid-run merge of
   the tickets committed so far): never checkout develop in that checkout (it carries or refuses
   their uncommitted edits; stash is forbidden). Merge only the COMMITTED tip with
   `scripts/merge-committed-no-checkout.sh <branch> develop <repo>...`: it asserts develop ==
   origin and is an ancestor of the branch, builds the two-parent merge with `git commit-tree`
   (tree == branch tree, asserted), pushes it fast-forward and moves the local ref; the worker
   tree stays untouched. Merge only what passed a gate; list in the reply which tickets are in and
   which (plus the changelog) still need a second merge, and log it on the board. The same script
   does the second merge: after the first merge develop is no longer an ancestor of the branch, so
   it accepts develop when its tree equals `git merge-base develop <branch>` (develop holds only the
   earlier merge of this branch) and refuses anything else.
8c. **A repeated "merge into develop" request**: first check whether it is already done (fetch;
   `git rev-list --count develop..<feature>` = 0, feature worktree clean, local `develop` =
   `origin/develop`). If so, say it is already merged and pushed with the shas, and offer what the
   user may have meant instead (push the feature branch, merge develop into main, deploy +
   migrations) rather than redoing or inventing work.
8c'. **"Finish the work first, then merge to main, you resolve the conflicts"**: integrate every
   pending branch (main, the other feature, the test-fix branch) INTO the feature branch in a
   scratch worktree (`merge/<x>` branch from `origin/<feature>`), one local merge commit each, gate,
   review, push the feature branch; build the remaining tickets on it; then one final merge of the
   feature into `main`. Treat the request as the push-to-main OK, but name the exact sha and gate
   result right before pushing `main`, and re-fetch: if `main` moved, merge it into the feature
   first so the push stays a fast-forward-safe `--no-ff` of a gated tree.
   - Every trial/integration script starts with `cd <scratch worktree>` and asserts it (`git
   rev-parse --show-toplevel`). Give each new script a fresh file name and check the path does not
   exist before writing it: an older `runs/merge-*/trial.sh` under the same name may target the
   user's checkout, and running "your" script by that path runs the old one. If one ran there by
   mistake, verify and report: HEAD, no `MERGE_HEAD`, the user's uncommitted diff unchanged.
   - Conflict-resolve scripts match the closing marker by any label (`>>>>>>> [^\n]*`): git labels
   it with whatever ref string was merged (a sha, `origin/main`, a branch), so a hard-coded label
   matches nothing. Make the script exit non-zero when a marker remains, so the commit step never
   runs on a half-resolved tree. Feed it only the files `git diff --name-only --diff-filter=U` lists:
   a file that conflicted last time may auto-merge this time, and "0 hunks" must not abort the run.
   - A merge script stops on any conflict outside the changelogs (case on the conflicted paths, exit
   with the merge left in progress); resolve code hunks by hand (read base/ours/theirs), then run a
   separate continue script. When the other side's NEW unit spec builds a service with a dependency
   your side removed and uses a stub manager, fix the constructor call and `jest.mock` the module-
   level helper your side added (it needs a real DB); keep the spec's assertions.
   - Pre-commit "only my files changed" guards compare the sorted path SET
   (`git status --short --untracked-files=no | awk '{print $2}' | sort` vs the explicit list), never
   line counts: untracked linked dirs and a list written several paths per line both break counts.
   Write the explicit list one path per line and expand it unquoted (`echo $PATHS | tr ' ' '\n'`).
   - A merged-tree gate that fails: prove each failure is the target's own before committing. Run
   exactly the failing specs on the plain target in a clean worktree on its own throwaway DB (same
   failure = inherited), and assert every format/lint-flagged file is byte-identical to the target
   (`git diff --quiet MERGE_HEAD -- <f>`). Commit only when both hold, name the inherited failures
   in the merge message, and add a board row for the target's owner.
   - Each time `main` moves during the run, preview the cost without a worktree:
   `git merge-tree --write-tree --name-only HEAD origin/main` lists the conflicting files (exit 0 =
   clean); also note which shared files auto-merge, since those need the gate again.
   - Push the integrated feature branch from the scratch worktree as `HEAD:<feature>` only after
   asserting `origin/<feature>` is an ancestor (fast-forward), and tell the user their local
   checkout is behind and a plain `git pull` fast-forwards it.
   - Review leftovers the user later decides, small and in the same settled files, become their own
     small ticket in the same worktree before the next feature ticket (one writer per tree).
   - Before asking for the push-to-main OK, run a final fan-out of fresh read-only reviewers over
     the WHOLE feature diff vs `origin/main`, split by area (core business flows end-to-end; reports
     + frontend + deploy notes; the merge integration: auto-merged files, cross-feature use of
     changed entities, changelogs). Per-ticket reviews pass while a cross-ticket bug survives (a
     total reading a column only test fixtures write). A blocker stops the push: fix, re-gate,
     re-show the new sha.
   - The target's own failing tests (proven inherited): when the user asks to fix them, read why
     each fails before touching anything; usually a spec setup left behind by a later code change
     of the same owner (a stub manager missing a method the service now calls, an integration spec
     that never seeds the row the validation needs). Fix the spec setup only, never the app code,
     then gate with an EMPTY failure baseline so the branch proves 0 failures.
     A structural wiring-guard spec ("bulk and single routes carry the same `@UsePermission`") that
     the owner broke by moving the check elsewhere on purpose (into a per-status service assert
     both handlers call) is widened to accept the equivalent mechanism, never "fixed" by restoring
     the old decorator: first read the new assert and confirm it really enforces a permission
     (STOP if not), extract each handler's guard from its OWN decorators/body only (so it cannot
     borrow the next route's), keep the old negative case, add one for the new form (bulk asserts,
     single does not -> refused), and prove it with a PM mutant that deletes the assert call from
     one handler. Formatting-only fixes on the owner's files: show the whitespace-stripped diff is
     empty or a trailing comma, so the commit cannot hide a logic change.
8d. **Publishing gated scratch work as new branches** (staged merge / test fix sitting in scratch
   worktrees while the user decided the push target): the gate may be hours old, so first `git
   fetch` and compare the target with the sha the gate used (save it to `runs/<x>/main-sha.txt` at
   gate time). If it moved, list its new files (`git diff --name-only <gated-sha> origin/<target>`)
   and intersect with the staged/changed files; no overlap = the gate still holds (say so, and that
   the PR was not re-tested on the new tip), overlap = re-gate. Then one script per publish:
   assert each worktree's branch name, stage EXPLICIT paths (never `add -A`: linked untracked
   `docs/` dirs show as `??` in worktrees), assert a staged merge has no unstaged leftovers,
   `commit -F <msg file>`, `push -u origin <branch>` (new branch, never force, never the target),
   then `git ls-remote --heads` for the new branches AND the target to prove the target is
   untouched. Report the PR URLs and the merge order the user should use (a test-fix branch first,
   so the other PR is not red with the same pre-existing failures).
9. **Dropping unpushed local commits** ("don't push main, it's in develop"): first prove
   `git rev-list --count origin/<target>..<b>` = 0, and that no worktree has `<b>` checked out.
   Then move the branch to its remote (`git branch -f <b> origin/<b>`) rather than deleting a
   release branch. List local-only tags left behind (compare `git tag` with `git ls-remote --tags`):
   they point at commits never released from the remote branch and `git push --follow-tags` would
   publish them; ask before deleting them.

## Reporting
- When asked "was anything removed?", answer from the step-5 measurement and the typecheck, never
  from grepping only the files you care about. Checking that your own feature survived does not
  show that the other side survived.
- If you find you reported wrongly earlier, say so plainly, give the measured damage (counts +
  file list + build errors), confirm nothing was pushed, and propose the recovery plan, asking
  before any reset.

## Recovery (local, unpushed)
- `origin/<branch>` untouched -> reset local branch to it (with approval), restore feature branch to
  its pre-rebase sha (still reachable via reflog / recorded sha), redo steps 1-6.
