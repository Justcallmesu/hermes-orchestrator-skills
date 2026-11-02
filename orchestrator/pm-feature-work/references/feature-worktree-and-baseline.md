# Feature worktree + baseline gate (before ticket 1)

Use when the main trees carry another feature's uncommitted work and the user chose "new branch in a
separate worktree".

## 1. Worktrees (one script, plain `bash <file>`)
```bash
for r in server webapp; do
  SRC=$P/<repo-$r>; DST=$P/wt/<short>-$r
  [ -d "$DST" ] || git -C "$SRC" worktree add -b feature/<name> "$DST" develop
  [ -e "$DST/node_modules" ] || ln -s "$SRC/node_modules" "$DST/node_modules"
  git -C "$DST" status -sb | head -1; git -C "$DST" log --oneline -1
done
git -C $P/<repo-server> status -sb | head -1   # main tree must still be on the other branch
```
- `git worktree add -b` never touches the source tree's index or files; still print the source branch
  afterwards as proof for the user.
- Monorepo (one git repo, `backend/` + `frontend/`): ONE worktree, one `node_modules` symlink per
  package dir, and point the project's gate scripts at it with their path overrides
  (`BACKEND=$WT/backend`, `FRONTEND=$WT/frontend`) instead of copying the scripts.
- Branching from `origin/main` makes the new branch track `main`. Run `git branch --unset-upstream`
  right after, so a bare `git push` can never target main; push later with `-u origin <branch>`.
- Base branches move between discovery and build (another feature merges, or the user pushes a quick
  edit). Discovery often reads the LOCAL checkout, which lags `origin/<base>`: `git fetch` before branching,
  then `git log --format='%h %an %ad %s' <discovery-sha>..origin/<base> -- <every path the spec cites>` and
  `git diff --stat` over the same range. If empty, the cites still hold; say so. Otherwise re-read those
  files at the new base before writing briefs, and record the new base in `tickets.md`. A new commit on the
  very file the ticket edits usually breaks an existing suite assertion (e.g. a report section the user
  commented out): name the expected-failing checks in the brief as "pre-existing, prove it fails on HEAD
  too, do not fix", tell the user in the status reply, and leave the user's own change untouched.
- A one-ticket feature does not need a new worker-rules file: point the brief at the latest feature's
  `worker-rules.md` with explicit substitutions (worktree path, `SRC=` prefix, ticket id, report path,
  do-not-touch trees). Still give the ticket id a feature prefix.
- Record branch, base commits and worktree paths at the top of `tickets.md`.

## 1a. No worktree needed: clean tree already equal to develop
When the previous run is merged and both trees are clean, branch in place from a script that refuses
otherwise: `[ -z "$(git status --porcelain --untracked-files=no)" ]`, `git diff --quiet develop HEAD`,
then `git checkout -b feat/<name> develop` per repo. Copy the previous run's gate script under a new
prefix (its own DB-name prefix and `docs/<feature>/runs/{gates,baseline}` paths) rather than writing a new
one, and start the baseline gate in the background together with the spec red-team: they share nothing.

## 2. Throwaway backend from the worktree
- Copy the WORKING TREE (rsync excluding node_modules/.git/dist/.env), not `git archive HEAD`: the
  feature's tickets are uncommitted until the user commits, so HEAD would test the old code.
- Exception for a parallel wave in ONE worktree: each worker's copy = `git archive HEAD` + only the files
  that ticket lists (the env script takes them as args). Copying the whole working tree would pull in another
  worker's half-written files and break your build or test. The PM gate after the wave copies the whole tree.
- One kit, several worktrees: give the env script a source override (`S=${SRC:-<default repo>}`) and
  write a per-feature gate script that exports `SRC=<worktree>` and its own run/DB prefix. Every brief
  and the worker rules must show the call WITH the prefix; without it the copy is built from the default
  checkout (another branch) and the worker's tests prove nothing about the feature.
