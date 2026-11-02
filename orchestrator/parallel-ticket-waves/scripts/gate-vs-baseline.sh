#!/usr/bin/env bash
# PM gate for one or more tickets: HEAD + the given files on a fresh throwaway DB, typecheck, unit
# tests, every HTTP suite, then compare against a baseline suites file recorded on clean HEAD.
# Usage: bash gate-vs-baseline.sh <gate-id> <repo-relative file>...
# Expects (adapt per project): $W/worker-env.sh (builds HEAD+files copy, creates DB erp_<id>, starts
# backend, prints API_URL), $W/api-suites.sh <port> <out> <dir> (one summary line per suite + indented
# FAIL lines), $BASELINE (same format, from clean HEAD on a fresh DB, same suite order).
set -u
GID=$1; shift
W=${W:?set W to the scratch dir}
BASELINE=${BASELINE:-$W/baseline-suites.txt}
R=${RUNS_DIR:-$W/gates}/$GID
mkdir -p "$R"
SAFE=$(echo "$GID" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9\n' '_')
FRESH=1 bash $W/worker-env.sh "$GID" "$@" > $R/env.log 2>&1
tail -2 $R/env.log
DIR=$W/w/$SAFE/server
PORT=$(grep -o 'API_URL=http://127.0.0.1:[0-9]*' $R/env.log | tail -1 | cut -d: -f3)
cd "$DIR"
npx tsc --noEmit -p tsconfig.json > $R/tsc.log 2>&1; echo "tsc exit $?"
npx jest src > $R/jest.log 2>&1; grep -E "Tests:|Test Suites:|FAIL" $R/jest.log
# Suites that set up rows by direct SQL need the scratch DB AND the scratch cluster address.
export TEST_DB=erp_$SAFE TEST_SCHEMA=${TEST_SCHEMA:-t_default} PGHOST=127.0.0.1 PGPORT=${PGPORT:-55432} PGPASSWORD=${PGPASSWORD:-postgres}
bash $W/api-suites.sh "$PORT" $R/suites.txt "$DIR"
echo "deadlocks: $(grep -c 'deadlock detected' $W/api-erp_$SAFE.log)"
kill $(cat $W/api-erp_$SAFE.pid) 2>/dev/null
echo "== suite summary diff (baseline < > gate)"
diff <(grep -v '^    ' $BASELINE) <(grep -v '^    ' $R/suites.txt)
echo "== crashed suites (exit!=0 with 0 FAIL lines): read their output"
grep -E ' 0 fail \(exit [1-9]' $R/suites.txt
norm() { grep '^    ' "$1" | sed -E 's/ :: .*//' | sort -u; }
echo "== FAIL lines new vs baseline (regressions unless order-dependent; rerun alone to check)"
comm -13 <(norm $BASELINE) <(norm $R/suites.txt)
echo "== FAIL lines fixed vs baseline"
comm -23 <(norm $BASELINE) <(norm $R/suites.txt)
echo GATE_DONE
