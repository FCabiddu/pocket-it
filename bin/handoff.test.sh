#!/usr/bin/env bash
# Self-test for handoff.sh — the fact cap must refuse a new fact at 30/30 instead of dropping the oldest.
# Covers AC1 (refuse at cap), AC2 (warning on the fact that reaches the cap), AC3 (log unaffected), AC4 (show marks the cap).
set -uo pipefail
cd "$(dirname "$0")"
SCRIPT="$PWD/handoff.sh"
S=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test.XXXXXX")
cleanup(){ rm -rf "$S"; }
trap cleanup EXIT
fail=0
ok(){ if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
git init -q "$S" >/dev/null

# --- AC2: fill to 29 facts, the 30th add lands (exit 0) and warns on stderr that the cap is reached ---
for i in $(seq 1 29); do (cd "$S" && bash "$SCRIPT" fact "fact number $i" >/dev/null 2>&1); done
F="$S/docs/SESSION_HANDOFF.md"
count(){ awk '/^## Fatti che non scadono/{f=1;next} /^## /{f=0} f && /^- /{c++} END{print c+0}' "$F"; }
ok "29 facts present before the 30th add" '[[ "$(count)" -eq 29 ]]'

out30=$(cd "$S" && bash "$SCRIPT" fact "fact number 30" 2>&1 1>/dev/null); rc30=$?
ok "AC2 — 30th fact lands with exit 0" '[[ "$rc30" -eq 0 ]]'
ok "AC2 — stderr warns the cap is reached" '[[ "$out30" == "handoff: facts 30/30 — cap reached, next fact will be refused" ]]'
ok "AC2 — the 30th fact is actually in the file" 'grep -qF "fact number 30" "$F"'
ok "file has exactly 30 facts after the 30th add" '[[ "$(count)" -eq 30 ]]'

# --- AC1: at the cap, a new fact is refused, file unchanged, exit 3, precise stderr line ---
before=$(cat "$F")
out31=$(cd "$S" && bash "$SCRIPT" fact "fact number 31" 2>&1 1>/dev/null); rc31=$?
after=$(cat "$F")
ok "AC1 — refused fact exits 3" '[[ "$rc31" -eq 3 ]]'
ok "AC1 — file unchanged when refused" '[[ "$before" == "$after" ]]'
ok "AC1 — file still has 30 facts, not 31" '[[ "$(count)" -eq 30 ]]'
ok "AC1 — the new fact is not in the file" '! grep -qF "fact number 31" "$F"'
expected1="handoff: facts at cap (30/30) — not added. Ask the retro to promote stable facts to best-practices, or remove one line by hand: fact number 31"
ok "AC1 — exact stderr line" '[[ "$out31" == "$expected1" ]]'

# --- AC3: log behaviour is unchanged — it still rotates at 40, silently, regardless of the facts cap ---
outlog=$(cd "$S" && bash "$SCRIPT" log "some event happened" 2>&1); rclog=$?
ok "AC3 — log still exits 0 at the facts cap" '[[ "$rclog" -eq 0 ]]'
ok "AC3 — log prints its usual message" '[[ "$outlog" == "handoff: logged" ]]'
for i in $(seq 1 45); do (cd "$S" && bash "$SCRIPT" log "log line $i" >/dev/null 2>&1); done
loglines=$(awk '/^## Log/{f=1;next} f && /^- /{c++} END{print c+0}' "$F")
ok "AC3 — log still caps at 40 lines" '[[ "$loglines" -eq 40 ]]'

# --- AC4: show ends with the cap marker when facts are at 30/30 ---
showout=$(cd "$S" && bash "$SCRIPT" show)
lastline=$(printf '%s\n' "$showout" | tail -1)
ok "AC4 — show ends with the cap marker" '[[ "$lastline" == "facts: 30/30 (cap)" ]]'

# --- sanity: below the cap, show does not print the cap marker ---
S2=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test2.XXXXXX")
git init -q "$S2" >/dev/null
(cd "$S2" && bash "$SCRIPT" fact "only one fact" >/dev/null 2>&1)
showout2=$(cd "$S2" && bash "$SCRIPT" show)
ok "below cap — show has no cap marker" '! grep -qF "facts: 30/30 (cap)" <<<"$showout2"'
rm -rf "$S2"

[[ "$fail" -eq 0 ]] && echo "handoff.test.sh: all ok" || echo "handoff.test.sh: FAILURES"
exit "$fail"
