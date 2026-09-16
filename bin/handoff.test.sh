#!/usr/bin/env bash
# Self-test for handoff.sh — the fact cap must refuse a new fact at 100/100 instead of dropping the oldest.
# Covers AC1 (99th->100th add lands with the cap warning), AC2 (refused past the cap, file unchanged, exit 3),
# AC3 (show marks the cap, absent below it), AC4 (a stale "max 30 righe" comment is normalised on any run),
# AC5 (log unaffected by the facts cap).
# Also covers PI-9 (log/fact confirmations name the path of the file they wrote, exit codes and
# redirected output unchanged).
set -uo pipefail
cd "$(dirname "$0")"
SCRIPT="$PWD/handoff.sh"
CAP=100
S=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test.XXXXXX")
S=$(cd "$S" && pwd -P)   # resolve any symlink (e.g. macOS /tmp) so it matches git's resolved toplevel
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
ok "AC1 — stderr warns the cap is reached" "[[ \"\$outcap\" == \"handoff: facts $CAP/$CAP — cap reached, next fact will be refused — $F\" ]]"
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
ok "log prints its usual message" "[[ \"\$outlog\" == \"handoff: logged — $F\" ]]"
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
# current cap on the next WRITE (PI-14 moves this off `show`: reads never touch the file any more, ADR-2
# — so the trigger here is `fact`, not `show`) ---
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
(cd "$S3" && bash "$SCRIPT" fact "a normalising write" >/dev/null 2>&1)
ok "AC4 — stale 'max 30 righe' comment is normalised on the next write" "grep -qF \"max $CAP righe:\" \"$S3/docs/SESSION_HANDOFF.md\""
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

# --- PI-39: `log` normalises a message that already starts with an ISO date, so the line never carries
# two dates (main's own history had exactly this: a caller passed a message already starting with a
# date, doubling it). Case table per AC1, one date dimension each, not a single example: prefix equal to
# today, prefix different from today, a repeated double prefix, and the limit case of a message that IS
# just a date with nothing else in it. AC2: a date NOT at the very start of the message is left
# untouched — only a LEADING one is ever stripped.
S19=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test19.XXXXXX")
git init -q "$S19" >/dev/null
F19="$S19/docs/SESSION_HANDOFF.md"
TODAY=$(date +%Y-%m-%d)
lastlog19(){ awk '/^## Log/{f=1;next} f && /^- /{print;exit}' "$F19"; }

(cd "$S19" && bash "$SCRIPT" log "$TODAY testo uno" >/dev/null 2>&1)
ok "PI-39 AC1 — prefix equal to today's date is stripped, one date left" \
   '[[ "$(lastlog19)" == "- $TODAY testo uno" ]]'

(cd "$S19" && bash "$SCRIPT" log "2020-01-01 testo due" >/dev/null 2>&1)
ok "PI-39 AC1 — prefix different from today is stripped, not kept alongside today's" \
   '[[ "$(lastlog19)" == "- $TODAY testo due" ]]'

(cd "$S19" && bash "$SCRIPT" log "2026-09-01 2026-09-02 testo tre" >/dev/null 2>&1)
ok "PI-39 AC1 — a repeated double date prefix is stripped entirely, not just the first" \
   '[[ "$(lastlog19)" == "- $TODAY testo tre" ]]'

(cd "$S19" && bash "$SCRIPT" log "2026-09-01" >/dev/null 2>&1)
ok "PI-39 AC1 — limit case: the message IS just a date, line still carries a single date" \
   '[[ "$(lastlog19)" == "- $TODAY" ]]'

(cd "$S19" && bash "$SCRIPT" log "PI-40 PR #80 approved — regressione del 2026-09-01" >/dev/null 2>&1)
ok "PI-39 AC2 — a date NOT at the start of the message is left untouched" \
   '[[ "$(lastlog19)" == "- $TODAY PI-40 PR #80 approved — regressione del 2026-09-01" ]]'
rm -rf "$S19"

# --- PI-39 AC3: no line in THIS project's own handoff/archive ever carries two consecutive ISO dates —
# an invariant on the real data, checked against BOTH files (rotation can move a line from one to the
# other), so the two doubled-date lines this task found and fixed on main cannot silently come back.
ok "PI-39 AC3 — no doubled-date log line in docs/SESSION_HANDOFF.md or its archive" \
   '! grep -qE "^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{4}-[0-9]{2}-[0-9]{2} " ../docs/SESSION_HANDOFF.md ../docs/SESSION_HANDOFF_ARCHIVE.md 2>/dev/null'

# --- PI-8 review finding 2 — LOGCAP must be the only place the 40 lives; nothing else repeats it by hand.
# Case A: the file created from scratch (no docs/SESSION_HANDOFF.md at all) must show the live LOGCAP in
# its "## Log" header, and the heredoc must actually have interpolated it (not leaked "$LOGCAP" as text).
# Trigger is `log` (a write), not `show`: PI-14 makes `show` a pure read that never creates the file.
S7=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test7.XXXXXX")
git init -q "$S7" >/dev/null
(cd "$S7" && bash "$SCRIPT" log "first log entry" >/dev/null 2>&1)
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
# (PI-40 moved the fallback out of `if not sep:` into `if not heading:`; the guard follows the assignment
# itself, which is the thing that must interpolate.)
ok "PI-8 F2 — the script's fallback header interpolates {logcap}, it does not hardcode 40" \
   '! grep -qE "^ *heading=f?\"## Log .*ultime 40 righe\)" "$SCRIPT"'
ok "PI-8 F2 — and it does spell out the interpolation, so the guard above is not vacuous" \
   'grep -qE "^ *heading=f\"## Log .*\{logcap\} righe\)" "$SCRIPT"'