- Fresh DB per run on the scratch cluster, then migrate, roles, seed, sample, build, start. Point workers
  at the same script with their ticket id so DB names and ports never collide. Give every worker,
  gate and reviewer id a feature prefix (`BS1`, `RS1`, gate `b<id>`), never a bare ticket id (`S1`):
  scratch dirs, DBs and pid files are keyed by that id and outlive the feature, so a bare id lands in
  an older feature's leftover dir and pid file.
- Derive the port from the ticket id, then skip ports already listening (`while ss -ltn | grep -q ":$PORT "; do PORT=$((PORT+1)); done`):
  an unrelated process on a hashed port answers the suites, which then fail with auth errors ("bad token")
  against the wrong server. After start, assert the backend PID is alive; a health probe returning 401
  is normal for guarded routes and proves nothing either way.
- Start the backend only AFTER migrations are applied. When a worker or reviewer adds a migration to an
  existing throwaway DB, migrate, then restart the backend: a backend booted against an unmigrated schema
  refuses to start, and every suite then dies with `fetch failed` (no listener). `fetch failed` across all
  suites = harness, never a code result; steer the worker to restart and re-run.
- Before reading a RED suite as a code result, look at its first FAIL line: auth/connection errors on
  fixture setup mean the run is invalid (harness), not that the code or the mutant was caught. Log it as
  INVALID and re-run.

## 3. Gate script
- tsc + the feature area's existing HTTP suites + the ticket's new suites, each with `timeout`.
- Build the file list the gate copies and sha-checks from `git status --short` at run time, never a
  list hard-coded in the script: gate scripts get copied round to round, and the first ticket that adds
  a file (a new helper in an existing utils file counts too once it is modified) leaves it out of the
  copy, so tsc fails on a missing export and every suite reports `PASS=0 FAIL=0`. Read any all-zero
  suite line as "did not run" and check `tsc.log` before reporting.
- Count `^PASS` / `^FAIL` lines per suite; exit codes alone hide which assertion failed.
- List suites by their FULL file names, copied from `ls test/api/` or a worker report path
  (`102-goods-return-refund.mjs`), never a bare number: a guessed name skips the suite with no
  error, so the summary looks complete but is missing the run you meant to check.
- Export what direct-DB suites need (`PGHOST`, `PGPORT`, `PGPASSWORD`, test DB/schema vars). A suite
  failing on `connection ... port 5432` is a harness gap, not a baseline failure: fix the env, re-run.
- Count real 5xx from the API log by its status line (e.g. `grep -cE 'Status:.*❌ 5[0-9][0-9]'`), never a bare
  `' 500 '`: validation messages like "must be shorter than or equal to 500 characters" match it and report
  phantom server errors. Check any non-zero count against the log before reporting it.

