---
name: pm-workspace-resume
description: "Use when resuming PM work after a handoff or new chat."
---

# Resuming a PM workspace (new chat, new PC, handoff bundle)

Complements `thin-orchestrator` (its Start / resume steps run AFTER this). This skill answers one
question first: which copy of the project is live, and is it intact?

## Procedure
1. **Find every candidate copy before reading any board.** A project can exist in several places: the
   cwd, a handoff layout (e.g. `~/project/<name>` + `~/project/<name>-monorepo`), an unpacked handoff
   bundle sitting in a repo root (`NEXT-CHAT-PROMPT.md`, `setup-new-pc.sh`, `uncommitted.patch`,
   `*.bundle`, `docs.tar.gz`), an archived old checkout. Signals: a `## Paths on this PC` section in
   `PROJECT.md`, a handoff prompt naming paths, `docs/_handoff/`.
2. **Pick the newest by content, not location.** Compare the `Updated` line of `STATUS.md` and the last
   line of the `tickets.md` log across copies; the one with the handoff / latest entry wins. The cwd
   copy can be the stale one.
   - WHY: a stale copy shows applied uncommitted work as "missing" and an interrupted run as "lost";
     reporting that sends the user chasing a non-problem. Never report work missing from one copy
     without checking the others.
3. **Verify the live copy (read-only):**
   - branch + HEAD vs `git ls-remote origin refs/heads/<branch>`;
   - uncommitted work vs the pause snapshot, by checksum:
     `grep -E '^[0-9a-f]{64}  (backend|frontend)/' runs/PAUSE-*.sha | sha256sum -c --quiet -`
     (count the files checked);
   - other modified files: show their diff, name them "not ours", never touch;
   - run prerequisites: `.env` present, DB client tools on PATH, a throwaway `createdb`/`dropdb` works,
     `node_modules` installed. If a handoff ships a `verify-*.sh`, prefer running it.
   - When the user says "already handled", re-run these checks before agreeing; report each one that
     still fails with the exact fix command. A DB server in Docker (`docker ps`, port 5432) does not
     put `createdb`/`dropdb`/`psql` on the host; gate scripts calling them still need the client package.
   - Read a verify script's FAIL lines critically: a stale-path FAIL can be a false positive (grep the
     named files yourself before reporting it). A bulk path rewrite also rewrites the verify script's own
     "old path" grep pattern into the NEW path, so the check then flags correct files: restore that
     pattern to the old path (or exclude the verify script from the rewrite) and re-run.
   - Check for duplicate skills: a handoff that unpacks profile skills can shadow a newer copy in an
     external skills dir (`skill_view` by bare name then fails as "ambiguous"). Diff the copies; when the
     profile copy is older or contradicts `PROJECT.md`, back it up and remove it with the user's go, and
     load the survivor by name so you follow its current rules.
   - Leftover absolute paths from the old machine inside `runs/` evidence logs are history; only
     scripts, `PROJECT.md` and skills need them rewritten.
3b. **When the human picks a copy other than the handoff layout** (e.g. the one where they put `.env`),
   make that copy complete instead of mixing the two. This choice is the go for these steps:
   - check the tracked tree is clean (`git status --short | grep -v '^??'` empty) before touching it;
   - move its stale `docs/` + `PROJECT.md` aside to a dated `_handoff-stale-<ts>/` folder (never delete);
   - copy the current `docs/` + `PROJECT.md` in from the handoff workspace;
   - back up the pm profile (`skills`, `memories`, `SOUL.md`) into the same folder, then rewrite the
     old absolute paths in docs, `PROJECT.md` and the profile, longest path first (the `-monorepo` /
     `-old` variants before the bare workspace path, so the prefix doesn't swallow them);
   - `git apply --check uncommitted.patch && git apply uncommitted.patch`, extract the untracked tarball,
     then re-run the pause-sha check and grep for leftover old paths (expect 0);
   - point the gate scripts' default paths at the chosen copy (check `BACKEND=` / `FRONTEND=` defaults),
     log the move on the board, mark the other copy unused in STATUS.md.
4. **Record, don't act:** append one "handoff received" / "resumed" line to the `tickets.md` log (what
   matched, what is missing, which copy is stale), add any setup blocker as a row at the top of
   STATUS.md "Needs you", and dispatch nothing until the human explicitly says continue.
4b. **On "continue":** before dispatching, write the run-level state the orchestrator skill expects
   (e.g. create `decisions.md` if missing, with the handoff, the chosen copy, answered parked questions
   and the resume line), record answered business questions in the spec decisions table, and clear
   them from STATUS.md "Needs you".
   - Re-dispatching a brief written before the handoff: add a "re-dispatch note" section at its top
     instead of rewriting it. State the fix-round count (an interrupted run that changed nothing does
     not consume a round), that the old machine's scratch/probe scripts did not travel (rebuild from
     the report text), the decisions taken since, and the parallel workers' files.
   - When a wave runs in parallel, give each shared file (rollout note, changelog) to exactly ONE
     worker; the others put the lines they would add in their report. Two workers editing one file
     outside git leave no diff to untangle.
   - Snapshot the tree (sha256 of modified + untracked files, out-of-git script dirs, DB list, running
     test processes) to `runs/` right before dispatch, so a lost worker can be checked against it.