# --- PI-9: a successful log/fact call says which file it wrote, so a missing 'cd' into the right
# worktree is visible in the same output instead of surfacing later as an unexplained change elsewhere.
S9=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test9.XXXXXX")
S9=$(cd "$S9" && pwd -P)   # resolve any symlink (e.g. macOS /tmp) so it matches git's resolved toplevel
git init -q "$S9" >/dev/null
F9="$S9/docs/SESSION_HANDOFF.md"

# PI-9 AC1 — a successful `log` names the path of the file it wrote, not a fixed string
outlog9=$(cd "$S9" && bash "$SCRIPT" log "an event")
ok "PI-9 AC1 — log output contains the written file's path" '[[ "$outlog9" == *"$F9"* ]]'

# PI-9 AC2 — a successful `fact` (first add, cap-reached add, and duplicate) names the path too
outfact9=$(cd "$S9" && bash "$SCRIPT" fact "a fact")
ok "PI-9 AC2 — fact-added output contains the written file's path" '[[ "$outfact9" == *"$F9"* ]]'
outdup9=$(cd "$S9" && bash "$SCRIPT" fact "a fact")
ok "PI-9 AC2 — duplicate-fact output contains the file's path too" '[[ "$outdup9" == *"$F9"* ]]'

# PI-9 AC3 — a caller that redirects the output still gets the same exit code and the file is still
# written; the addition is on the output only, never on the contract callers already depend on.
rcredirlog9=$(cd "$S9" && bash "$SCRIPT" log "redirected event" >/dev/null 2>&1; echo $?)
ok "PI-9 AC3 — log exit code unchanged when output is redirected" '[[ "$rcredirlog9" -eq 0 ]]'
ok "PI-9 AC3 — log still wrote the redirected event to the file" 'grep -qF "redirected event" "$F9"'
rcredirfact9=$(cd "$S9" && bash "$SCRIPT" fact "another fact" >/dev/null 2>&1; echo $?)
ok "PI-9 AC3 — fact exit code unchanged when output is redirected" '[[ "$rcredirfact9" -eq 0 ]]'
ok "PI-9 AC3 — fact still wrote the redirected fact to the file" 'grep -qF "another fact" "$F9"'
rm -rf "$S9"

# --- PI-14: read-only composer — facts/show/recent/grep merge frozen sources with docs/handoff/**
# fragments and NEVER write (ADR-2). See TAD HANDOFF_MEMORY_TECH_ANALYSIS.md §4.2-§4.3 for the fragment
# format and the ordering/dedup table these tests encode.

hash12(){ python3 -c "import hashlib,sys; print(hashlib.sha1(sys.argv[1].encode()).hexdigest()[:12])" "$1"; }

# AC1 — on a copy of this repo's own SESSION_HANDOFF.md, with no fragments, `facts` is byte-identical to
# the pre-PI-14 awk extraction.
S10=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test10.XXXXXX")
git init -q "$S10" >/dev/null
mkdir -p "$S10/docs"
cp "$PWD/../docs/SESSION_HANDOFF.md" "$S10/docs/SESSION_HANDOFF.md"
awkout=$(awk '/^## Fatti/{f=1;next} /^## /{f=0} f && /^- /' "$S10/docs/SESSION_HANDOFF.md")
factsout=$(cd "$S10" && bash "$SCRIPT" facts)
ok "AC1 — facts byte-identical to the pre-PI-14 awk, on this repo's real memory ($(printf '%s\n' "$awkout" | grep -c '^- ') lines both sides)" \
   '[[ "$factsout" == "$awkout" ]]'
rm -rf "$S10"

# AC2 — with SESSION_HANDOFF_ARCHIVE.md added, `recent --all` is the multiset of Log + archive lines.
S11=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test11.XXXXXX")
git init -q "$S11" >/dev/null
mkdir -p "$S11/docs"
cp "$PWD/../docs/SESSION_HANDOFF.md" "$S11/docs/SESSION_HANDOFF.md"
cp "$PWD/../docs/SESSION_HANDOFF_ARCHIVE.md" "$S11/docs/SESSION_HANDOFF_ARCHIVE.md"
mainlog=$(awk '/^## Log/{f=1;next} f && /^- /' "$S11/docs/SESSION_HANDOFF.md" | sort)
archlog=$(awk '/^## Log archiviato/{f=1;next} f && /^- /' "$S11/docs/SESSION_HANDOFF_ARCHIVE.md" | sort)
expectedcount=$(( $(printf '%s\n' "$mainlog" | grep -c '^- ') + $(printf '%s\n' "$archlog" | grep -c '^- ') ))
allout=$(cd "$S11" && bash "$SCRIPT" recent --all | sort)
actualcount=$(printf '%s\n' "$allout" | grep -c '^- ')
ok "AC2 — recent --all multiset equals Log + archive ($expectedcount lines expected, $actualcount got)" \
   '[[ "$actualcount" -eq "$expectedcount" ]] && [[ "$allout" == "$(printf "%s\n%s" "$mainlog" "$archlog" | sort)" ]]'
rm -rf "$S11"

# AC3 — hand-built fragments: ## Log, ## Fatti, ## Ritirati; two identical log lines in two fragments;
# an archive section sharing a fragment's name (declared copy, counted once).
S12=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test12.XXXXXX")
git init -q "$S12" >/dev/null
mkdir -p "$S12/docs/handoff/2026-09" "$S12/docs/handoff/archive"
cat > "$S12/docs/SESSION_HANDOFF.md" <<'EOF'
# Session handoff

## Fatti che non scadono
- fatto da ritirare
- fatto stabile
- fatto duplicato

