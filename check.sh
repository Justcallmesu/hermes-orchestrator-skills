#!/usr/bin/env bash
# Read-only setup check. Changes nothing. Usage: ./check.sh [profile ...]   (default: default pm)
HERE="$(cd "$(dirname "$0")" && pwd)"; SK="$HERE/orchestrator"; fail=0
ok(){ echo "ok    $*"; }; bad(){ echo "MISS  $*"; fail=1; }
HH="${HERMES_HOME_ROOT:-$HOME/.hermes}"
profiles=("$@"); [ ${#profiles[@]} -eq 0 ] && profiles=(default pm)
for p in "${profiles[@]}"; do
  if [ "$p" = default ]; then dir="$HH"; else dir="$HH/profiles/$p"; fi
  [ -d "$dir" ] || { bad "profile $p ($dir not found)"; continue; }
  if grep -qE 'hermes-orchestrator-skills/orchestrator' "$dir/config.yaml" 2>/dev/null; then
    ok "$p: external_dirs points at this repo"
  else bad "$p: skills.external_dirs does not list $SK"; fi
  for s in "$SK"/*/; do n=$(basename "$s")
    c=$(find "$dir/skills" -type d -name "$n" -not -path "$SK/*" 2>/dev/null | head -1)
    [ -z "$c" ] || bad "$p: duplicate local copy of $n at $c (local wins over the repo)"
  done
  for dep in pm-discovery claude-code to-tickets; do
    find "$dir/skills" -type d -name "$dep" 2>/dev/null | grep -q . && ok "$p: skill $dep" || bad "$p: skill $dep not installed"
  done
done
if [ -d "$HH/plugins/omh" ] || hermes plugins list 2>/dev/null | grep -qw omh; then ok "plugin omh"
else bad "plugin omh (needed by omh-autopilot, omh-ralph, omh-ralph-driver)"; fi
for r in developer reviewer; do [ -d "$HH/profiles/$r" ] && ok "profile $r" || bad "profile $r (thin-orchestrator launches it)"; done
for f in $(find "$SK" -name SKILL.md); do head -1 "$f" | grep -q '^---$' || bad "bad frontmatter: $f"; done
exit $fail
