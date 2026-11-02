---
name: git-commit-in-dirty-tree
description: "Use to commit only your changes beside the user's edits."
---

# Commit only your own work in a dirty tree

## When to Use
The working tree holds uncommitted edits you did not make, sometimes in the SAME file as yours,
and the user asked you to commit your part. Never touch, stash, reset or commit their work.

## Procedure
1. `git status --short` and `git diff --stat` to separate yours from theirs. For a mixed file,
   `git diff -U0 <file>` and list which hunks are yours.
2. Files that are entirely yours: `git add <file>`. Never `git add -A` / `commit -a`.
3. Mixed file: build the blob yourself. Take `git show HEAD:<file>`, re-apply only your hunks in
   a small Python script, write it to `$TMPDIR`, then
   `git hash-object -w <tmp>` and `git update-index --cacheinfo 100644,<hash>,<file>`.
   The working copy stays untouched, so their edits survive. Re-run `git hash-object` after any
   fix; strip a trailing blank line (`git apply` warns "new blank line at EOF").
4. Prove the staged set stands alone, in a throwaway worktree (not by stashing):
   `git worktree add --detach $TMPDIR/wt HEAD`; `git diff --cached | (cd $TMPDIR/wt && git apply)`;
   symlink `node_modules`, copy `.env`; run the relevant test suites there;
   `git worktree remove --force $TMPDIR/wt`. Expect fewer tests than the dirty tree: theirs that
   depend on their uncommitted code are not in the commit.
5. Formatter/linter: check only YOUR lines. To learn whether a warning pre-exists, run the
   formatter on `git show HEAD:<file>` copied to `$TMPDIR` (use the repo config explicitly).
   Do not reformat pre-existing lines inside your commit.
6. Commit with a conventional message; body explains why. `git status --short` afterward must
   show the user's files still modified. Report what was included, what was left out, and that
   nothing was pushed.

## Pitfalls
- `git stash` / `stash pop` to get a baseline briefly rewrites the user's files and can fail
  halfway - compare against `git show HEAD:<file>` or a worktree instead.
- Ask before committing when the repo's own rules say so; do not push unless told.
- A baseline error count (e.g. `tsc`) is only comparable on the same tree; compare counts, not
  absolute zero, when pre-existing errors exist.