## Log (più recente in alto, ultime 40 righe)
EOF
H12=$(hash12 "fatto da ritirare")
# Review round 1, finding 2(b): a retract must also hide a fact that lives in a FRAGMENT older than the
# retract, not only a frozen one — otherwise "hide only frozen facts" (M3) passes unnoticed.
HOLD=$(hash12 "fatto vecchio del frammento")
cat > "$S12/docs/handoff/2026-09/20260910T000000Z-oldfact-f6f6.md" <<'EOF'
## Fatti
- fatto vecchio del frammento
EOF
cat > "$S12/docs/handoff/2026-09/20260911T090000Z-branch-a-a1a1.md" <<'EOF'
## Log
- 2026-09-13 riga duplicata
EOF
cat > "$S12/docs/handoff/2026-09/20260912T090000Z-branch-b-b2b2.md" <<'EOF'
## Log
- 2026-09-13 riga duplicata
EOF
cat > "$S12/docs/handoff/2026-09/20260913T090000Z-retro-c3c3.md" <<EOF
## Ritirati
- ~ $H12
- ~ $HOLD
EOF
cat > "$S12/docs/handoff/2026-09/20260914T090000Z-copyname-d4d4.md" <<'EOF'
## Log
- 2026-09-14 riga del frammento con copia in archivio
EOF
# Review round 1, finding 2(c): the same fact text in two sources (frozen + fragment) must still count
# once — proves the text-dedup rule (§4.3), not just the retract path.
cat > "$S12/docs/handoff/2026-09/20260916T000000Z-dupfact-g7g7.md" <<'EOF'
## Fatti
- fatto duplicato
EOF
cat > "$S12/docs/handoff/archive/2026-09-20261001T000000Z-zzzz.md" <<'EOF'
### 20260914T090000Z-copyname-d4d4
## Log
- 2026-09-14 riga del frammento con copia in archivio

### 20260920T000000Z-orphan-o1o1
## Log
- 2026-09-20 riga solo in archivio, mai stata un frammento vivo
EOF
recent12=$(cd "$S12" && bash "$SCRIPT" recent --all)
ok "AC3 — the duplicated log line appears twice (two events, never deduped)" \
   '[[ "$(printf "%s\n" "$recent12" | grep -c "^- 2026-09-13 riga duplicata$")" -eq 2 ]]'
ok "AC3 — the declared copy (archive section == live fragment name) counts once" \
   '[[ "$(printf "%s\n" "$recent12" | grep -c "riga del frammento con copia")" -eq 1 ]]'
# Review round 1, finding 2(a): an archive section with NO live fragment of the same name must still be
# read (not silently skipped, M2) — its line has nowhere else to come from.
ok "AC3 — an archive section with no live fragment (orphan) is still read" \
   '[[ "$(printf "%s\n" "$recent12" | grep -c "riga solo in archivio")" -eq 1 ]]'
facts12=$(cd "$S12" && bash "$SCRIPT" facts)
ok "AC3 — the retracted fact (frozen source) does not appear" '! grep -qF "fatto da ritirare" <<<"$facts12"'
ok "AC3 — the retracted fact (fragment source, older than the retract) does not appear" \
   '! grep -qF "fatto vecchio del frammento" <<<"$facts12"'
ok "AC3 — the untouched fact still appears" 'grep -qF "fatto stabile" <<<"$facts12"'
ok "AC3 — the same fact in two sources counts once" \
   '[[ "$(printf "%s\n" "$facts12" | grep -c "^- fatto duplicato$")" -eq 1 ]]'
# mutation: a fact rewritten AFTER the retract (newer fragment, same text) is visible again
cat > "$S12/docs/handoff/2026-09/20260915T090000Z-fix-e5e5.md" <<'EOF'
## Fatti
- fatto da ritirare
EOF
facts12b=$(cd "$S12" && bash "$SCRIPT" facts)
ok "AC3 — the same fact rewritten after the retract is visible again" 'grep -qF "fatto da ritirare" <<<"$facts12b"'
rm -rf "$S12"

# AC4 — facts/show/recent 5/grep X never write: git status --porcelain identical before and after, with
# and without the frozen file, no file created. Also from a project root with no docs/ at all.
for variant in bare withold; do
  S13=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test13-$variant.XXXXXX")
  S13=$(cd "$S13" && pwd -P)
  git init -q "$S13" >/dev/null
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  if [[ "$variant" == withold ]]; then
    mkdir -p "$S13/docs"
    cp "$PWD/../docs/SESSION_HANDOFF.md" "$S13/docs/SESSION_HANDOFF.md"
    (cd "$S13" && git add -A && git commit -q -m init) >/dev/null
  fi
  before13=$(cd "$S13" && git status --porcelain)
  (cd "$S13" && bash "$SCRIPT" facts >/dev/null 2>&1
                bash "$SCRIPT" show >/dev/null 2>&1
                bash "$SCRIPT" recent 5 >/dev/null 2>&1
                bash "$SCRIPT" grep X >/dev/null 2>&1)
  after13=$(cd "$S13" && git status --porcelain)
  ok "AC4 [$variant] — git status --porcelain identical before/after four reads" '[[ "$before13" == "$after13" ]]'
  ok "AC4 [$variant] — no docs/handoff created by a read" '[[ ! -d "$S13/docs/handoff" ]]'
  rm -rf "$S13"
done

# Review round 1, finding 3: the "withold" case above copies THIS repo's own file, which already says
# "max 100 righe" — a reintroduced normalisation on read is a no-op rewrite there and git status stays
# clean either way (M6 passed unnoticed). Commit a STALE "max 30 righe" comment plus a fragment and an
# archive section, so a reintroduced sed on any of the four reads produces a real, visible diff.
S13b=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test13b.XXXXXX")
S13b=$(cd "$S13b" && pwd -P)
git init -q "$S13b" >/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$S13b/docs/handoff/2026-09" "$S13b/docs/handoff/archive"
cat > "$S13b/docs/SESSION_HANDOFF.md" <<'EOF'
# Session handoff

## Fatti che non scadono
<!-- max 30 righe: invarianti, gotcha, decisioni e perché. Chi aggiunge una riga toglie quella che non vale più. -->
- an existing fact

