# Merge the committed branch state while workers still edit the tree

Use when the user asks to merge/push mid-run and worker agents have uncommitted edits in the same working tree (checkout develop would carry or clash with them).

Rule: build the merge commit with plumbing, never touch the working tree or switch branches.

```bash
git fetch -q origin
[ "$(git rev-parse develop)" = "$(git rev-parse origin/develop)" ] || exit 1
git merge-base --is-ancestor develop "$B" || exit 1   # develop must be an ancestor, so tree == branch tree
FEAT=$(git rev-parse "$B"); DEV=$(git rev-parse develop)
M=$(git commit-tree "$FEAT^{tree}" -p "$DEV" -p "$FEAT" -m "Merge branch '$B' into develop")
git push -q origin "$M:refs/heads/develop"        # fast-forward of origin/develop
git update-ref refs/heads/develop "$M" "$DEV"
```

Why: only commits that already passed the gate go in; in-flight edits stay out; the merge tree is provably identical to the gated branch tree. Put it in a script file (shell approval quirk). Record afterwards which tickets are NOT in the merge (they need a second merge) and add their author/--no-ff conventions as usual (commit-tree uses the configured committer; set GIT_AUTHOR_* env if the project fixes the author).
