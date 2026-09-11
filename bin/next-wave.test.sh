#!/usr/bin/env bash
# Self-test for next-wave.sh's sort key on mixed alphanumeric task ids (PI-6): a board that mixes
# purely-numeric ids (T-28.5.5) with ids carrying an alphabetic segment (T-BUG-1) used to blow up
# with "TypeError: '<' not supported between instances of 'int' and 'str'" and print nothing.
# Covers AC1-AC3 of PI-6.
cd "$(dirname "$0")"
SCRIPT="$PWD/next-wave.sh"
S=$(mktemp -d "${TMPDIR:-/tmp}/next-wave-test.XXXXXX")
cleanup(){ rm -rf "$S"; }
trap cleanup EXIT
fail=0
ok(){ if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
has(){ grep -qF "$1" <<<"$OUT"; }

task(){ # task <dir> <id> <status> — minimal well-formed task file; Files left blank so no two test
        # fixtures ever collide on the file-overlap block (not under test here)
  mkdir -p "$1/tasks"
  printf '# %s: x\n\n**Status**: %s\n**Label**: DevOps\n**Files**: \n**TAD**: none\n\n## Acceptance criteria\n- ok\n' "$2" "$3" > "$1/tasks/${2//\//-}.md"
}

# --- AC1: mixed board (numeric-only id next to an id with an alphabetic segment) ---
R1="$S/repo1"
task "$R1" "T-28.5.5" "Todo"
task "$R1" "T-BUG-1"  "Todo"
OUT=$(cd "$R1" && bash "$SCRIPT" 2>&1 >/tmp/next-wave-test-stdout.$$); rc=$?
OUT_ERR="$OUT"; OUT_OUT=$(cat "/tmp/next-wave-test-stdout.$$" 2>/dev/null); rm -f "/tmp/next-wave-test-stdout.$$"
ok "AC1 exits without a Python exception"          '[[ $rc -eq 0 ]] && ! grep -q "TypeError" <<<"$OUT_ERR"'
ok "AC1 prints the summary line"                    'grep -q "next-wave: " <<<"$OUT_ERR"'
ok "AC1 prints the ready JSON for both tasks"        'grep -q "\"issue\": \"T-28.5.5\"" <<<"$OUT_OUT" && grep -q "\"issue\": \"T-BUG-1\"" <<<"$OUT_OUT"'

# --- AC2: purely numeric ids — order must stay the same as before the fix ---
R2="$S/repo2"
task "$R2" "T-1.2.3"  "Todo"
task "$R2" "T-1.10.1" "Todo"
task "$R2" "T-2.1.1"  "Todo"
OUT_OUT=$(cd "$R2" && bash "$SCRIPT" 2>/dev/null)
order=$(grep -o '"issue": "[^"]*"' <<<"$OUT_OUT" | sed -E 's/.*"([^"]+)"$/\1/' | tr '\n' ' ')
ok "AC2 numeric ids sorted numerically, not lexicographically" '[[ "$order" == "T-1.2.3 T-1.10.1 T-2.1.1 " ]]'

# --- AC3: different alphabetic ids — deterministic, and same-word numeric segment sorts numerically ---
R3="$S/repo3"
task "$R3" "T-BUG-1"  "Todo"
task "$R3" "QF-3"     "Todo"
task "$R3" "T-BUG-10" "Todo"
OUT_OUT=$(cd "$R3" && bash "$SCRIPT" 2>/dev/null)
order=$(grep -o '"issue": "[^"]*"' <<<"$OUT_OUT" | sed -E 's/.*"([^"]+)"$/\1/' | tr '\n' ' ')
OUT_OUT2=$(cd "$R3" && bash "$SCRIPT" 2>/dev/null)
order2=$(grep -o '"issue": "[^"]*"' <<<"$OUT_OUT2" | sed -E 's/.*"([^"]+)"$/\1/' | tr '\n' ' ')
ok "AC3 deterministic across repeated runs"          '[[ "$order" == "$order2" ]]'
bug1_pos=$(tr ' ' '\n' <<<"$order" | grep -n "^T-BUG-1$" | cut -d: -f1)
bug10_pos=$(tr ' ' '\n' <<<"$order" | grep -n "^T-BUG-10$" | cut -d: -f1)
ok "AC3 T-BUG-10 follows T-BUG-1 (numeric last segment)" '[[ -n "$bug1_pos" && -n "$bug10_pos" && $bug1_pos -lt $bug10_pos ]]'

exit $fail
