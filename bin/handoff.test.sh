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

# --- PI-8: log rotation archives the overflow instead of dropping it ---
S4=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test4.XXXXXX")
git init -q "$S4" >/dev/null
F4="$S4/docs/SESSION_HANDOFF.md"; ARCHIVE4="$S4/docs/SESSION_HANDOFF_ARCHIVE.md"
loglines4(){ awk '/^## Log/{f=1;next} f && /^- /{c++} END{print c+0}' "$F4"; }
archlines4(){ [[ -f "$ARCHIVE4" ]] && awk '/^- /{c++} END{print c+0}' "$ARCHIVE4" || echo 0; }
for i in $(seq 1 40); do (cd "$S4" && bash "$SCRIPT" log "line $i" >/dev/null 2>&1); done
ok "PI-8 setup — 40 log lines present before the rotating add" '[[ "$(loglines4)" -eq 40 ]]'

# PI-8 AC1 — the line pushed out of the last 40 lands in the archive: total (log + archive) grows by one
totalbefore4=$(( $(loglines4) + $(archlines4) ))
(cd "$S4" && bash "$SCRIPT" log "line 41" >/dev/null 2>&1)
totalafter4=$(( $(loglines4) + $(archlines4) ))
ok "PI-8 AC1 — total lines (log + archive) grow by one" '[[ "$totalafter4" -eq $((totalbefore4 + 1)) ]]'
ok "PI-8 AC1 — the oldest line (line 1) is in the archive, not in the log" 'grep -qE "line 1$" "$ARCHIVE4" && ! grep -qE "line 1$" "$F4"'

# PI-8 AC2 — the main log section still has 40 lines, the newest on top
ok "PI-8 AC2 — main log still has 40 lines" '[[ "$(loglines4)" -eq 40 ]]'
firstlogline4=$(awk '/^## Log/{f=1;next} f && /^- /{print;exit}' "$F4")
ok "PI-8 AC2 — the newest line is on top" '[[ "$firstlogline4" == *"line 41"* ]]'

# PI-8 AC3 — a pre-existing archive is appended to, not overwritten, by the next rotation
(cd "$S4" && bash "$SCRIPT" log "line 42" >/dev/null 2>&1)
ok "PI-8 AC3 — line 1 (archived first) survives a second rotation" 'grep -qE "line 1$" "$ARCHIVE4"'
ok "PI-8 AC3 — line 2 (archived second) is also there" 'grep -qE "line 2$" "$ARCHIVE4"'
ok "PI-8 AC3 — archive has exactly 2 lines after two rotations" '[[ "$(archlines4)" -eq 2 ]]'

# PI-8 AC4 — below the cap, no archive file is created and no line is moved
S5=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test5.XXXXXX")
git init -q "$S5" >/dev/null
(cd "$S5" && bash "$SCRIPT" log "only one line" >/dev/null 2>&1)
ok "PI-8 AC4 — no archive file is created below the cap" '[[ ! -f "$S5/docs/SESSION_HANDOFF_ARCHIVE.md" ]]'

# PI-8 AC5 — a rotation that moves N lines says so, with N, on its output
out4=$(cd "$S4" && bash "$SCRIPT" log "line 43" 2>&1)
ok "PI-8 AC5 — output names the archived count" '[[ "$out4" == *"archived 1 line"* ]]'
rm -rf "$S4" "$S5"

