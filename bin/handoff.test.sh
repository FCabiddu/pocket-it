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
ok "PI-8 F2 — the script's fallback header interpolates {logcap}, it does not hardcode 40" \
   '! grep -nE "if not sep:.*ultime 40 righe\)" "$SCRIPT"'
ok "PI-8 F2 — and it does spell out the interpolation, so the guard above is not vacuous" \
   'grep -nE "if not sep:.*\{logcap\} righe\)" "$SCRIPT" >/dev/null'

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

## Log (più recente in alto, ultime 40 righe)
EOF
H12=$(hash12 "fatto da ritirare")
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
EOF
cat > "$S12/docs/handoff/2026-09/20260914T090000Z-copyname-d4d4.md" <<'EOF'
## Log
- 2026-09-14 riga del frammento con copia in archivio
EOF
cat > "$S12/docs/handoff/archive/2026-09-20261001T000000Z-zzzz.md" <<'EOF'
### 20260914T090000Z-copyname-d4d4
## Log
- 2026-09-14 riga del frammento con copia in archivio
EOF
recent12=$(cd "$S12" && bash "$SCRIPT" recent --all)
ok "AC3 — the duplicated log line appears twice (two events, never deduped)" \
   '[[ "$(printf "%s\n" "$recent12" | grep -c "^- 2026-09-13 riga duplicata$")" -eq 2 ]]'
ok "AC3 — the declared copy (archive section == live fragment name) counts once" \
   '[[ "$(printf "%s\n" "$recent12" | grep -c "riga del frammento con copia")" -eq 1 ]]'
facts12=$(cd "$S12" && bash "$SCRIPT" facts)
ok "AC3 — the retracted fact does not appear" '! grep -qF "fatto da ritirare" <<<"$facts12"'
ok "AC3 — the untouched fact still appears" 'grep -qF "fatto stabile" <<<"$facts12"'
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

[[ "$fail" -eq 0 ]] && echo "handoff.test.sh: all ok" || echo "handoff.test.sh: FAILURES"
exit "$fail"