- A formula duplicated in server and webapp (document totals, rounding remainders) and changed by the
  feature: the PM proves parity with a pure node script that imports BOTH implementations (TS loaded
  with `node --experimental-transform-types` plus a resolve hook mapping `@/` to the server or webapp
  `src` by the importing file's path) and compares them on thousands of random documents covering the
  new edge (free lines, last line 0). Report 0 diffs on the change AND show the same script finds diffs
  against the HEAD webapp copy, so the check can fail. Neither repo has a test runner for the other side.
- Webapp gate: tsc, eslint on the changed files, the repo's guard scripts, and a build into a scratch outDir (never the repo `dist`). Get the changed files from `git status --short -uall`. Without `-uall`, a new untracked folder shows as ONE entry, so its new files are silently skipped by the lint. Check the linted file count against the worker's file list.

- PM gate after a parallel wave: copy the WHOLE worktree including untracked files, not HEAD + one
  ticket's files (each worker only typechecked its own slice, so cross-ticket breaks surface only here):
  `git -C $WT ls-files -co --exclude-standard -z | (cd $WT && xargs -0 cp --parents -t $COPY)`, then
  symlink `node_modules`. For the server, pass every `git status --short` path to the env script.

## 3a. A failing suite that the baseline did not run
- A worker or a wider gate runs suites that are not in the baseline, and some of them fail. Before blaming the tickets, run those suites on the base branch without touching git state. Export it with `git archive <base> | tar -x -C <scratch>`, link `node_modules`, and use a fresh DB.
- Compare the failing test NAMES, not the counts. Random fixtures make setup steps fail at random, so the counts move.
- A suite whose PASS count drops by one or two with 0 FAIL is usually fixture variance (data-dependent loops emit a variable number of checks): grep that suite's line across every earlier gate's `suites.txt` (`grep -h '<suite>' docs/*/runs/*/*/suites.txt | sort | uniq -c`). If earlier gates show the same spread, log it as variance with the counts; otherwise read the diff of PASS names.
- If the same names fail on the base branch, the failures are pre-existing. Add one PRE row on the board with the evidence path, and from then on judge tickets by "no new failing names".
- If the base branch moves mid-run, add a pre-merge note to the board: merge the base in, then re-gate. Leave the git operation to the user.

## 3b. Per-ticket order in a worktree
- For a migration that copies then DROPS a column, the review brief must demand a data proof, not a read:
  seed edge rows BEFORE migrating (value on several child rows, NULL, no children, soft-deleted, archived,
  value 0) in at least TWO tenant schemas (create the second one on the throwaway DB), then up → second up
  says "up to date" → `down()` restores → up again. A single-schema test hides per-schema runner bugs.
- A business question in the worker's build report (an edge the brief did not decide): ask the user
  (clarify) while the PM gate runs, and put the answer in the spec and the review brief BEFORE dispatching
  the reviewer. A steer sent after dispatch often lands after a short review has finished, so the
  reviewer reports the undecided edge as a MAJOR and the fix round has to be re-scoped.
- Gate → PM mutation → dispatch the reviewer. Mutate INSIDE the gate's own scratch copy (it already has
  the built backend and DB): apply the mutant there, re-run the one suite with the copy's rerun script,
  restore from a `.bak`, and `cmp` the restored file against the real tree. The live tree is never
  touched, so a reviewer reading it can never see a mutant. If you must mutate the live file instead,
  restore with a sha256 match before dispatching the review; never run the two in parallel.
- Write ONE mutation script per ticket: the gate, then one mutant per rule the spec decided (each required field, the overwrite and the restore of a column, null handling, each refusal guard), then restore and a sha256 match.
- Apply each mutant with an exact-replace helper (python) that exits 1 unless the anchor matches exactly once; it handles multi-line anchors that `sed` cannot. Count the anchor inside that same python step, never with `grep -cF`: grep counts matching LINES, so a multi-line anchor reports the wrong count and the mutant is skipped as INVALID.
- Judge a mutant by the suite going RED, not by grepping the mutated text in `dist`: tsc rewrites the
  line (`if (false && x)` compiles to something else), so a "0 in dist" print is noise when the suite fails.
- Building ticket N+1 on top of an UNCOMMITTED, gated ticket N in the same worktree: snapshot
  `git status --short` + sha256 of every changed file into `runs/<N+1>/pre.txt` before dispatch, and
  tell the worker to pass EVERY ticket-N file plus its own to the env script (it copies HEAD + listed
  files only, so a missing ticket-N file silently tests the old code; generate the list from
  `git status --short` and save it for the PM gate). Its RED check runs on HEAD + ticket-N files only,
  and the worker must build that RED copy BEFORE its first edit: once it edits ticket-N files in the
  tree, the pre-ticket state exists nowhere (it would have to rebuild it from an earlier gate copy).