# --- PI-8 review finding 1 — one order for the whole archive, not "newest-first inside a batch,
# oldest-first across batches". Hand-build a log already past the cap by 5 (45 lines) so a single
# rotation evicts 6 lines at once: this is the only way to see within-batch order at all.
S6=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test6.XXXXXX")
git init -q "$S6" >/dev/null
mkdir -p "$S6/docs"
F6="$S6/docs/SESSION_HANDOFF.md"; ARCHIVE6="$S6/docs/SESSION_HANDOFF_ARCHIVE.md"
{
  echo "# Session handoff"; echo
  echo "## Fatti che non scadono"; echo
  echo "## Log (più recente in alto, ultime 40 righe)"
  for i in $(seq 45 -1 1); do echo "- 2026-01-01 entry $i"; done
} > "$F6"
archfirst6(){ awk '/^- /{print;exit}' "$ARCHIVE6"; }
archlast6(){ awk '/^- /{l=$0} END{print l}' "$ARCHIVE6"; }
archcount6(){ awk '/^- /{c++} END{print c+0}' "$ARCHIVE6"; }
(cd "$S6" && bash "$SCRIPT" log "entry 46" >/dev/null 2>&1)
ok "PI-8 F1 — a 6-line batch lands in the archive whole" '[[ "$(archcount6)" -eq 6 ]]'
ok "PI-8 F1 — within that batch, the oldest overall (entry 1) is at the top" '[[ "$(archfirst6)" == *"entry 1" ]]'
ok "PI-8 F1 — within that batch, the newest-of-the-evicted (entry 6) is at the bottom" '[[ "$(archlast6)" == *"entry 6" ]]'
# a later rotation must extend the SAME order, not restart it: its line lands below the earlier batch,
# and the oldest-ever entry stays at the very top — one order end to end, never two.
(cd "$S6" && bash "$SCRIPT" log "entry 47" >/dev/null 2>&1)
ok "PI-8 F1 — a later rotation's line lands below the earlier batch (entry 7 after entry 6)" '[[ "$(archlast6)" == *"entry 7" ]]'
ok "PI-8 F1 — the oldest entry ever archived is still at the very top" '[[ "$(archfirst6)" == *"entry 1" ]]'
rm -rf "$S6"

# --- PI-8 review finding 2 — LOGCAP must be the only place the 40 lives; nothing else repeats it by hand.
# Case A: the file created from scratch (no docs/SESSION_HANDOFF.md at all) must show the live LOGCAP in
# its "## Log" header, and the heredoc must actually have interpolated it (not leaked "$LOGCAP" as text).
S7=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test7.XXXXXX")
git init -q "$S7" >/dev/null
(cd "$S7" && bash "$SCRIPT" show >/dev/null 2>&1)
ok "PI-8 F2a — a freshly created file's Log header shows the live cap" \
   'grep -qF "## Log (più recente in alto, ultime 40 righe)" "$S7/docs/SESSION_HANDOFF.md"'
ok "PI-8 F2a — heredoc interpolation fired, no literal \$LOGCAP leaked into the file" \
   '! grep -qF "\$LOGCAP" "$S7/docs/SESSION_HANDOFF.md"'
rm -rf "$S7"
# Case B: the file exists but has no "## Log" section yet (an older file, or one built by hand) — the
# python fallback that adds the section must also derive from LOGCAP, never repeat 40 by hand.
S8=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test8.XXXXXX")
git init -q "$S8" >/dev/null
mkdir -p "$S8/docs"
cat > "$S8/docs/SESSION_HANDOFF.md" <<'EOF'
# Session handoff

## Fatti che non scadono
- an existing fact
EOF
(cd "$S8" && bash "$SCRIPT" log "first log entry ever" >/dev/null 2>&1)
ok "PI-8 F2b — the fallback header (no prior '## Log' section) shows the live cap" \
   'grep -qF "## Log (più recente in alto, ultime 40 righe)" "$S8/docs/SESSION_HANDOFF.md"'
rm -rf "$S8"
# Structural guard: the fallback header line in the script itself must build the number from {logcap},
# never spell it out — this is what actually failed before the fix (line hardcoded "ultime 40 righe").
ok "PI-8 F2 — the script's fallback header interpolates {logcap}, it does not hardcode 40" \
   '! grep -nE "if not sep:.*ultime 40 righe\)" "$SCRIPT"'
ok "PI-8 F2 — and it does spell out the interpolation, so the guard above is not vacuous" \
   'grep -nE "if not sep:.*\{logcap\} righe\)" "$SCRIPT" >/dev/null'

[[ "$fail" -eq 0 ]] && echo "handoff.test.sh: all ok" || echo "handoff.test.sh: FAILURES"
exit "$fail"