## Log (più recente in alto, ultime 40 righe)
- 2026-09-01 an existing log line
EOF
cat > "$S13b/docs/handoff/2026-09/20260902T090000Z-x-x1x1.md" <<'EOF'
## Log
- 2026-09-02 a fragment line
EOF
cat > "$S13b/docs/handoff/archive/2026-09-20261001T000000Z-a2a2.md" <<'EOF'
### 20260902T090000Z-x-x1x1
## Log
- 2026-09-02 a fragment line
EOF
(cd "$S13b" && git add -A && git commit -q -m init) >/dev/null
before13b=$(cd "$S13b" && git status --porcelain)
(cd "$S13b" && bash "$SCRIPT" facts >/dev/null 2>&1
               bash "$SCRIPT" show >/dev/null 2>&1
               bash "$SCRIPT" recent 5 >/dev/null 2>&1
               bash "$SCRIPT" grep X >/dev/null 2>&1)
after13b=$(cd "$S13b" && git status --porcelain)
ok "AC4 [stale-comment+fragments] — git status --porcelain identical before/after" '[[ "$before13b" == "$after13b" ]]'
ok "AC4 [stale-comment+fragments] — the stale comment is still 'max 30 righe' after four reads" \
   'grep -qF "max 30 righe" "$S13b/docs/SESSION_HANDOFF.md"'
rm -rf "$S13b"

# AC4 — outside a repo: exit 1 (not a git repository), nothing created, no traceback.
S13c=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test13c.XXXXXX")
outnr=$(cd "$S13c" && bash "$SCRIPT" facts 2>&1); rcnr=$?
ok "AC4 [outside a repo] — exit 1" '[[ "$rcnr" -eq 1 ]]'
ok "AC4 [outside a repo] — no file created" '[[ -z "$(ls -A "$S13c")" ]]'
rm -rf "$S13c"

# AC5 — a frozen row dated 2026-09-10 and fragments dated 2026-09-11 and 2026-09-12: recent --all orders
# 12, 11, 10, and at equal day fragments come before frozen rows.
S14=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test14.XXXXXX")
git init -q "$S14" >/dev/null
mkdir -p "$S14/docs/handoff/2026-09"
cat > "$S14/docs/SESSION_HANDOFF.md" <<'EOF'
# Session handoff

## Fatti che non scadono

## Log (più recente in alto, ultime 40 righe)
- 2026-09-10 evento congelato
EOF
cat > "$S14/docs/handoff/2026-09/20260911T090000Z-branch-a-a1a1.md" <<'EOF'
## Log
- 2026-09-11 evento frammento
EOF
cat > "$S14/docs/handoff/2026-09/20260912T090000Z-branch-b-b2b2.md" <<'EOF'
## Log
- 2026-09-12 evento frammento
EOF
order14=$(cd "$S14" && bash "$SCRIPT" recent --all)
ok "AC5 — order is 12, 11, 10" \
   '[[ "$order14" == "$(printf "%s\n%s\n%s" "- 2026-09-12 evento frammento" "- 2026-09-11 evento frammento" "- 2026-09-10 evento congelato")" ]]'
rm -rf "$S14"

# Review round 1, finding 1: AC5's fixture above has every entry on a distinct day, so the tie-break rule
# for SAME-day entries (§4.3: fragments by timestamp descending, then main log top-down, then archive
# bottom-up) is never exercised. All same day here: main log (1 line), archive (2 lines, oldest on top of
# the file), two fragments at different timestamps.
S15=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test15.XXXXXX")
git init -q "$S15" >/dev/null
mkdir -p "$S15/docs/handoff/2026-09"
cat > "$S15/docs/SESSION_HANDOFF.md" <<'EOF'
# Session handoff

## Fatti che non scadono

## Log (più recente in alto, ultime 40 righe)
- 2026-09-13 riga principale
EOF
cat > "$S15/docs/SESSION_HANDOFF_ARCHIVE.md" <<'EOF'
# Session handoff — archive

## Log archiviato
- 2026-09-13 riga archivio vecchia
- 2026-09-13 riga archivio nuova
EOF
cat > "$S15/docs/handoff/2026-09/20260913T090000Z-branch-a-a1a1.md" <<'EOF'
## Log
- 2026-09-13 riga frammento presto
EOF
cat > "$S15/docs/handoff/2026-09/20260913T100000Z-branch-b-b2b2.md" <<'EOF'
## Log
- 2026-09-13 riga frammento tardi
EOF
order15=$(cd "$S15" && bash "$SCRIPT" recent --all)
expected15=$(printf '%s\n%s\n%s\n%s\n%s' \
  "- 2026-09-13 riga frammento tardi" "- 2026-09-13 riga frammento presto" \
  "- 2026-09-13 riga principale" \
  "- 2026-09-13 riga archivio nuova" "- 2026-09-13 riga archivio vecchia")
ok "AC5 — same-day tie-break: fragments (newest ts first), then main log, then archive bottom-up" \
   '[[ "$order15" == "$expected15" ]]'
rm -rf "$S15"

# Review round 1, finding 4: bin/handoff.sh:53 used str.splitlines(), which breaks a line on far more
# characters than awk's RS="\n" (CRLF, a lone CR, VT, FF, FS, GS, RS, NEL, LS, PS) — the tail after any of
# them silently vanished. Every one of the 10 must survive as DATA, byte for byte, matching the awk oracle.
for sepname in CRLF CR VT FF FS GS RS NEL LS PS; do
  S16=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test16-$sepname.XXXXXX")
  git init -q "$S16" >/dev/null
  mkdir -p "$S16/docs"
  python3 - "$S16/docs/SESSION_HANDOFF.md" "$sepname" <<'PY'
import sys
path, name = sys.argv[1], sys.argv[2]
SEP = {
    "CRLF": "\r\n", "CR": "\r", "VT": "\x0b", "FF": "\x0c",
    "FS": "\x1c", "GS": "\x1d", "RS": "\x1e",
    "NEL": "\x85", "LS": " ", "PS": " ",
}[name]
content = ("# Session handoff\n\n"
           "## Fatti che non scadono\n"
           f"- fact a{SEP}b\n\n"
           "## Log (più recente in alto, ultime 40 righe)\n"
           f"- 2026-09-12 log a{SEP}b\n")
