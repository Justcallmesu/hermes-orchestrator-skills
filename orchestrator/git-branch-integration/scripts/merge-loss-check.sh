#!/bin/bash
# Usage: bash merge-loss-check.sh <other-branch> <target-before-sha> [<target-after-ref>]
# Omit <target-after-ref> to check the STAGED index of an in-progress merge (before commit).
# For every file <other-branch> changed since its merge-base with target-before, report whether
# the other side's version survived on target-after:
#   SAME    = identical to other-branch
#   DROPPED = identical to target-before (other side's change lost entirely)
#   MIXED   = neither (inspect: partial loss or legit combination; see the line check below)
# Then the reverse: files target-before changed that now equal other-branch (target's change lost).
# Then, for every MIXED file: how many lines each side ADDED are missing from the result
# (0 missing on both sides = an additive resolution, e.g. two changelog entries kept).
# All output goes to stdout in order, so `> file 2>&1` gives a readable report.
set -u
OTHER=$1; BEFORE=$2; AFTER=${3:-}
BASE=$(git merge-base "$OTHER" "$BEFORE")
echo "merge-base: $BASE  (after: ${AFTER:-<index>})"
same_as() { # $1 ref, $2 file -> 0 if AFTER/index equals ref for file
  if [ -n "$AFTER" ]; then git diff --quiet "$1" "$AFTER" -- "$2"
  else git diff --cached --quiet "$1" -- "$2"; fi
}
result_of() { # $1 file -> content in AFTER or the index
  if [ -n "$AFTER" ]; then git show "$AFTER:$1"; else git show ":$1"; fi
}
LIST=$(for f in $(git diff --name-only "$BASE" "$OTHER"); do
  if same_as "$OTHER" "$f"; then s=SAME
  elif same_as "$BEFORE" "$f"; then s=DROPPED
  else s=MIXED; fi
  echo "$s $f"
done | sort)
echo "$LIST"
echo "== summary =="
echo "$LIST" | cut -d' ' -f1 | uniq -c
echo "== target-side changes lost (file now equals $OTHER though target changed it) =="
for f in $(git diff --name-only "$BASE" "$BEFORE"); do
  git diff --quiet "$BASE" "$OTHER" -- "$f" && continue   # other side never touched it
  same_as "$OTHER" "$f" && echo "TARGET_DROPPED? $f"
done
echo "== MIXED files: added lines missing from the result =="
T=$(mktemp -d)
for f in $(echo "$LIST" | awk '$1=="MIXED"{print $2}'); do
  result_of "$f" > "$T/result"
  for side in "$BEFORE" "$OTHER"; do
    git diff "$BASE" "$side" -- "$f" | grep '^+' | grep -v '^+++' | cut -c2- | grep -v '^\s*$' > "$T/added"
    missing=0
    while IFS= read -r line; do grep -qxF -- "$line" "$T/result" || missing=$((missing+1)); done < "$T/added"
    echo "$f  side ${side:0:8}: $(wc -l < "$T/added") added, $missing missing"
  done
done
rm -rf "$T"