- Parallel tickets in ONE repo are safe when the env script builds each worker's copy from HEAD + its
  own listed files and the briefs give disjoint file lists (name the other ticket's files as
  do-not-touch). Commit the shared base first so both start from the same HEAD. If both need the same
  helper ("force free lines to price 0"), name its shared util path in BOTH briefs; otherwise each
  writes its own copy and the PM merges them later. Gate them together once from the whole tree.
- Parallel tickets in two repos of one feature (server ticket N+1 and the webapp ticket) are safe; name
  the other repo READ-ONLY in each brief and tell the webapp worker its optional live check may hit a
  server tree that is mid-edit. The webapp ticket may start while the server ticket's RE-review runs once
  the server PM gate is green: brief it against the contract in the latest build report (cite that file),
  log on the board that a contract change from the re-review means a webapp fix round, and say so to the user.
- Read a worker report's last lines for edits made AFTER its suite runs ("final whitespace edit, only
  tsc/jest re-run"): its suite counts then describe a tree that no longer exists. The PM gate must
  copy the tree as it is now and compare file sha256 with the report before quoting any count; never
  forward the worker's numbers to the user as verified.
- Parallel server + webapp fix rounds where the server adds a contract value (a new reason code):
  put the new value and its UI text in the webapp brief too, so the webapp handles it before the
  server emits it; otherwise the webapp ships a fallback for that case and needs another round.
- Make mutants type-safe: delete a statement, drop a `||` fallback, invert a guard. Have the script check `tsc exit 0` first and print INVALID otherwise. A mutant that does not compile proves nothing about the test.
- If a worker session ends without a final answer, look in its run dir for a finished gate summary before re-dispatching. When the gate is green and the diff exists, the PM writes the build report from the diff and the gate, then continues with its own gate and the review.
- A read-only REVIEWER that dies without a report ("owner exited", no review file): prove the tree it
  read is unchanged (`cd $WT && sha256sum -c --quiet <gated-sha>`), then dispatch a FRESH reviewer
  with the same focus list and "write findings to the report file after each check, not at the end"
  in the goal itself, so a second death still leaves partial findings. Never commit on the dead run.
- Worker killed MID-EDIT (host/owner exit, no gate yet): never restart from scratch and never revert its edits (the tree also holds earlier uncommitted tickets). Check `git status` per repo and the partial report, then dispatch a "finisher" on the same brief whose context names: the partial report, the dead transcript (read its tail), the files it touched, and any RED copy it already built (reuse it: the pre-edit state may exist nowhere else). Tell it to review the partial edits critically before finishing. Parallel workers in two repos die together; re-dispatch both in one call. Mark the board row "killed, finisher <id>" so the delayed failure notice that arrives later is recognised as old news.
  Before re-dispatching, read the dead transcript's tail for the LAST edit call: one that was "BLOCKED" by
  an approval timeout never ran, so the file is still at HEAD whatever the worker planned. Kill the dead
  worker's still-running backends (`kill -0 $(cat api-erp_<id>*.pid)`), and tell the finisher to edit files
  only with the patch / write_file tools: a whole-file rewrite inside an `execute_code` script raises an
  approval prompt that nobody answers in a background run. Put the same rule in the feature's worker-rules file.