with open(path, "w", encoding="utf-8", newline="") as f:
    f.write(content)
PY
  awkfacts=$(awk '/^## Fatti/{f=1;next} /^## /{f=0} f && /^- /' "$S16/docs/SESSION_HANDOFF.md")
  ourfacts=$(cd "$S16" && bash "$SCRIPT" facts)
  ok "Finding4 [$sepname] — facts byte-identical to awk with the separator embedded as data" \
     '[[ "$ourfacts" == "$awkfacts" ]]'
  awklog=$(awk '/^## Log/{f=1;next} f && /^- /' "$S16/docs/SESSION_HANDOFF.md")
  ourlog=$(cd "$S16" && bash "$SCRIPT" recent --all)
  ok "Finding4 [$sepname] — recent --all byte-identical to awk with the separator embedded as data" \
     '[[ "$ourlog" == "$awklog" ]]'
  rm -rf "$S16"
done

# Contract §5.1 / round 1 review: a malformed argument gives exit 2 with a usage line on stderr, never a
# Python traceback (exit 1) and never a silent wrong answer (recent -1 used to exit 0 and drop a line via
# a negative slice).
S17=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test17.XXXXXX")
git init -q "$S17" >/dev/null

out17a=$(cd "$S17" && bash "$SCRIPT" recent abc 2>&1); rc17a=$?
ok "exit 2 on 'recent abc' (non-numeric N)" '[[ "$rc17a" -eq 2 ]]'
ok "usage line on 'recent abc'" '[[ "$out17a" == usage:* ]]'

out17b=$(cd "$S17" && bash "$SCRIPT" recent --al 2>&1); rc17b=$?
ok "exit 2 on 'recent --al' (typo of --all)" '[[ "$rc17b" -eq 2 ]]'
ok "usage line on 'recent --al'" '[[ "$out17b" == usage:* ]]'

out17c=$(cd "$S17" && bash "$SCRIPT" grep '[' 2>&1); rc17c=$?
ok "exit 2 on invalid regex \"grep [\"" '[[ "$rc17c" -eq 2 ]]'
ok "usage line on invalid regex" '[[ "$out17c" == usage:* ]]'

out17d=$(cd "$S17" && bash "$SCRIPT" recent -1 2>&1); rc17d=$?
ok "exit 2 on 'recent -1' (negative N, not a silent negative slice)" '[[ "$rc17d" -eq 2 ]]'
ok "usage line on 'recent -1'" '[[ "$out17d" == usage:* ]]'

out17e=$(cd "$S17" && bash "$SCRIPT" grep 2>&1); rc17e=$?
ok "exit 2 on 'grep' with no argument" '[[ "$rc17e" -eq 2 ]]'
ok "usage line on 'grep' with no argument" '[[ "$out17e" == usage:* ]]'
rm -rf "$S17"

# Review round 3: the finding above listed five FORMS of malformed argv, not the class — extra arguments
# ("facts X", "show X", "recent 3 X", "grep A B") were being silently ignored, exit 0. Fix: one grammar
# declaration per read subcommand (SPEC in bin/handoff.sh — min args, max args, an optional per-arg type
# check, and a known-bad example value for that check), read via the internal `__spec` command, that
# BOTH drives the real validation AND generates these tests — so nothing here repeats a number by hand,
# and a new subcommand is unusable (validate() rejects it) unless it gets a SPEC entry too.
S18=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test18.XXXXXX")
git init -q "$S18" >/dev/null
speclines=$(cd "$S18" && bash "$SCRIPT" __spec)
ok "argspec — __spec lists the four read subcommands" \
   '[[ "$(printf "%s\n" "$speclines" | grep -c .)" -eq 4 ]]'
while read -r specname lo hi bad; do
  [[ -z "$specname" ]] && continue

  # one argument more than the declared max, regardless of its content — the class this round closes
  extra=()
  for ((i = 0; i <= hi; i++)); do extra+=("X"); done
  outmany=$(cd "$S18" && bash "$SCRIPT" "$specname" "${extra[@]}" 2>&1); rcmany=$?
  ok "argspec[$specname] — $((hi + 1)) args (declared max $hi) → exit 2" '[[ "$rcmany" -eq 2 ]]'
  ok "argspec[$specname] — usage line on too many args" '[[ "$outmany" == usage:* ]]'

  # one argument fewer than the declared min, only for subcommands that require at least one
  if [[ "$lo" -gt 0 ]]; then
    short=()
    for ((i = 0; i < lo - 1; i++)); do short+=("X"); done
    # bash 3.2 (macOS default) treats "${short[@]}" on a still-empty array as an unbound variable under
    # `set -u` — guard the expansion instead of relying on it being silently empty.
    if [[ "${#short[@]}" -gt 0 ]]; then
      outfew=$(cd "$S18" && bash "$SCRIPT" "$specname" "${short[@]}" 2>&1); rcfew=$?
    else
      outfew=$(cd "$S18" && bash "$SCRIPT" "$specname" 2>&1); rcfew=$?
    fi
    ok "argspec[$specname] — $((lo - 1)) args (declared min $lo) → exit 2" '[[ "$rcfew" -eq 2 ]]'
    ok "argspec[$specname] — usage line on too few args" '[[ "$outfew" == usage:* ]]'
  fi

  # the declaration's own known-bad value, only for subcommands with a per-arg type check
  if [[ "$bad" != "-" ]]; then
    outbad=$(cd "$S18" && bash "$SCRIPT" "$specname" "$bad" 2>&1); rcbad=$?
    ok "argspec[$specname] — declared bad value '$bad' → exit 2" '[[ "$rcbad" -eq 2 ]]'
    ok "argspec[$specname] — usage line on the declared bad value" '[[ "$outbad" == usage:* ]]'
  fi
