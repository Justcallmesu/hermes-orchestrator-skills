#!/usr/bin/env bash
# Merge a gated feature/fix branch into a target branch (--no-ff) in one or more repos, then push the
# target fast-forward only. Run only after the user explicitly asked to merge AND push.
# Usage: AUTHOR_NAME=x AUTHOR_EMAIL=y bash merge-no-ff-and-push.sh <branch> <target> <repo-dir>...
# Before running: read .github/workflows/* `on:` for the target (a push to a release branch may deploy).
# Two passes: every repo is checked first, so a failing check never leaves repo 1 merged+pushed and
# repo 2 untouched.
set -eu
B=$1; T=$2; shift 2
export GIT_AUTHOR_NAME="${AUTHOR_NAME:?}" GIT_AUTHOR_EMAIL="${AUTHOR_EMAIL:?}"
for R in "$@"; do
  cd "$R"; echo "===== preflight $R"
  git fetch -q origin
  [ "$(git branch --show-current)" = "$B" ] || { echo "not on $B"; exit 1; }
  [ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "tracked changes present"; exit 1; }
  if [ "$(git rev-parse "$T")" != "$(git rev-parse "origin/$T")" ]; then
    # Local target merely behind the remote (never committed to locally): fast-forward the ref.
    git merge-base --is-ancestor "$T" "origin/$T" || { echo "local $T has commits origin/$T lacks"; exit 1; }
    git branch -f "$T" "origin/$T"; echo "fast-forwarded local $T to origin/$T"
  fi
  # The gate ran on the branch; it still holds only if the target has not moved since.
  git merge-base --is-ancestor "$T" "$B" || { echo "$T moved since the gate: merge origin/$T into $B and re-gate"; exit 1; }
done
for R in "$@"; do
  cd "$R"; echo "===== $R"
  FEAT=$(git rev-parse "$B")
  git checkout -q "$T"
  git merge --no-ff -q -m "Merge branch '$B' into $T" "$FEAT"
  git diff --quiet HEAD "$FEAT" || { echo "merged tree != gated tree"; exit 1; }
  git merge-base --is-ancestor "origin/$T" "$T" || { echo "not a fast-forward"; exit 1; }
  git push -q origin "$T:$T"
  git fetch -q origin
  echo "$T local $(git rev-parse --short "$T") remote $(git rev-parse --short "origin/$T")"
done
echo ALL_DONE
