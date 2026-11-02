#!/usr/bin/env bash
# Merge the COMMITTED tip of <branch> into <target> (--no-ff shape) and push, WITHOUT checkout:
# the working tree (other workers' uncommitted edits) is never touched.
# Valid when nothing new landed on <target> since the gate: either <target> is an ancestor of
# <branch>, or <target> is an EARLIER merge of this same branch (second merge of a run) whose tree
# equals the merge base. The merge tree == branch tree by construction (asserted).
# Usage: bash merge-committed-no-checkout.sh <branch> <target> <repo>...
set -eu
B=$1; T=$2; shift 2
for R in "$@"; do
  cd "$R"; echo "===== $R"
  git fetch -q origin
  [ "$(git rev-parse "$T")" = "$(git rev-parse "origin/$T")" ] || { echo "local $T != origin/$T"; exit 1; }
  if ! git merge-base --is-ancestor "$T" "$B"; then
    MB=$(git merge-base "$T" "$B")
    git diff --quiet "$T" "$MB" || { echo "$T has changes not in $B: merge normally"; exit 1; }
    echo "$T = earlier merge of $B (tree == merge base $(git rev-parse --short "$MB"))"
  fi
  FEAT=$(git rev-parse "$B"); BASE=$(git rev-parse "$T")
  [ "$FEAT" != "$BASE" ] || { echo "nothing to merge"; continue; }
  echo "commits merged:"; git log --oneline "$BASE..$FEAT"
  M=$(git commit-tree "$FEAT^{tree}" -p "$BASE" -p "$FEAT" -m "Merge branch '$B' into $T")
  [ "$(git rev-parse "$M^{tree}")" = "$(git rev-parse "$FEAT^{tree}")" ] || { echo "merge tree != branch tree"; exit 1; }
  git push -q origin "$M:refs/heads/$T"
  git update-ref "refs/heads/$T" "$M" "$BASE"
  git fetch -q origin
  echo "$T local $(git rev-parse --short "$T") remote $(git rev-parse --short "origin/$T"); still on $(git branch --show-current)"
done
echo ALL_DONE