done <<<"$speclines"
rm -rf "$S18"

# --- PI-40: the writer must find its OWN headings, never a marker quoted inside free text.
# Damage to prevent, stated as damage: no section heading and no fact may be deleted, or moved to
# another section, by the act of writing a line. (The cause was `s.partition("## Log")` — a substring
# match — so the first fact quoting the marker took the heading's place: the real heading was dropped,
# it does not start with "- ", and every fact below the quote was rewritten into the log, then rotated.)
# The class, not the one spelling observed in the wild: the marker backticked inside a command, inline
# mid-sentence, first thing in the fact's text, spelled with the heading's own parenthetical, twice in
# one line, and last thing on the line — plus, for `fact`, the mirror case of a log line quoting the
# facts heading. Oracles are the anchored awk extractions this suite already uses, never the script.
factlines40(){ awk '/^## Fatti/{f=1;next} /^## /{f=0} f && /^- /' "$1"; }
loglines40(){ awk '/^## Log/{f=1;next} f && /^- /' "$1"; }
countlines40(){ printf '%s' "$1" | grep -c '^- '; }
headcount40(){ grep -c '^## Log' "$1"; }
structure40(){ awk '{print} /^## Log/{exit}' "$1"; }   # the file down to (and including) the Log heading
mkpoisoned40(){   # $1 = repo dir, $2 = the fact text that quotes a marker, $3.. = log lines, newest first
  local d="$1" poison="$2"; shift 2
  [[ "$#" -eq 0 ]] && set -- "2026-01-01 una riga di log che c'era già"
  mkdir -p "$d/docs"
  { echo "# Session handoff"
    echo
    echo "## Fatti che non scadono"
    echo "<!-- max 100 righe: invarianti, gotcha, decisioni e perché. Chi aggiunge una riga toglie quella che non vale più. -->"
    echo "- primo fatto, sopra la citazione"
    printf -- '- %s\n' "$poison"
    echo "- ultimo fatto, SOTTO la citazione"
    echo
    echo "## Log (più recente in alto, ultime 40 righe)"
    printf -- '- %s\n' "$@"
  } > "$d/docs/SESSION_HANDOFF.md"
}
POISONS40=(
  $'regola: controlla con `awk \'/^## Log/{f=1;next} /^## /{f=0}\'` prima di scrivere'
  'la sezione ## Log sta in fondo al file'
  '## Log è il marcatore che ogni lettore cerca'
  'il file finisce con ## Log (più recente in alto, ultime 40 righe)'
  'due marcatori in una riga: ## Fatti che non scadono e ## Log'
  'vedi ## Log'
)

