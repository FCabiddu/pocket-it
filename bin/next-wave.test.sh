#!/usr/bin/env bash
# Self-test for next-wave.sh's sort key on mixed alphanumeric task ids (PI-6): a board that mixes
# purely-numeric ids (T-28.5.5) with ids carrying an alphabetic segment (T-BUG-1) used to blow up
# with "TypeError: '<' not supported between instances of 'int' and 'str'" and print nothing.
# Covers AC1-AC3 of PI-6.
# Also covers AC1 of PI-26: the model field is a suggestion, not a decision, and its name says so
# ("model_hint"), computed from Risk alone.
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

# --- AC4 (PI-25): a plain hyphenated word with no digits is not a task id — never fused into one fake task ---
P25R4="$S/repo_pi25_4"
mkdir -p "$P25R4/tasks"
printf '# Follow-up: something to check\n\n**Status**: Todo\n**Label**: DevOps\n**Files**: \n**TAD**: none\n\n## Acceptance criteria\n- ok\n' > "$P25R4/tasks/follow-up-1.md"
printf '# Follow-up: something else\n\n**Status**: Todo\n**Label**: DevOps\n**Files**: \n**TAD**: none\n\n## Acceptance criteria\n- ok\n' > "$P25R4/tasks/follow-up-2.md"
task "$P25R4" "PI-40" "Todo"
OUT=$(cd "$P25R4" && bash "$SCRIPT" 2>&1 >/tmp/next-wave-test-stdout2.$$); rc=$?
OUT_ERR="$OUT"; OUT_OUT=$(cat "/tmp/next-wave-test-stdout2.$$" 2>/dev/null); rm -f "/tmp/next-wave-test-stdout2.$$"
ok "AC4 a hyphenated word without digits is never read as a task id" '! grep -q "Follow-up" <<<"$OUT_OUT$OUT_ERR"'
ok "AC4 the two Follow-up notes are excluded from the total (1, not 3)" 'grep -q "1 total" <<<"$OUT_ERR"'

# --- AC5 (PI-25 third round): an alnum-mixed segment must not drop the task off the board ---
P25R5="$S/repo_pi25_5"
task "$P25R5" "STYLE-PR1" "Todo"
task "$P25R5" "WELCOME-A11Y-1" "Todo"
task "$P25R5" "E2E-4" "Todo"
OUT_OUT=$(cd "$P25R5" && bash "$SCRIPT" 2>/dev/null)
ok "AC5 STYLE-PR1 is read as a task"      'grep -q "\"issue\": \"STYLE-PR1\"" <<<"$OUT_OUT"'
ok "AC5 WELCOME-A11Y-1 is read as a task" 'grep -q "\"issue\": \"WELCOME-A11Y-1\"" <<<"$OUT_OUT"'
ok "AC5 E2E-4 is read as a task"          'grep -q "\"issue\": \"E2E-4\"" <<<"$OUT_OUT"'

# --- AC6 (PI-25 third round): a letter suffix on the number must not merge two distinct ids ---
P25R6="$S/repo_pi25_6"
task "$P25R6" "T-1.2.3a" "Todo"
task "$P25R6" "T-1.2.3b" "Todo"
task "$P25R6" "QF-10"    "Todo"
task "$P25R6" "QF-10b"   "Todo"
OUT_ERR=$(cd "$P25R6" && bash "$SCRIPT" 2>&1 >/dev/null)
ok "AC6 T-1.2.3a and T-1.2.3b both counted (4 total, none overwritten)" 'grep -q "4 total" <<<"$OUT_ERR"'

# --- PI-26 AC1: model field is named as a hint and computed from Risk alone ---
R4="$S/repo4"
mkdir -p "$R4/tasks"
printf '# T-HI-1: x\n\n**Status**: Todo\n**Label**: DevOps\n**Risk**: high\n**Files**: \n**TAD**: none\n\n## Acceptance criteria\n- ok\n' > "$R4/tasks/T-HI-1.md"
printf '# T-LO-1: x\n\n**Status**: Todo\n**Label**: DevOps\n**Risk**: low\n**Files**: \n**TAD**: none\n\n## Acceptance criteria\n- ok\n' > "$R4/tasks/T-LO-1.md"
OUT_OUT=$(cd "$R4" && bash "$SCRIPT" 2>/dev/null)
ok "PI-26 AC1 field is named model_hint, not model"    'grep -q "\"model_hint\"" <<<"$OUT_OUT" && ! grep -q "\"model\":" <<<"$OUT_OUT"'
ok "PI-26 AC1 high-risk task gets an opus hint"         'grep -q "\"issue\": \"T-HI-1\".*\"model_hint\": \"opus\"" <<<"$OUT_OUT"'
ok "PI-26 AC1 low-risk task gets a sonnet hint"         'grep -q "\"issue\": \"T-LO-1\".*\"model_hint\": \"sonnet\"" <<<"$OUT_OUT"'

exit $fail