## 3c. Commit per ticket from one shared worktree
- Gate script writes `sha256sum` of every changed + untracked file to `runs/<ticket>/gated-sha.txt`.
  The commit script then refuses unless the index is empty, `sha256sum -c` passes, and the current
  changed-file set equals the gated list exactly; it stages that list only. The sha file holds
  repo-relative paths, so run `sha256sum -c` (and the PM's own pre-commit re-check) with the worktree as
  cwd (`cd $WT && sha256sum -c --quiet <file>`); from any other directory every line reports "No such
  file" and reads like a tree that changed after the gate. A file touched after the
  gate (a late fix, another worker) cannot slip into the commit unreviewed.
- Before turning a review finding into work, re-read the code path it cites. Reviewers misread setup
  flows (e.g. "existing tenants only get the new setting after a manual seed" when API start already
  syncs defaults): close a wrong finding on the board with the PM's cite, so it is not fixed or noted for deploy.
  Also state the correction in the NEXT brief: workers read earlier review reports and repeat a wrong
  finding in their proposed doc text (a bogus deploy step), which must be corrected before it is applied.
- Review minors that are only missing TESTS on a gated, uncommitted ticket: a tests-only follow-up
  (edit the one suite file, each new check proven to fail on a named mutant in the worker's scratch
  copy). Then the PM proves only that file changed since the gate (`sha256sum -c` lists exactly it),
  re-runs that suite alone on the gate copy, rewrites `gated-sha.txt`, and commits both together; no
  full re-gate is needed for a test-only delta.
- Parametrise the commit script by branch (`BR=${BR:-<feature branch>}`) instead of hard-coding the
  first feature's branch name: a follow-up feature in the same worktrees runs on a new branch and the
  old script's branch assert refuses every commit.
- Small review findings (MINOR/NIT) on a committed ticket go into the NEXT ticket of the same feature
  when it already edits those files (name them in its brief with allowed extra files); the rest become
  backlog rows. No separate fix round for findings that do not block.
- After editing changelogs or other markdown with a find-and-replace tool, grep the result for
  backslash-escaped quotes (`\\"`) before committing: escaped quotes in the new text can land literally.
- A ticket that DELETES files: the gate script records sha256 for files that exist and a separate
  `gated-deleted.txt` list for removed ones, and passes all paths to the env script (which removes
  deleted paths from the copy); the commit check compares the full changed set (`git diff --name-only`
  + untracked), deletions included.
- One script (`bash <file>`): assert the branch, print the repo's configured `user.name/email` (commit as
  that identity unless `PROJECT.md` names another), then per ticket `git add <explicit file list from its
  build report>` + commit, in dependency order. Give files shared by several tickets (changelogs, a
  cross-ticket doc) to the LAST ticket of that repo, which may use `git add -A` after asserting the
  remaining `git status` holds only its files. Print `git log --oneline` and an empty `git status` at the
  end, then push with `-u`.
- A follow-up decision that arrives after commit (a new Q answered at commit time) becomes its own
  ticket and commit on the same branch; do not amend the committed tickets.
- When the user commits only at the end and later tickets edited files of earlier ones (the same
  service, the same detail page), per-ticket commits are no longer clean: check overlap with the
  build reports' file lists, then hand over ONE commit per repo, and say that any per-ticket command
  given earlier is withdrawn. New tickets added after a "here are your commands" message also make
  those commands incomplete: tell the user to hold the commit until the new tickets land.

## 4. Baseline
- When the previous feature's final gate ran on a clean HEAD whose tree equals the new branch base
  (`git diff --quiet <that HEAD> develop`), copy its `suites.txt` as the new baseline instead of
  re-running; say so in the board header.
- Run the gate once on the untouched branch (`runs/baseline`) before any worker edits.
- For every baseline FAIL, read the assertion and the code it targets, and log on the board why it
  fails (stale test vs real bug vs harness) and which ticket will change it. Read the first error
  line first: an `ENOENT` on a path under the repo's untracked `docs/` (specs that load SQL/fixtures
  kept outside git) is a worktree harness gap, not a code failure, because a worktree holds only
  tracked files. Log it as a PRE row with that reason. Later gates compare against this, so a
  pre-existing failure is never blamed on a worker, and a worker never "fixes" it out of scope.
- The baseline and the first developer can run in parallel when they use different DB names.
- Copy the baseline's failure list and tsc count into each ticket's run dir, and judge the ticket by
  diffing the sorted failure lists (identical = nothing new). Gate scripts print RED whenever any suite
  fails to run, including suites that already failed in the baseline, so the overall verdict alone
  misleads. A formatter step that complains about a file the ticket deleted is noise.