# AC1 — one disposable repo per member of the class: after a `log`, the heading is still there exactly
# once, the new line is under it, and no fact moved section.
for idx in $(seq 0 $((${#POISONS40[@]} - 1))); do
  poison40="${POISONS40[$idx]}"
  S20=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test20-$idx.XXXXXX")
  git init -q "$S20" >/dev/null
  mkpoisoned40 "$S20" "$poison40"
  F20="$S20/docs/SESSION_HANDOFF.md"
  beforefacts20=$(factlines40 "$F20")
  (cd "$S20" && bash "$SCRIPT" log "PI-40 nuova riga di log" >/dev/null 2>&1)
  afterfacts20=$(factlines40 "$F20")
  newest20=$(loglines40 "$F20" | head -1)
  ok "PI-40 AC1 [$idx] — the real '## Log' heading is still present exactly once" \
     '[[ "$(headcount40 "$F20")" -eq 1 ]]'
  ok "PI-40 AC1 [$idx] — every fact is byte-identical, the one quoting the marker included" \
     '[[ "$afterfacts20" == "$beforefacts20" ]]'
  ok "PI-40 AC1 [$idx] — the fact standing AFTER the quote is still a fact" \
     'grep -qF "ultimo fatto, SOTTO la citazione" <<<"$afterfacts20"'
  ok "PI-40 AC1 [$idx] — the new line is the top line of the Log section" \
     '[[ "$newest20" == *"PI-40 nuova riga di log" ]]'
  ok "PI-40 AC1 [$idx] — the pre-existing log line is still in the Log section (2 log lines)" \
     '[[ "$(countlines40 "$(loglines40 "$F20")")" -eq 2 ]]'
  ok "PI-40 AC1 [$idx] — nothing was rotated: no archive file exists" \
     '[[ ! -f "$S20/docs/SESSION_HANDOFF_ARCHIVE.md" ]]'
  rm -rf "$S20"
done

# AC2 — N writes in a row on the same poisoned file: structure byte-stable, facts never shrink, nothing
# rotates. Checked after EVERY write, not only at the end: the old defect repeated on each run.
S21=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test21.XXXXXX")
git init -q "$S21" >/dev/null
mkpoisoned40 "$S21" "${POISONS40[0]}"
F21="$S21/docs/SESSION_HANDOFF.md"
minfacts21=$(countlines40 "$(factlines40 "$F21")"); headok21=1; factok21=1
for n in 1 2 3 4 5; do
  (cd "$S21" && bash "$SCRIPT" log "evento numero $n" >/dev/null 2>&1)
  [[ "$(headcount40 "$F21")" -eq 1 ]] || headok21=0
  [[ "$(countlines40 "$(factlines40 "$F21")")" -ge "$minfacts21" ]] || factok21=0
  [[ "$n" -eq 4 ]] && struct21=$(structure40 "$F21")
done
ok "PI-40 AC2 — the heading count stays 1 after each of 5 consecutive writes" '[[ "$headok21" -eq 1 ]]'
ok "PI-40 AC2 — the fact count never decreases across the 5 writes" '[[ "$factok21" -eq 1 ]]'
ok "PI-40 AC2 — the file down to the Log heading is byte-identical between two writes" \
   '[[ "$(structure40 "$F21")" == "$struct21" ]]'
ok "PI-40 AC2 — no fact ever reached the archive (no archive file at all)" \
   '[[ ! -f "$S21/docs/SESSION_HANDOFF_ARCHIVE.md" ]]'
rm -rf "$S21"

# AC3 — a file with NO Log heading at all: the section is created once, at the end, and the dated line
# that was already there (a fact that reads like a log line) is not re-parented into it.
S22=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test22.XXXXXX")
git init -q "$S22" >/dev/null
mkdir -p "$S22/docs"
F22="$S22/docs/SESSION_HANDOFF.md"
cat > "$F22" <<'EOF'
# Session handoff

## Fatti che non scadono
- un fatto che cita ## Log dentro il proprio testo
- 2026-01-01 un fatto che sembra una riga di log ma è un fatto
EOF
beforefacts22=$(factlines40 "$F22")
(cd "$S22" && bash "$SCRIPT" log "prima riga di log in assoluto" >/dev/null 2>&1)
lastheading22=$(grep '^## ' "$F22" | tail -1)
ok "PI-40 AC3 — a Log heading is created, exactly once" '[[ "$(headcount40 "$F22")" -eq 1 ]]'
ok "PI-40 AC3 — it is created at the END (it is the last heading of the file)" \
   '[[ "$lastheading22" == "## Log"* ]]'
ok "PI-40 AC3 — both pre-existing facts are untouched, the dated one included" \
   '[[ "$(factlines40 "$F22")" == "$beforefacts22" ]]'
ok "PI-40 AC3 — the Log section holds exactly one line: the new one, nothing re-parented" \
   '[[ "$(countlines40 "$(loglines40 "$F22")")" -eq 1 ]] && [[ "$(loglines40 "$F22")" == *"prima riga di log in assoluto" ]]'
rm -rf "$S22"

# AC4 — rotation under AC1's conditions: only genuine log lines rotate, PI-8's invariant holds (nothing
# lost, oldest at the top). 45 log lines + a poisoned facts section: one write evicts 6 at once.
S23=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test23.XXXXXX")
git init -q "$S23" >/dev/null
entries23=()
for i in $(seq 45 -1 1); do entries23+=("2026-01-01 entry $i"); done
mkpoisoned40 "$S23" "${POISONS40[3]}" "${entries23[@]}"
F23="$S23/docs/SESSION_HANDOFF.md"; ARCHIVE23="$S23/docs/SESSION_HANDOFF_ARCHIVE.md"
beforefacts23=$(factlines40 "$F23")
(cd "$S23" && bash "$SCRIPT" log "entry 46" >/dev/null 2>&1)
archlines23=$(awk '/^- /' "$ARCHIVE23")
ok "PI-40 AC4 — exactly 6 lines rotated (45 + 1 - 40)" '[[ "$(countlines40 "$archlines23")" -eq 6 ]]'
ok "PI-40 AC4 — every archived line is a genuine log line ('entry N'), none is anything else" \
   '[[ "$(printf "%s\n" "$archlines23" | grep -c "^- 2026-01-01 entry [0-9]*$")" -eq 6 ]]'
ok "PI-40 AC4 — no fact reached the archive" \
   '! grep -qF "ultimo fatto, SOTTO la citazione" "$ARCHIVE23" && ! grep -qF "il file finisce con" "$ARCHIVE23"'
ok "PI-40 AC4 — sibling of the absence above: those facts ARE still in the handoff file" \
   'grep -qF "ultimo fatto, SOTTO la citazione" "$F23" && grep -qF "il file finisce con" "$F23"'
ok "PI-40 AC4 — order oldest-at-top survives (entry 1 first, entry 6 last)" \
   '[[ "$(printf "%s\n" "$archlines23" | head -1)" == *"entry 1" ]] && [[ "$(printf "%s\n" "$archlines23" | tail -1)" == *"entry 6" ]]'
ok "PI-40 AC4 — the facts section is byte-identical after the rotating write" \
   '[[ "$(factlines40 "$F23")" == "$beforefacts23" ]]'
rm -rf "$S23"

# AC5 — one definition of where each section starts, used by the composer (facts/recent) and by both
# writers. Same poisoned file, read by the composer and written by `fact`.
S24=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test24.XXXXXX")
git init -q "$S24" >/dev/null
mkpoisoned40 "$S24" "${POISONS40[0]}"
F24="$S24/docs/SESSION_HANDOFF.md"
awkfacts24=$(factlines40 "$F24"); awklog24=$(loglines40 "$F24")
composed24=$(cd "$S24" && bash "$SCRIPT" facts)
recent24=$(cd "$S24" && bash "$SCRIPT" recent --all)
ok "PI-40 AC5 — the composer's facts equal the anchored awk extraction, quote included" \
   '[[ "$composed24" == "$awkfacts24" ]]'
ok "PI-40 AC5 — the composer's log equals the anchored awk extraction (the quote is not a log line)" \
   '[[ "$recent24" == "$awklog24" ]]'
(cd "$S24" && bash "$SCRIPT" fact "un fatto aggiunto dopo la citazione" >/dev/null 2>&1)
ok "PI-40 AC5 — after a fact write, the facts are the old ones plus the new one, in order" \
   '[[ "$(factlines40 "$F24")" == "$(printf "%s\n%s" "$awkfacts24" "- un fatto aggiunto dopo la citazione")" ]]'
ok "PI-40 AC5 — after a fact write, the Log section is byte-identical" '[[ "$(loglines40 "$F24")" == "$awklog24" ]]'
ok "PI-40 AC5 — after a fact write, each heading still appears exactly once" \
   '[[ "$(headcount40 "$F24")" -eq 1 ]] && [[ "$(grep -c "^## Fatti che non scadono" "$F24")" -eq 1 ]]'
rm -rf "$S24"

# AC5, mirror case: a LOG line quoting the FACTS heading, in a file that has no facts heading of its own
# — the quote must not become the place where the new fact is written, or the fact lands inside the Log
# section and every reader files it as a log line.
S25=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test25.XXXXXX")
git init -q "$S25" >/dev/null
mkdir -p "$S25/docs"
F25="$S25/docs/SESSION_HANDOFF.md"
cat > "$F25" <<'EOF'
# Session handoff

## Log (più recente in alto, ultime 40 righe)
- 2026-01-01 i fatti stanno sotto ## Fatti che non scadono
- 2026-01-01 una seconda riga di log
EOF
awklog25=$(loglines40 "$F25")
(cd "$S25" && bash "$SCRIPT" fact "il fatto nuovo" >/dev/null 2>&1)
facts25=$(cd "$S25" && bash "$SCRIPT" facts)
recent25=$(cd "$S25" && bash "$SCRIPT" recent --all)
ok "PI-40 AC5 mirror — the new fact is readable as a fact (the heading was created for it)" \
   '[[ "$facts25" == "- il fatto nuovo" ]]'
ok "PI-40 AC5 mirror — the two log lines are still log lines, byte-identical, and the fact is not one" \
   '[[ "$recent25" == "$awklog25" ]]'
rm -rf "$S25"

# AC1/AC2, writer side: the 10 characters str.splitlines() breaks on but awk (RS="\n") does not. A fact
# or a log line may legitimately hold any of them as DATA; reading the file with universal-newline
# translation on and writing it back rewrote them, which cut the tail off the line that held one — the
# same damage as the heading bug, reached by another road. Finding 4 fixed this for the reader only.
for sepname in CRLF CR VT FF FS GS RS NEL LS PS; do
  S26=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test26-$sepname.XXXXXX")
  git init -q "$S26" >/dev/null
  mkdir -p "$S26/docs"
  python3 - "$S26/docs/SESSION_HANDOFF.md" "$sepname" <<'PY'
import sys
path, name = sys.argv[1], sys.argv[2]
SEP = {
    "CRLF": "\r\n", "CR": "\r", "VT": "\x0b", "FF": "\x0c",
    "FS": "\x1c", "GS": "\x1d", "RS": "\x1e",
    "NEL": "\x85", "LS": " ", "PS": " ",
}[name]
content = ("# Session handoff\n\n"
           "## Fatti che non scadono\n"
           f"- fact a{SEP}b\n\n"
           "## Log (più recente in alto, ultime 40 righe)\n"
           f"- 2026-09-12 log a{SEP}b\n")
with open(path, "w", encoding="utf-8", newline="") as f:
    f.write(content)
PY
  F26="$S26/docs/SESSION_HANDOFF.md"
  beforefacts26=$(factlines40 "$F26"); beforelog26=$(loglines40 "$F26")
  (cd "$S26" && bash "$SCRIPT" log "una riga nuova" >/dev/null 2>&1)
  ok "PI-40 writer [$sepname] — the fact holding the separator as data survives a log write, byte for byte" \
     '[[ "$(factlines40 "$F26")" == "$beforefacts26" ]]'
  ok "PI-40 writer [$sepname] — the pre-existing log line holding it survives too" \
     '[[ "$(loglines40 "$F26" | tail -1)" == "$beforelog26" ]]'
  rm -rf "$S26"
done

# PI-40 — the cap-comment normalisation is a write over free text too: anchored to the start of the
# line, so a fact quoting "max 30 righe:" is data and is not rewritten by an unrelated log call.
S27=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test27.XXXXXX")
git init -q "$S27" >/dev/null
mkdir -p "$S27/docs"
F27="$S27/docs/SESSION_HANDOFF.md"
cat > "$F27" <<'EOF'
# Session handoff

## Fatti che non scadono
<!-- max 30 righe: invarianti, gotcha, decisioni e perché. Chi aggiunge una riga toglie quella che non vale più. -->
- il commento diceva "max 30 righe:" prima che il cap salisse

## Log (più recente in alto, ultime 40 righe)
EOF
(cd "$S27" && bash "$SCRIPT" log "un evento qualsiasi" >/dev/null 2>&1)
ok "PI-40 — the fact quoting the cap comment is left exactly as written" \
   'grep -qF -- "- il commento diceva \"max 30 righe:\" prima che il cap salisse" "$F27"'
ok "PI-40 — sibling: the real comment line IS normalised by the same write" \
   'grep -qF "<!-- max $CAP righe:" "$F27"'
rm -rf "$S27"

# PI-40 structural — one home for the term: no substring split on a section marker is left anywhere in
# the script, there is exactly one definition of where a section begins, and every python program in the
# file is fed through the shared helpers (py_run) instead of a bare `python3 -`.
ok "PI-40 AC5 — no marker is located by substring partition any more (code lines, not the comments about it)" \
   '! grep -qE "^[^#]*\.partition\(\"#" "$SCRIPT"'
ok "PI-40 AC5 — sibling: that same pattern does match the pre-PI-40 form, so the guard is not vacuous" \
   'printf "%s\n" "head,sep,tail=s.partition(\"## Log\")" | grep -qE "^[^#]*\.partition\(\"#"'
ok "PI-40 AC5 — exactly one definition of where a section begins" \
   '[[ "$(grep -c "^def split_section(" "$SCRIPT")" -eq 1 ]]'
ok "PI-40 AC5 — no python program bypasses the shared helpers" \
   '[[ "$(grep -cE "^ *python3 - " "$SCRIPT")" -eq 0 ]]'
ok "PI-40 AC5 — sibling: that same pattern does match a bare invocation, so the guard is not vacuous" \
   'printf "%s\n" "    python3 - \"\$F\" <<PY" | grep -qE "^ *python3 - "'

[[ "$fail" -eq 0 ]] && echo "handoff.test.sh: all ok" || echo "handoff.test.sh: FAILURES"
exit "$fail"
