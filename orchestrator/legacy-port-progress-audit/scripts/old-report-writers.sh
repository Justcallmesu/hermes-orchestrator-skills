#!/usr/bin/env bash
# List every call site in the OLD app that writes a report row through a service, with the
# enclosing method name, so each event can be matched to the rewrite.
# Usage: bash old-report-writers.sh <old-src-modules-dir> <serviceVar> [<serviceVar>...]
#   e.g. bash old-report-writers.sh ~/legacy-app/server/src/modules \
#          vehicleConditionReportService vehicleUncountableHmReportService
# Calls inside the service's own module dir are skipped. Commented-out calls are NOT filtered:
# read the context of each hit (sed -n "$((l-25)),$((l+6))p" file) before counting it.
set -u
DIR=$1; shift
cd "$DIR" || exit 2
for v in "$@"; do
  echo "=== $v"
  own=$(echo "$v" | sed -E 's/Service$//; s/([a-z])([A-Z])/\1-\2/g' | tr 'A-Z' 'a-z')
  grep -rn "this\.$v\.\(create\|save\|update\|generate\|delete\|remove\|upsert\|insert\)[A-Za-z]*(" . --include=*.ts \
    | grep -v "/$own/" \
    | while IFS=: read -r f l rest; do
        m=$(head -n "$l" "$f" | grep -E '^\s+(async\s+)?[a-zA-Z0-9_]+\s*\(' \
              | grep -vE '\b(if|for|while|switch|catch|return|await)\b' | tail -1 \
              | sed -E 's/^\s*(async\s+)?([a-zA-Z0-9_]+).*/\2/')
        call=$(echo "$rest" | grep -oE "this\.$v\.[A-Za-z]+")
        echo "  $f:$l  in ${m}()  -> ${call#this.}"
      done
done
# The method name is a heuristic (last indented identifier followed by '('); it can name a helper
# call such as plainToInstance() instead of the method. Confirm from the context dump.
