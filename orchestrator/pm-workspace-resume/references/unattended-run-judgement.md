# Judgement calls in a long unattended run (PM + workers)

Depth for step 4d/4e of SKILL.md. Each rule: what to do + why.

## Gated per-ticket commit + push (when PROJECT.md grants it)
One script per ticket, stop at the first failure:
1. Assert branch and empty index; sha256 the ticket's explicit file list.
2. `git worktree add --detach` of HEAD; copy exactly those files in; symlink `node_modules` and any
   out-of-git dir the specs read (e.g. `docs/`); copy `.env`.
3. Run the gate script there with its repo-path override (`BACKEND=<wt>/backend`) and the baseline dir
   explicit (`BASELINE_DIR=`): otherwise it tests the dirty tree or records a fresh baseline.
4. Fail on any red line except a NAMED pre-existing one (exact-string match, e.g. one formatter line
   in a file that already fails at HEAD); require "no new failures" on the test line.
5. `sha256sum -c` the files again (a parallel worker may have edited them during the gates).
6. Remove the worktree; stage the explicit list; assert the staged list equals it.
7. Commit with a why-message (decision ids, ticket ids, review verdict); `git push origin <branch>`;
   confirm HEAD == origin. Never force-push, never `main`.
- Prove push access once per session with `git push --dry-run origin <branch>`.
- A red gate stops before staging, so nothing needs undoing: fix, delete the old gate output dir,
  re-run the same script. Reuse the script for the next ticket by swapping the file list and message.
- A commit may run while another ticket's worker edits disjoint files; tell any reviewer HEAD may move.

## Full delegation ("take your recommendation on every decision", "never stop until done")
- The park list shrinks to main / prod / real DBs. Take the recommended option on business and money
  rules too; record each as a spec Q row marked "(user, delegated)" with the rejected options; move
  the open "Needs you" rows to one ANSWERED line in STATUS.md; red-team and the fix-round cap still apply.
- A ticket held "until production data reaches state X" (a review list empties) can never unblock
  before deploy. Build it now and turn the hold into a runtime display rule: hide what is not yet
  trustworthy, and show a total only when every part is shown (else "incomplete" + count).
- Do not set up an auto-resume cron for a live orchestration: a cron agent has no session context and
  races the running session (double dispatch on the same files and DBs). Say so and keep resume manual.
- A worker STOP on an existing test's expectation under a delegated rule usually means the rule is too
  broad (it blocks a documented flow). Narrow the rule so the old test stays valid, amend the Q row,
  and re-run; do not approve flipping the test.

## Phase A before a cross-cutting rule
- For a rule every path goes through (e.g. "an IN without cost throws"), first dispatch a read-only
  analyst: list every caller with file:line, mutate the rule in on a scratch copy, run the module
  suites, and classify each new failure as test seed vs production path. Ask for a BLOCKS-<x> list and
  open questions; decide those (Q rows), then brief the build. Seed-only failures become seed fixes;
  tests pinning the removed behaviour are flipped to assert the refusal + unchanged DB.
- Same for a feature whose shape is unknown (where a cost would show, how rows link without double
  counting): Phase A report with DECISIONS + proposed tickets, then build briefs.

## Red-team scope for a backfill that recomputes some documents
- Ask the red-team what the script LEAVES behind, not only what it writes: documents it skips or
  treats as posted can keep the old wrong value in a pending row that no later gate checks (it has a
  value, so a "missing value" guard passes). Fix: a list of every such row in the script and "list
  empty" as a go/no-go step at the freeze.
- Match rows to their source by the same representative-line rule the shared lib uses, never by item
  alone (unrelated lines of the same item make a good row skip).

## What still goes to a fix round under standing approval
- A review MINOR that leaves malformed stored money (0/0 or negative journal rows, totals still
  right): fix it before commit. A known ledger defect is never "a note".
- Review MINORs that are only stale comments or a script header: a comment-only ticket before the
  commit (diff = comment lines only, code files' sha256 unchanged, specs re-run once), so the commit
  never ships text that contradicts the final rule.
- Probe failures streamed from a reviewer's own run ("5 failed") are not findings: the probe may carry
  its own bug (wrong enum casing). Wait for the verdict before telling the user anything is broken.

## A worker overturns the PM's technical rule
- Verify the cited code, amend the decision row in place with the reason, and name the amendment in
  the re-review brief so the reviewer attacks it.
- A worker that STOPs because the PM's rule cannot be made correct did its job: choose the most
  conservative option that is provably correct, record it, and continue the same fix round with a
  "Run 2 (continue)" section in the brief.
- A heuristic that still fails the worker's own probes after the last fix round usually hides a missing
  stored relation. Offer the user "store the link" (nullable column + writer + reader preferring it +
  fallback for old rows + backfill) over another heuristic round.

## Backfilling a link (or any "fact" column) from legacy rows
- Write a value only where it is CERTAIN from stored data (e.g. the row the target itself names, in a
  set with no merged members). Rules over current row values can be fooled by edits made before the
  guard existed (two merged groups with swapped members look identical to a different true state), and
  the app treats a written value as fact forever.
- All-or-nothing per set: a half-linked set confuses the fallback for its unlinked neighbours.
- Any capacity/room formula the fallback uses must be the same named function the "already filled"
  check uses; two formulas drift (one forgot the inspection shortfall).
- Leave uncertain sets NULL and give the user the residual risk in plain words with options
  (e.g. refuse edits on those rows / accept / fix by hand).

## Deploy SQL that writes money (backfills outside git)
- Shape: `\set ON_ERROR_STOP on`, one transaction, dry run by default, `-v apply=1` to write,
  `SET LOCAL lock_timeout`, idempotent, a final in-script invariant check that aborts the whole run.
- The final check must reuse the SAME named predicate (CTE) as the plan; a check written separately
  drifts (it counted cancelled documents as receipts) and aborts every real run.
- Parity: run the app's own helper under node on the same inputs; 0 mismatches over a random sweep.
- When the design texts disagree on a case ("posted" vs "recompute"), the worker builds the no-write
  side, lists the rows, and STOPs; the PM turns it into a user decision with the facts (what happens to
  those rows later if left alone).
- Ask for a guard on the DB server version when the script reproduces an app float rule.

## Flaky test that only fails under the full suite and asserts an ORDER
- Running it alone N times proves nothing (it passes). Read the code path: a read without ORDER BY
  returns Postgres rows in physical order, which any UPDATE the ticket added changes.
- Fix in the code (sort by created time + id, one shared comparator), fold it into the same commit,
  prove with Phase A (order wrong before), 3 full-suite runs, and a mutation (remove the sort).