4c. **Session restart mid-wave (model switch, app restart, new chat while workers ran):** in-session
   subagents die with the session; their batch result comes back `status=unknown`. Triage each before
   any re-dispatch:
   - transcript tail (`cache/delegation/live/<id>/task-N.log`, last think/assistant lines) and the
     ticket's scratch outputs (RED, green x3, suites, mutation, probe logs);
   - the ticket's files vs the pre-dispatch snapshot sha: unchanged = the run changed nothing and did
     not consume a fix round;
   - leftover throwaway DBs, running jest/psql, `zz-*` / `.bak` probe files.
   - `delegate_task(action='list')` first: an empty list means every child is dead, whatever the
     batch message says; a finished sibling's result can still arrive later and is valid.
   - DB leftovers: plain `psql` prompts for a password and fails; use a small script that exports
     PGHOST/PGPORT/PGUSER/PGPASSWORD from only the `DB_*` keys of `.env` and lists `<project>_*`-style
     throwaway DBs (keep it in scratch, reuse it after every loss).
   Then: work finished but no report -> the PM writes the report from the evidence, labelled as such,
   unverified until gates + review; work not done -> add a "Run N" bullet to the brief's re-dispatch note
   (what is verified done with evidence paths, what is left, "do not redo finished steps", same report
   file keeping earlier sections) and re-dispatch. A lost run stays in the same fix round. A STOP
   finding from the lost run (e.g. an extra data era) is decided and recorded in the spec before the
   re-dispatch, not handed back.
   - A plan red-team lost after its target code has landed: re-dispatch it as a code review with the
     same attack list once the builder's report exists, not as a plan review.
   - Restarts can repeat within one session (every model switch). Tell the user after each loss what
     survived, keep waves small, and require report updates after EVERY milestone in each brief.
   - Notifications from a dead child's background processes (a test run it started) can still arrive
     after the restart. They are evidence for triage, not a sign the child is alive.
4d. **User away for days ("I'm out for a week"):** write an "away mode" block at the TOP of STATUS.md
   and one line in `decisions.md`, so any resumed session follows it: what the PM does alone (technical
   decisions, dispatch, gates, review, commit/push if `PROJECT.md` allows), what it parks (business /
   money / tax rules, a fix round past the cap, main/prod/real DBs, design-only for money-moving
   tickets), the ordered queue, and the restart-recovery steps of 4c. Tell the user plainly that work
   only advances while the session and PC stay up, ask them to keep it awake, and offer a scheduled
   resume check. Check-ins ("status") are answered from that block: done since last check, running,
   parked items with options.
   - If the user grants commit/push mid-run, edit the `PROJECT.md` hard rule in place (who commits,
     which branch, never force / main, only after gates + fresh review) and add a `decisions.md` line.
   - Commit/push recipe, what still needs a fix round, worker STOPs that overturn a PM rule, legacy
     backfills, money deploy SQL, order-dependent flaky tests: `references/unattended-run-judgement.md`.
   - When the user is away, many decisions pile up: keep ONE ordered "Needs you" table (item,
     options with consequence, recommendation) and end every report with the open items as a single
     line the user can answer in shorthand ("A, A, C, yes").
   - An approval prompt that times out means the command did not run: never retry or rephrase it.
     Record the same fact with a plain append (`echo ... >> decisions.md`) and ask the user for the go
     on the blocked edit. Appending works only for log files: `tickets.md` ends with its event log, so
     an appended board row lands outside the table; insert rows with `patch` anchored on an existing
     row. While the user is away, never use python-heredoc or sed-generated scripts
     for board/script edits (they need approval): edit `tickets.md` rows with `patch`, write commit
     scripts and commit messages with `write_file` (`git commit -F <msg file>`), run with `bash <file>`.
   - Full delegation ("take your recommendation on everything", "never stop"): see
     `references/unattended-run-judgement.md` (delegated Q rows, held tickets, no auto-resume cron).
5. **Report:** lead with the correction if an earlier answer was based on the stale copy (say plainly
   what was wrong), then a check table (check -> result), then the human's to-do list, then the resume
   queue that will run on "continue".
6. **Leave a resume point when a feature's build work ends:** prepend a dated `## CURRENT` block to
   STATUS.md (HEAD = origin sha, commits that shipped, work outside git with its checksums, "nothing
   running", the items only the user can do), mark the older sections as history. A fresh session then
   starts from that block instead of reconstructing state from the board log.

## Related
- Handoff that asks you to *set up a local runner* (worktrees on feature branches, DB copy, extra
  services, env files, smoke test): `references/local-runner-from-handoff.md`.
- Switching or adding the LLM provider/key of a runner piece (bot, assistant): `llm-provider-integration`.

## Pitfalls
- The project folder can move between chats (e.g. into a parent `~/Projects/<name>/` with old repos
  under `<name>-old/`). When `PROJECT.md` / memory paths no longer exist, search for `*/PROJECT.md`
  under `~/Projects`, use the copy you find, and report the stale `## Paths on this PC` lines
  (fix them only with the user's go). On the go, fix every LIVE path in one pass: `PROJECT.md`
  (paths section + repo table rows), gate scripts' `BACKEND=` / `FRONTEND=` defaults (`bash -n`
  after), review/brief templates, PM skills and the memory registry line; leave `runs/` logs and old
  briefs as history and say so in `PROJECT.md`. Also grep tracked `CLAUDE.md` files for `@../` imports
  that now point nowhere (a missing import silently drops the shared rules); those are in git, so
  offer the one-line fix instead of making it. Log the move on the board.
- Archives you inspected can vanish between calls (the user is moving files); re-`ls` before relying on
  them, and when a file disappears, look for where it went instead of assuming loss.
- `source .env` can fail on unquoted values; read only the keys you need instead of sourcing in a
  shell that then runs commands.
- Never apply a handoff patch, unpack bundles, or run the setup script yourself without the user's
  go: it writes the repo and the user may already have done it elsewhere. The user naming which copy
  is live IS that go for step 3b.
- When two copies exist, ask the user which one is live (recommend the one holding the verified
  uncommitted work + newest docs) instead of picking silently; then follow 3b.
