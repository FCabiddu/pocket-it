#!/usr/bin/env bash
# Self-test for handoff.sh — the fact cap must refuse a new fact at 100/100 instead of dropping the oldest.
# Covers AC1 (99th->100th add lands with the cap warning), AC2 (refused past the cap, file unchanged, exit 3),
# AC3 (show marks the cap, absent below it), AC4 (a stale "max 30 righe" comment is normalised on any run),
# AC5 (log unaffected by the facts cap).
set -uo pipefail
cd "$(dirname "$0")"
SCRIPT="$PWD/handoff.sh"
CAP=100
S=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test.XXXXXX")
cleanup(){ rm -rf "$S"; }
trap cleanup EXIT
fail=0
ok(){ if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
git init -q "$S" >/dev/null

# --- fill to CAP-1 facts via a loop, not literal lines ---
for i in $(seq 1 $((CAP - 1))); do (cd "$S" && bash "$SCRIPT" fact "fact number $i" >/dev/null 2>&1); done
F="$S/docs/SESSION_HANDOFF.md"
count(){ awk '/^## Fatti che non scadono/{f=1;next} /^## /{f=0} f && /^- /{c++} END{print c+0}' "$F"; }
ok "$((CAP - 1)) facts present before the last add" "[[ \"\$(count)\" -eq $((CAP - 1)) ]]"

# --- AC1: the fact that reaches the cap lands (exit 0) and warns on stderr that the cap is reached ---
outcap=$(cd "$S" && bash "$SCRIPT" fact "fact number $CAP" 2>&1 1>/dev/null); rccap=$?
ok "AC1 — fact reaching the cap lands with exit 0" '[[ "$rccap" -eq 0 ]]'
ok "AC1 — stderr warns the cap is reached" "[[ \"\$outcap\" == \"handoff: facts $CAP/$CAP — cap reached, next fact will be refused\" ]]"
ok "AC1 — the fact reaching the cap is actually in the file" 'grep -qF "fact number '"$CAP"'" "$F"'
ok "file has exactly $CAP facts after that add" "[[ \"\$(count)\" -eq $CAP ]]"

# --- AC2: at the cap, a new fact is refused, file unchanged, exit 3, precise stderr line ---
before=$(cat "$F")
next=$((CAP + 1))
out2=$(cd "$S" && bash "$SCRIPT" fact "fact number $next" 2>&1 1>/dev/null); rc2=$?
after=$(cat "$F")
ok "AC2 — refused fact exits 3" '[[ "$rc2" -eq 3 ]]'
ok "AC2 — file unchanged when refused" '[[ "$before" == "$after" ]]'
ok "AC2 — file still has $CAP facts, not $next" "[[ \"\$(count)\" -eq $CAP ]]"
ok "AC2 — the new fact is not in the file" "! grep -qF \"fact number $next\" \"\$F\""
expected2="handoff: facts at cap ($CAP/$CAP) — not added. Ask the retro to promote stable facts to best-practices, or remove one line by hand: fact number $next"
ok "AC2 — exact stderr line" '[[ "$out2" == "$expected2" ]]'

# --- log behaviour is unchanged — it still rotates at 40, silently, regardless of the facts cap ---
outlog=$(cd "$S" && bash "$SCRIPT" log "some event happened" 2>&1); rclog=$?
ok "log still exits 0 at the facts cap" '[[ "$rclog" -eq 0 ]]'
ok "log prints its usual message" '[[ "$outlog" == "handoff: logged" ]]'
for i in $(seq 1 45); do (cd "$S" && bash "$SCRIPT" log "log line $i" >/dev/null 2>&1); done
loglines=$(awk '/^## Log/{f=1;next} f && /^- /{c++} END{print c+0}' "$F")
ok "log still caps at 40 lines" '[[ "$loglines" -eq 40 ]]'

# --- AC3: show ends with the cap marker when facts are at the cap ---
showout=$(cd "$S" && bash "$SCRIPT" show)
lastline=$(printf '%s\n' "$showout" | tail -1)
ok "AC3 — show ends with the cap marker" "[[ \"\$lastline\" == \"facts: $CAP/$CAP (cap)\" ]]"

# --- sanity: below the cap, show does not print the cap marker ---
S2=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test2.XXXXXX")
git init -q "$S2" >/dev/null
(cd "$S2" && bash "$SCRIPT" fact "only one fact" >/dev/null 2>&1)
showout2=$(cd "$S2" && bash "$SCRIPT" show)
ok "AC3 — below cap, show has no cap marker" "! grep -qF \"facts: $CAP/$CAP (cap)\" <<<\"\$showout2\""

# --- AC4: a project handoff file whose comment still says "max 30 righe" gets it normalised to the
# current cap on any subcommand run, and the command works unchanged ---
S3=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test3.XXXXXX")
git init -q "$S3" >/dev/null
mkdir -p "$S3/docs"
cat > "$S3/docs/SESSION_HANDOFF.md" <<'EOF'
# Session handoff

Memoria della pipeline, scritta dagli agenti. Lo stato del lavoro non sta qui (si calcola con `status.sh`): qui stanno i fatti che non scadono e il log degli eventi.

## Fatti che non scadono
<!-- max 30 righe: invarianti, gotcha, decisioni e perché. Chi aggiunge una riga toglie quella che non vale più. -->
- an existing fact

## Log (più recente in alto, ultime 40 righe)
EOF
(cd "$S3" && bash "$SCRIPT" show >/dev/null 2>&1)
ok "AC4 — stale 'max 30 righe' comment is normalised to the new cap" "grep -qF \"max $CAP righe:\" \"$S3/docs/SESSION_HANDOFF.md\""
ok "AC4 — pre-existing fact survives the normalisation" "grep -qF 'an existing fact' \"$S3/docs/SESSION_HANDOFF.md\""
rm -rf "$S2" "$S3"

[[ "$fail" -eq 0 ]] && echo "handoff.test.sh: all ok" || echo "handoff.test.sh: FAILURES"
exit "$fail"
