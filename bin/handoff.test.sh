#!/usr/bin/env bash
# Self-test for handoff.sh.
#
# PI-16 turned every write into the creation of ONE NEW FILE under docs/handoff/{AAAA-MM}/ and froze
# docs/SESSION_HANDOFF.md and its archive, so the whole suite is stated on that write path:
#   AC1 non-contention — four branches write memory, everything merges with zero conflicts, and the
#       mutation (one shared file per branch) really does conflict, so the scenario can fail;
#   AC2 nothing written twice — 50 concurrent `log` calls, 50 distinct files, no existing file touched
#       (content AND mtime);
#   AC3 freezing — the old files are never written, never created;
#   AC4 retract — hides a fact living in a fragment and in a frozen source without touching either;
#   AC5 the facts cap counts VISIBLE facts and points at `retract`;
#   AC6 on a copy of this repo's real memory;
#   AC7 `where` — prints the directory, needs no repo, writes nothing (with the pre-PI-16 behaviour as
#       the mutation, so the check is not vacuous);
#   AC8 the instructions agents read at startup no longer describe the frozen file as the write target.
# Plus non-rotation (PI-8's rotation tests, restated: nothing moves, LOGCAP is only a display window),
# PI-39 (a caller's leading date is never doubled), PI-9 (the confirmation names the file it wrote),
# PI-14 (the read-only composer, its ordering/dedup table and its argv grammar) and PI-40 (no write, of
# any shape, can add or destroy a heading) — each re-derived from the new write path, never re-run
# unchanged: where the old assertion said "the one file still has one heading", the new one says
# "every pre-existing file is byte-identical and the one new file holds exactly one heading and one
# record", which is what makes the damage impossible now.
set -uo pipefail
cd "$(dirname "$0")"
SCRIPT="$PWD/handoff.sh"
REPO=$(cd .. && pwd -P)
CAP=100
LOGCAP=40
fail=0
ok(){ if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
TODAY=$(date +%Y-%m-%d)
MONTH=$(date -u +%Y-%m)
# A clock read once at start-up and compared against a line written minutes later is a test that goes red
# at a boundary it never chose. handoff.sh dates each line with the LOCAL date at the moment of the write,
# so a suite that runs across local midnight writes some lines before it and some after, and one $TODAY
# cannot be right for both — measured on this suite: a run crossing 00:00 went red on the one line written
# after it, with nothing wrong in the code under test. The two helpers below close the whole class rather
# than the assertion that happened to catch it: `dated` accepts either date this run can legitimately have
# written, and `undate` normalises a leading date to $TODAY on BOTH sides of a multiset comparison.
dated(){ local a="$1"; shift; local r="$*"
         [[ "$a" == "- $TODAY${r:+ $r}" ]] || [[ "$a" == "- $(date +%Y-%m-%d)${r:+ $r}" ]]; }
undate(){ sed -E "s/^- $(date +%Y-%m-%d)( |\$)/- $TODAY\1/"; }
# `MONTH` carries the identical hazard at a UTC month boundary — the fragment directory is named for the
# month at the moment of the write, so a run that starts at 23:59 UTC on the last day of a month and
# writes at 00:01 the next day compares one month against the other. `monthed` closes it the same way
# `dated` does, by re-reading the clock at assertion time and accepting either month this run can
# legitimately have written: <string> must be <literal prefix> + docs/handoff/{AAAA-MM}/ + <suffix glob>.
# Prefix and month are matched literally; only the suffix is a pattern.
monthed(){ local s="$1" pre="$2" suf="${3-}" m
  for m in "$MONTH" "$(date -u +%Y-%m)"; do
    [[ "$s" == "$pre""docs/handoff/$m/"$suf ]] && return 0
  done
  return 1
}
# MONTHS_RE — the same two months as an alternation, for the filters that must drop fragment paths
MONTHS_RE(){ printf 'docs/handoff/(%s|%s)/' "$MONTH" "$(date -u +%Y-%m)"; }

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/handoff-tests.XXXXXX")
TMPROOT=$(cd "$TMPROOT" && pwd -P)   # resolve any symlink (e.g. macOS /tmp) so it matches git's resolved toplevel
cleanup(){ rm -rf "$TMPROOT"; }
trap cleanup EXIT
# mktemp, not a counter: mkrepo is always called in a command substitution, i.e. in a subshell, so a
# counter incremented here would never reach the parent and every test would share one repo.
mkrepo(){ local d; d=$(mktemp -d "$TMPROOT/repo.XXXXXX"); git init -q "$d" >/dev/null 2>&1; printf '%s' "$d"; }

# --- oracles -------------------------------------------------------------------------------------
# The fragments are read with the same ANCHORED awk extraction this suite has always used as its
# oracle, applied to the fragments concatenated in name order — never with the script under test.
fragfiles(){ find "$1/docs/handoff" -type f -name '*.md' 2>/dev/null | sort; }
nfrags(){ fragfiles "$1" | grep -c . ; }
allfrags(){ local f; while IFS= read -r f; do [[ -n "$f" ]] && cat "$f"; done < <(fragfiles "$1"); }
fragfacts(){ allfrags "$1" | awk '/^## Fatti/{f=1;next} /^## /{f=0} f && /^- /'; }
fraglog(){ allfrags "$1" | awk '/^## Log/{f=1;next} /^## /{f=0} f && /^- /'; }
cfacts(){ (cd "$1" && bash "$SCRIPT" facts); }
clog(){ (cd "$1" && bash "$SCRIPT" recent --all); }
nlines(){ printf '%s\n' "$1" | grep -c '^- '; }
hash12(){ python3 -c "import hashlib,sys; print(hashlib.sha1(sys.argv[1].encode()).hexdigest()[:12])" "$1"; }
# every file's path, mtime (nanoseconds) and content hash — "unchanged" means all three, so a rewrite
# with identical bytes is still caught as a write.
statesnap(){ python3 - "$1" <<'PY'
import sys, os, hashlib
root = sys.argv[1]; out = []
for dp, dn, fn in os.walk(root):
    dn[:] = [d for d in dn if d != ".git"]
    for f in fn:
        p = os.path.join(dp, f)
        st = os.stat(p)
        with open(p, "rb") as fh:
            out.append("%s %d %s" % (os.path.relpath(p, root), st.st_mtime_ns, hashlib.sha1(fh.read()).hexdigest()))
print("\n".join(sorted(out)))
PY
}
# "every line of $2 is present verbatim in $1" — the containment check every "untouched" assertion below
# is written with. A loop over a here-string, never `printf "%s\n" "$hay" | grep -qxF "$needle"`: under
# `set -o pipefail` grep -q exits at its first match, the printf ahead of it then dies of EPIPE, and the
# pipeline reports that failure — so the pipe shape turns a true assertion into a FAIL at random,
# depending only on how far down the match sits. (Seen here on the 51-file snapshot of AC2.)
holds_lines(){ local l; while IFS= read -r l; do [[ -z "$l" ]] && continue; grep -qxF -- "$l" <<<"$1" || return 1; done <<<"$2"; return 0; }

# =================================================================================================
# The facts cap — it counts the VISIBLE facts (composed, deduplicated, retracts applied), it refuses
# rather than dropping the oldest, and past PI-16 it tells the caller to `retract`, because there is no
# longer a line to "remove by hand": the fact lives in an immutable fragment.
# =================================================================================================
S=$(mkrepo)
for i in $(seq 1 $((CAP - 1))); do (cd "$S" && bash "$SCRIPT" fact "fact number $i" >/dev/null 2>&1); done
count(){ cfacts "$S" | grep -c '^- '; }
ok "$((CAP - 1)) visible facts before the last add" "[[ \"\$(count)\" -eq $((CAP - 1)) ]]"
ok "$((CAP - 1)) facts means $((CAP - 1)) fragments — one file per invocation, never appended to" \
   "[[ \"\$(nfrags \"\$S\")\" -eq $((CAP - 1)) ]]"

# AC1 — the fact that reaches the cap lands (exit 0) and warns on stderr that the cap is reached
outcap=$(cd "$S" && bash "$SCRIPT" fact "fact number $CAP" 2>&1 1>/dev/null); rccap=$?
ok "AC1 — fact reaching the cap lands with exit 0" '[[ "$rccap" -eq 0 ]]'
ok "AC1 — stderr warns the cap is reached and names the fragment it wrote" \
   "monthed \"\$outcap\" \"handoff: facts $CAP/$CAP — cap reached, next fact will be refused — \$S/\" '*.md'"
ok "AC1 — the fact reaching the cap is actually visible" 'grep -qF "fact number '"$CAP"'" <<<"$(cfacts "$S")"'
ok "$CAP visible facts after that add" "[[ \"\$(count)\" -eq $CAP ]]"

# AC2 — at the cap a new fact is refused: exit 3, nothing created, no file touched, exact stderr line
before=$(statesnap "$S")
next=$((CAP + 1))
out2=$(cd "$S" && bash "$SCRIPT" fact "fact number $next" 2>&1 1>/dev/null); rc2=$?
ok "AC2 — refused fact exits 3" '[[ "$rc2" -eq 3 ]]'
ok "AC2 — a refused fact writes nothing at all: every file identical, mtimes included" \
   '[[ "$before" == "$(statesnap "$S")" ]]'
ok "AC2 — still $CAP visible facts, not $next" "[[ \"\$(count)\" -eq $CAP ]]"
ok "AC2 — the refused fact is nowhere on disk" "! grep -rqF \"fact number $next\" \"\$S/docs\""
expected2="handoff: facts at cap ($CAP/$CAP) — not added. Ask the retro to promote stable facts to best-practices, or retract one first: handoff.sh retract \"<il testo esatto del fatto>\": fact number $next"
ok "AC2 — exact stderr line, and it points at retract, not at editing a file by hand" \
   '[[ "$out2" == "$expected2" ]]'

# AC3 — show marks the cap; below the cap it does not
showout=$(cd "$S" && bash "$SCRIPT" show)
ok "AC3 — show ends with the cap marker" "[[ \"\$(printf '%s\n' \"\$showout\" | tail -1)\" == \"facts: $CAP/$CAP (cap)\" ]]"
S2=$(mkrepo)
(cd "$S2" && bash "$SCRIPT" fact "only one fact" >/dev/null 2>&1)
ok "AC3 — below cap, show has no cap marker" \
   "! grep -qF \"facts: $CAP/$CAP (cap)\" <<<\"\$(cd \"\$S2\" && bash \"\$SCRIPT\" show)\""

# PI-16 AC5 — retract frees exactly one slot: after retracting a visible fact, a new one is accepted and
# the visible count is back at the cap, not above it.
outr=$(cd "$S" && bash "$SCRIPT" retract "fact number 1"); rcr=$?
ok "PI-16 AC5 — retract of a visible fact exits 0" '[[ "$rcr" -eq 0 ]]'
ok "PI-16 AC5 — after the retract, $((CAP - 1)) facts are visible" "[[ \"\$(count)\" -eq $((CAP - 1)) ]]"
ok "PI-16 AC5 — the retracted fact is no longer visible" '! grep -qxF -- "- fact number 1" <<<"$(cfacts "$S")"'
ok "PI-16 AC5 — sibling: its text is still on disk, in the fragment that declared it (nothing was deleted)" \
   'grep -rqxF -- "- fact number 1" "$S/docs/handoff"'
outnew=$(cd "$S" && bash "$SCRIPT" fact "fact number $next" 2>&1); rcnew=$?
ok "PI-16 AC5 — the fact refused a moment ago is accepted after the retract (exit 0)" '[[ "$rcnew" -eq 0 ]]'
ok "PI-16 AC5 — visible facts are back at $CAP, not $next" "[[ \"\$(count)\" -eq $CAP ]]"
ok "PI-16 AC5 — retract of a text that is not a visible fact exits 2 and writes nothing" \
   'st=$(statesnap "$S"); (cd "$S" && bash "$SCRIPT" retract "un fatto che non esiste" >/dev/null 2>&1); [[ "$?" -eq 2 ]] && [[ "$st" == "$(statesnap "$S")" ]]'

# =================================================================================================
# NON-ROTATION (was: PI-8 rotation). Nothing is ever moved out of the log any more: every line written
# stays readable for ever and LOGCAP is only how many lines `show` and a bare `recent` DISPLAY.
# =================================================================================================
S4=$(mkrepo)
for i in $(seq 1 45); do (cd "$S4" && bash "$SCRIPT" log "line $i" >/dev/null 2>&1); done
all4=$(clog "$S4")
ok "non-rotation — all 45 lines are still readable, none moved, none dropped" '[[ "$(nlines "$all4")" -eq 45 ]]'
ok "non-rotation — the very first line written is still there" 'grep -qE "line 1$" <<<"$all4"'
ok "non-rotation — no archive file is created, ever" '[[ ! -f "$S4/docs/SESSION_HANDOFF_ARCHIVE.md" ]]'
ok "non-rotation — 45 writes are 45 files" '[[ "$(nfrags "$S4")" -eq 45 ]]'
ok "non-rotation — a bare recent shows the newest $LOGCAP only (display window, not a cap on memory)" \
   "[[ \"\$(nlines \"\$(cd \"\$S4\" && bash \"\$SCRIPT\" recent)\")\" -eq $LOGCAP ]]"
ok "non-rotation — show displays the newest $LOGCAP too" \
   "[[ \"\$( (cd \"\$S4\" && bash \"\$SCRIPT\" show) | grep -c '^- ')\" -eq $LOGCAP ]]"
ok "non-rotation — the newest line is on top" '[[ "$(head -1 <<<"$all4")" == *"line 45" ]]'
ok "non-rotation — recent 5 shows five" '[[ "$(nlines "$(cd "$S4" && bash "$SCRIPT" recent 5)")" -eq 5 ]]'

# LOGCAP lives in exactly one place: the display header must show the live value, never a hardcoded 40.
ok "LOGCAP F2 — show's Log header shows the live cap" \
   "grep -qF \"## Log (più recente in alto, ultime $LOGCAP righe)\" <<<\"\$(cd \"\$S4\" && bash \"\$SCRIPT\" show)\""
ok "LOGCAP F2 — the script builds that header from LOGCAP, it does not spell the number out" \
   '! grep -qE "^ *print\(f?\"## Log .*ultime 40 righe" "$SCRIPT"'
ok "LOGCAP F2 — sibling, so the guard above is not vacuous: it does spell out the interpolation" \
   'grep -qE "^ *print\(f\"## Log .*\{LOGCAP\} righe\)" "$SCRIPT"'

# =================================================================================================
# PI-39 — `log` never lets a line carry two dates. Read back through the composer AND through the awk
# oracle on the fragment itself, because the date is now written into a file whose name also carries a
# timestamp: the line's date must still be exactly one.
# =================================================================================================
S19=$(mkrepo)
newest19(){ head -1 <<<"$(clog "$S19")"; }   # never `clog | head`: see holds_lines on EPIPE + pipefail

(cd "$S19" && bash "$SCRIPT" log "$TODAY testo uno" >/dev/null 2>&1)
ok "PI-39 AC1 — prefix equal to today's date is stripped, one date left" 'dated "$(newest19)" "testo uno"'
(cd "$S19" && bash "$SCRIPT" log "2020-01-01 testo due" >/dev/null 2>&1)
ok "PI-39 AC1 — prefix different from today is stripped, not kept alongside today's" 'dated "$(newest19)" "testo due"'
(cd "$S19" && bash "$SCRIPT" log "2026-09-01 2026-09-02 testo tre" >/dev/null 2>&1)
ok "PI-39 AC1 — a repeated double date prefix is stripped entirely, not just the first" 'dated "$(newest19)" "testo tre"'
(cd "$S19" && bash "$SCRIPT" log "2026-09-01" >/dev/null 2>&1)
ok "PI-39 AC1 — limit case: the message IS just a date, line still carries a single date" 'dated "$(newest19)"'
(cd "$S19" && bash "$SCRIPT" log "PI-40 PR #80 approved — regressione del 2026-09-01" >/dev/null 2>&1)
ok "PI-39 AC2 — a date NOT at the start of the message is left untouched" \
   'dated "$(newest19)" "PI-40 PR #80 approved — regressione del 2026-09-01"'
ok "PI-39 — no fragment line carries two consecutive ISO dates" \
   '! grep -rqE "^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{4}-[0-9]{2}-[0-9]{2} " "$S19/docs/handoff"'

# AC3 invariant on the REAL memory of this project: the frozen files and every fragment committed here.
ok "PI-39 AC3 — no doubled-date log line in this repo's frozen memory or in any of its fragments" \
   '! grep -rqE "^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{4}-[0-9]{2}-[0-9]{2} " "$REPO/docs/SESSION_HANDOFF.md" "$REPO/docs/SESSION_HANDOFF_ARCHIVE.md" "$REPO/docs/handoff" 2>/dev/null'

# =================================================================================================
# PI-9 — a successful write says WHICH FILE it wrote, so a missing `cd` into the right worktree is
# visible in the same output. After PI-16 that path is the fragment just created, under this month.
# =================================================================================================
S9=$(mkrepo)
outlog9=$(cd "$S9" && bash "$SCRIPT" log "an event")
ok "PI-9 AC1 — log names the fragment it created, under docs/handoff/{AAAA-MM}/" \
   'monthed "$outlog9" "handoff: logged — $S9/" "*.md"'
ok "PI-9 AC1 — sibling: that path exists and holds the event" \
   'p="${outlog9##*— }"; [[ -f "$p" ]] && grep -qF "an event" "$p"'
outfact9=$(cd "$S9" && bash "$SCRIPT" fact "a fact")
ok "PI-9 AC2 — fact names the fragment it created" 'monthed "$outfact9" "handoff: fact added — $S9/" "*.md"'
outdup9=$(cd "$S9" && bash "$SCRIPT" fact "a fact")
ok "PI-9 AC2 — a duplicate fact still names where the memory lives" '[[ "$outdup9" == *"$S9/docs/handoff"* ]]'
ok "PI-9 AC2 — a duplicate fact creates no second file" '[[ "$(nfrags "$S9")" -eq 2 ]]'
outret9=$(cd "$S9" && bash "$SCRIPT" retract "a fact")
ok "PI-9 — retract names the fragment it created and the hash it wrote" \
   'monthed "$outret9" "handoff: retracted $(hash12 "a fact") — $S9/" "*.md"'
rcredir9=$(cd "$S9" && bash "$SCRIPT" log "redirected event" >/dev/null 2>&1; echo $?)
ok "PI-9 AC3 — exit code unchanged when the output is redirected" '[[ "$rcredir9" -eq 0 ]]'
ok "PI-9 AC3 — and the event was still written" 'grep -qF "redirected event" <<<"$(clog "$S9")"'

# =================================================================================================
# PI-16 AC2 — NO PATH IS EVER WRITTEN TWICE. 50 `log` calls started together: 50 distinct files, one
# entry each, and not one pre-existing file touched (content or mtime). The 50 finish in a couple of
# seconds, so by the pigeonhole principle many of them share the same one-second stamp — which is
# exactly the case exclusive creation exists for, and the sibling below proves it really happened.
# =================================================================================================
S28=$(mkrepo)
(cd "$S28" && bash "$SCRIPT" log "riga preesistente" >/dev/null 2>&1)
before28=$(statesnap "$S28")
for i in $(seq 1 50); do (cd "$S28" && bash "$SCRIPT" log "riga parallela $i" >/dev/null 2>&1) & done
wait
ok "PI-16 AC2 — 50 concurrent writes created exactly 50 new files" '[[ "$(nfrags "$S28")" -eq 51 ]]'
ok "PI-16 AC2 — every file holds exactly one entry" \
   '[[ "$(fragfiles "$S28" | while read -r f; do grep -c "^- " "$f"; done | sort -u | tr -d "\n")" == "1" ]]'
ok "PI-16 AC2 — the pre-existing file is untouched: same bytes AND same mtime" \
   'holds_lines "$(statesnap "$S28")" "$before28"'
all28=$(clog "$S28")
ok "PI-16 AC2 — all 51 lines are readable, none lost, none duplicated" \
   '[[ "$(nlines "$all28")" -eq 51 ]] && [[ "$(printf "%s\n" "$all28" | sort -u | grep -c "^- ")" -eq 51 ]]'
ok "PI-16 AC2 — sibling: at least two of them landed in the SAME second, so exclusive creation was really exercised" \
   '[[ "$(fragfiles "$S28" | sed -E "s|.*/([0-9]{8}T[0-9]{6}Z)-.*|\1|" | sort | uniq -d | grep -c .)" -ge 1 ]]'

# =================================================================================================
# PI-16 AC3 — the frozen files are never written again, and never created.
# =================================================================================================
S29=$(mkrepo)
mkdir -p "$S29/docs"
cat > "$S29/docs/SESSION_HANDOFF.md" <<'EOF'
# Session handoff

## Fatti che non scadono
<!-- max 30 righe: invarianti, gotcha, decisioni e perché. Chi aggiunge una riga toglie quella che non vale più. -->
- un fatto congelato

## Log (più recente in alto, ultime 40 righe)
- 2026-09-01 una riga congelata
EOF
cat > "$S29/docs/SESSION_HANDOFF_ARCHIVE.md" <<'EOF'
# Session handoff — archive

## Log archiviato
- 2026-08-01 una riga archiviata
EOF
(cd "$S29" && git add -A && git commit -q -m init) >/dev/null
(cd "$S29" && bash "$SCRIPT" log "evento nuovo" >/dev/null 2>&1
              bash "$SCRIPT" fact "fatto nuovo" >/dev/null 2>&1
              bash "$SCRIPT" retract "un fatto congelato" >/dev/null 2>&1)
ok "PI-16 AC3 — git diff on the two frozen files is empty after log + fact + retract" \
   '[[ -z "$(cd "$S29" && git diff -- docs/SESSION_HANDOFF.md docs/SESSION_HANDOFF_ARCHIVE.md)" ]]'
ok "PI-16 AC3 — the stale 'max 30 righe' comment is NOT normalised: nothing rewrites that file any more" \
   'grep -qF "max 30 righe" "$S29/docs/SESSION_HANDOFF.md"'
ok "PI-16 AC3 — sibling: the three writes did happen (three fragments)" '[[ "$(nfrags "$S29")" -eq 3 ]]'
ok "PI-16 AC3 — and their effect is visible: the frozen fact is retracted, the new one is there" \
   '! grep -qF "un fatto congelato" <<<"$(cfacts "$S29")" && grep -qF "fatto nuovo" <<<"$(cfacts "$S29")"'
ok "PI-16 AC3 — the frozen log lines are still read (main and archive)" \
   'grep -qF "una riga congelata" <<<"$(clog "$S29")" && grep -qF "una riga archiviata" <<<"$(clog "$S29")"'
S30=$(mkrepo)
(cd "$S30" && bash "$SCRIPT" log "primo evento in assoluto" >/dev/null 2>&1
              bash "$SCRIPT" fact "primo fatto in assoluto" >/dev/null 2>&1)
ok "PI-16 AC3 — in a repo that never had them, the frozen files are NOT created" \
   '[[ ! -e "$S30/docs/SESSION_HANDOFF.md" ]] && [[ ! -e "$S30/docs/SESSION_HANDOFF_ARCHIVE.md" ]]'
ok "PI-16 AC3 — the only thing docs/ holds is the fragment directory" \
   '[[ "$(cd "$S30/docs" && ls -A)" == "handoff" ]]'

# =================================================================================================
# PI-16 AC4 — retract hides a fact that lives in a fragment written on ANOTHER branch and in a frozen
# source, and touches neither: same bytes, same mtime, hash before == hash after.
# =================================================================================================
S31=$(mkrepo)
mkdir -p "$S31/docs" "$S31/docs/handoff/2026-09"
cat > "$S31/docs/SESSION_HANDOFF.md" <<'EOF'
# Session handoff

## Fatti che non scadono
- fatto condiviso
- fatto che resta

## Log (più recente in alto, ultime 40 righe)
EOF
cat > "$S31/docs/handoff/2026-09/20260910T000000Z-task-altro-ramo-a1a1.md" <<'EOF'
## Fatti
- fatto condiviso
EOF
before31=$(statesnap "$S31")
ok "PI-16 AC4 — before the retract the fact is visible, once (two sources, one claim)" \
   '[[ "$(cfacts "$S31" | grep -c "^- fatto condiviso$")" -eq 1 ]]'
out31=$(cd "$S31" && bash "$SCRIPT" retract "fatto condiviso" 2>&1)
new31=${out31##*— }   # the writer prints the absolute path of the fragment it created
after31=$(statesnap "$S31")
ok "PI-16 AC4 — after the retract the fact is gone from the view" '! grep -qF "fatto condiviso" <<<"$(cfacts "$S31")"'
ok "PI-16 AC4 — the other fact is untouched" 'grep -qxF -- "- fatto che resta" <<<"$(cfacts "$S31")"'
ok "PI-16 AC4 — both source files are byte-identical and unmodified (hash and mtime before == after)" \
   '[[ "$(printf "%s\n" "$before31" | grep -vE "$(MONTHS_RE)")" == "$(printf "%s\n" "$after31" | grep -vE "$(MONTHS_RE)")" ]]'
ok "PI-16 AC4 — the retract added exactly one new file, and it holds only the hash" \
   '[[ "$(nfrags "$S31")" -eq 2 ]] && monthed "$new31" "$S31/" "*" && grep -qxF -- "- ~ $(hash12 "fatto condiviso")" "$new31"'
ok "PI-16 AC4 — the retract fragment never carries the fact's text" \
   '! grep -qF "fatto condiviso" "$new31"'

# =================================================================================================
# PI-16 × bin/retro-due.sh — THE OTHER READER OF THE WRITE CONTRACT. retro-due decides whether a retro
# is due from the handoff log, and it reads it through this composer only when it recognises one in the
# installed bin/handoff.sh; otherwise it falls back to the frozen files, which after PI-16 no writer
# touches. So "moved the writes into fragments" and "retro-due still sees what was written" are one
# change, not two: the integration is asserted here, end to end, with the real scripts.
# =================================================================================================
S33=$(mkrepo)
mkdir -p "$S33/bin"
cp "$SCRIPT" "$REPO/bin/handoff_sections.py" "$REPO/bin/retro-due.sh" "$S33/bin/"
(cd "$S33" && bash bin/handoff.sh log "BUDGET PI-0 sforato — causa nota" >/dev/null 2>&1)
out33=$(cd "$S33" && bash bin/retro-due.sh 2>&1); rc33=$?
ok "PI-16 × retro-due — a signal written into a fragment is counted (exit 10, no frozen file in sight)" \
   '[[ "$rc33" -eq 10 ]] && [[ "$out33" == *"budget"* ]] && [[ ! -e "$S33/docs/SESSION_HANDOFF.md" ]]'
# MUTATION: the pre-PI-16 detector — the bash case pattern alone — on the very same repo. It is what
# made this test necessary: it reads the memory as empty and the retro never comes due.
sed '/PI-16: the SPEC entry/d' "$REPO/bin/retro-due.sh" > "$S33/bin/retro-due-old.sh"
out33m=$(cd "$S33" && bash bin/retro-due-old.sh 2>&1); rc33m=$?
ok "PI-16 × retro-due — sibling: with the old case-pattern detector the same memory reads as empty" \
   '[[ "$rc33m" -eq 0 ]] && [[ "$out33m" == "retro-due: nothing" ]]'

# The two files travel together: bin/handoff.sh is nothing without bin/handoff_sections.py, and an
# install that carries only one of them must say so and write nothing, not half-write a fragment with a
# traceback for a confirmation.
S34=$(mkrepo)
mkdir -p "$S34/bin"
cp "$SCRIPT" "$S34/bin/"
out34=$(cd "$S34" && bash bin/handoff.sh log "riga con la libreria mancante" 2>&1); rc34=$?
ok "PI-16 — without bin/handoff_sections.py the script refuses (exit 1) and names the missing file" \
   '[[ "$rc34" -eq 1 ]] && [[ "$out34" == *"handoff_sections.py"* ]]'
ok "PI-16 — and it wrote nothing at all" '[[ ! -e "$S34/docs" ]]'

# =================================================================================================
# PI-16 AC1 — NON-CONTENTION, the four-branch scenario of TAD §11.2. Two task branches write memory
# (log + fact + retract), two chore branches write one line each on the base, one task branch is merged
# with --squash and then writes again. Everything merges with zero conflicts and nothing is lost.
# GIT_ATTR_NOSYSTEM=1 plus an empty .gitattributes: no system or repo merge driver can be what makes
# this pass — the union has to come from the fact that no two branches ever wrote the same path.
# =================================================================================================
S32=$(mkrepo)
mkdir -p "$S32/docs"
: > "$S32/.gitattributes"
cat > "$S32/docs/SESSION_HANDOFF.md" <<'EOF'
# Session handoff

## Fatti che non scadono
- fatto alfa
- fatto beta

## Log (più recente in alto, ultime 40 righe)
EOF
g(){ (cd "$S32" && GIT_ATTR_NOSYSTEM=1 git "$@"); }
h(){ (cd "$S32" && bash "$SCRIPT" "$@" >/dev/null 2>&1); }
g checkout -q -b base >/dev/null 2>&1
g add -A >/dev/null; g commit -q -m base >/dev/null
for b in task/a task/b chore/1 chore/2; do
  g checkout -q base
  g checkout -q -b "$b"
  case "$b" in
    task/a) h log "evento di a"; h fact "fatto di a"; h retract "fatto alfa";;
    task/b) h log "evento di b"; h fact "fatto di b"; h retract "fatto beta";;
    *)      h log "evento di ${b//\//-}";;
  esac
  g add -A >/dev/null; g commit -q -m "$b" >/dev/null
done
conflicts32=0
g checkout -q base
for b in chore/1 chore/2 task/b; do
  g merge -q --no-edit "$b" >/dev/null 2>&1 || conflicts32=$((conflicts32 + 1))
done
g merge -q --squash task/a >/dev/null 2>&1 || conflicts32=$((conflicts32 + 1))
g commit -q -m "squash di task/a" >/dev/null
# task/a keeps going on its own branch after having been squashed into base — the case that makes a
# single shared file conflict for ever, because base's squash commit has no ancestry with it.
g checkout -q task/a
h log "evento di a dopo lo squash"
g add -A >/dev/null; g commit -q -m "task/a again" >/dev/null
g checkout -q base
g merge -q --no-edit task/a >/dev/null 2>&1 || conflicts32=$((conflicts32 + 1))
ok "PI-16 AC1 — the four-branch scenario merges with zero conflicts" '[[ "$conflicts32" -eq 0 ]]'
ok "PI-16 AC1 — and git agrees: no unmerged paths left" '[[ -z "$(g ls-files -u)" ]]'
all32=$(clog "$S32")
expected32=$(printf '%s\n' "- $TODAY evento di a" "- $TODAY evento di a dopo lo squash" "- $TODAY evento di b" "- $TODAY evento di chore-1" "- $TODAY evento di chore-2" | sort)
ok "PI-16 AC1 — the multiset of recent --all equals exactly the five lines written on the four branches" \
   '[[ "$(printf "%s\n" "$all32" | undate | sort)" == "$(printf "%s\n" "$expected32" | undate)" ]]'
facts32=$(cfacts "$S32")
ok "PI-16 AC1 — both branches' facts survived the merges" \
   'grep -qxF -- "- fatto di a" <<<"$facts32" && grep -qxF -- "- fatto di b" <<<"$facts32"'
ok "PI-16 AC1 — both retracts survived too: the two frozen facts are hidden" \
   '! grep -qF "fatto alfa" <<<"$facts32" && ! grep -qF "fatto beta" <<<"$facts32"'
ok "PI-16 AC1 — the frozen file is still byte-identical to the one committed on base" \
   '[[ -z "$(g diff base -- docs/SESSION_HANDOFF.md)" ]] && [[ -z "$(g status --porcelain)" ]]'
# MUTATION, in-suite: the same five writes into ONE shared file per branch. If this merged cleanly the
# scenario above would prove nothing — it is the shape PI-16 exists to leave behind.
S33=$(mkrepo)
gm(){ (cd "$S33" && GIT_ATTR_NOSYSTEM=1 git "$@"); }
: > "$S33/.gitattributes"; mkdir -p "$S33/docs"; printf '# memoria\n' > "$S33/docs/ONE.md"
gm checkout -q -b base >/dev/null 2>&1; gm add -A >/dev/null; gm commit -q -m base >/dev/null
for b in task/a task/b; do
  gm checkout -q base; gm checkout -q -b "$b"
  # the pre-PI-16 shape: PREPEND to the shared file, exactly what `log` used to do
  python3 - "$S33/docs/ONE.md" "$b" <<'PY'
import sys
p, b = sys.argv[1], sys.argv[2]
s = open(p).read().split("\n")
open(p, "w").write("\n".join([s[0], "- riga di " + b] + s[1:]))
PY
  gm add -A >/dev/null; gm commit -q -m "$b" >/dev/null
done
gm checkout -q base
gm merge -q --no-edit task/a >/dev/null 2>&1; mrc1=$?
gm merge -q --no-edit task/b >/dev/null 2>&1; mrc2=$?
ok "PI-16 AC1 mutation — one shared file per branch DOES conflict (so the proof above is not vacuous)" \
   '[[ "$mrc1" -eq 0 ]] && [[ "$mrc2" -ne 0 ]] && [[ -n "$(gm ls-files -u)" ]]'
gm merge --abort >/dev/null 2>&1

# =================================================================================================
# PI-16 AC6 — on a copy of THIS repo's real memory: a log and a fact add exactly themselves, and every
# line of today's awk extraction is still there afterwards.
# =================================================================================================
S34=$(mkrepo)
mkdir -p "$S34/docs"
cp "$REPO/docs/SESSION_HANDOFF.md" "$S34/docs/SESSION_HANDOFF.md"
cp "$REPO/docs/SESSION_HANDOFF_ARCHIVE.md" "$S34/docs/SESSION_HANDOFF_ARCHIVE.md"
awkfacts34=$(awk '/^## Fatti/{f=1;next} /^## /{f=0} f && /^- /' "$S34/docs/SESSION_HANDOFF.md")
awkmain34=$(awk '/^## Log/{f=1;next} f && /^- /' "$S34/docs/SESSION_HANDOFF.md")
awkarch34=$(awk '/^## Log archiviato/{f=1;next} f && /^- /' "$S34/docs/SESSION_HANDOFF_ARCHIVE.md")
ok "PI-16 AC6 — before any write, facts is byte-identical to the pre-PI-14 awk on the real memory ($(nlines "$awkfacts34") lines)" \
   '[[ "$(cfacts "$S34")" == "$awkfacts34" ]]'
(cd "$S34" && bash "$SCRIPT" log "una riga nuova sulla memoria vera" >/dev/null 2>&1
              bash "$SCRIPT" fact "un fatto nuovo sulla memoria vera" >/dev/null 2>&1)
ok "PI-16 AC6 — facts is the awk set plus the new fact, in order, nothing else changed" \
   '[[ "$(cfacts "$S34")" == "$(printf "%s\n%s" "$awkfacts34" "- un fatto nuovo sulla memoria vera")" ]]'
exp34=$(printf '%s\n%s\n%s\n' "$awkmain34" "$awkarch34" "- $TODAY una riga nuova sulla memoria vera" | grep '^- ' | sort)
ok "PI-16 AC6 — recent --all is the multiset of main log + archive + the new line ($(printf '%s\n' "$exp34" | grep -c '^- ') lines)" \
   '[[ "$(clog "$S34" | undate | sort)" == "$(printf "%s\n" "$exp34" | undate)" ]]'
ok "PI-16 AC6 — the two frozen files were not touched by those writes" \
   'cmp -s "$S34/docs/SESSION_HANDOFF.md" "$REPO/docs/SESSION_HANDOFF.md" && cmp -s "$S34/docs/SESSION_HANDOFF_ARCHIVE.md" "$REPO/docs/SESSION_HANDOFF_ARCHIVE.md"'

# =================================================================================================
# PI-16 AC7 — `where` is the installed-version signal: it prints the relative directory a write would
# use, needs no git repository, and creates nothing. The mutation is the PRE-PI-16 behaviour, written
# out here as a stand-in (resolve the toplevel or exit 1, then mkdir -p docs and create the file): it
# must fail both halves, or these two checks would pass on a machine where nothing was installed.
# =================================================================================================
D35="$TMPROOT/notarepo"; mkdir -p "$D35"
out35=$(cd "$D35" && bash "$SCRIPT" where 2>&1); rc35=$?
ok "PI-16 AC7 — where outside a git repo prints docs/handoff/{AAAA-MM}/" 'monthed "$out35" "" ""'
ok "PI-16 AC7 — where outside a git repo exits 0" '[[ "$rc35" -eq 0 ]]'
ok "PI-16 AC7 — and the directory is still empty" '[[ -z "$(find "$D35" -mindepth 1)" ]]'
OLD35="$TMPROOT/old-handoff.sh"
cat > "$OLD35" <<'EOF'
#!/usr/bin/env bash
# stand-in for the pre-PI-16 entry point: resolve the repo root or die, then make sure the file exists.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel) || exit 1
mkdir -p "$ROOT/docs"
[[ -f "$ROOT/docs/SESSION_HANDOFF.md" ]] || printf '# Session handoff\n' > "$ROOT/docs/SESSION_HANDOFF.md"
echo "docs/handoff/$(date -u +%Y-%m)/"
EOF
rcold35=$( (cd "$D35" && bash "$OLD35" >/dev/null 2>&1); echo $? )
ok "PI-16 AC7 mutation — the pre-PI-16 script exits 1 outside a repo (so the checks above are not vacuous)" \
   '[[ "$rcold35" -eq 1 ]] && [[ -z "$(find "$D35" -mindepth 1)" ]]'
for variant in bare withold; do
  S36=$(mkrepo)
  if [[ "$variant" == withold ]]; then
    mkdir -p "$S36/docs"; cp "$REPO/docs/SESSION_HANDOFF.md" "$S36/docs/SESSION_HANDOFF.md"
  fi
  (cd "$S36" && git add -A >/dev/null 2>&1 && git commit -q -m init --allow-empty) >/dev/null 2>&1
  before36=$(cd "$S36" && git status --porcelain)
  out36=$(cd "$S36" && bash "$SCRIPT" where 2>&1); rc36=$?
  ok "PI-16 AC7 [$variant] — same output in a repo root, exit 0" 'monthed "$out36" "" "" && [[ "$rc36" -eq 0 ]]'
  ok "PI-16 AC7 [$variant] — git status --porcelain identical before and after" \
     '[[ "$before36" == "$(cd "$S36" && git status --porcelain)" ]]'
  ok "PI-16 AC7 [$variant] — where created no directory" '[[ ! -d "$S36/docs/handoff" ]]'
  if [[ "$variant" == bare ]]; then
    (cd "$S36" && bash "$OLD35" >/dev/null 2>&1)
    ok "PI-16 AC7 mutation — the pre-PI-16 script leaves '?? docs/' behind in a repo without docs/" \
       '[[ "$(cd "$S36" && git status --porcelain)" == "?? docs/" ]]'
    rm -rf "$S36/docs"
  fi
done

# =================================================================================================
# PI-16 — the fragment name. The slug is a branch name, i.e. attacker-shaped input; whatever it holds,
# the write lands under docs/handoff/{AAAA-MM}/ and the name stays inside a safe charset.
# =================================================================================================
S37=$(mkrepo)
(cd "$S37" && git checkout -q -b 'Feature/ÀÉ_Strano..cose' 2>/dev/null || git checkout -q -b 'Feature/Strano_cose')
outw37=$(cd "$S37" && bash "$SCRIPT" log "riga da un ramo dal nome ostile" 2>&1)
p37="${outw37##*— }"
ok "PI-16 — a hostile branch name still writes inside docs/handoff/{AAAA-MM}/" \
   'monthed "$p37" "$S37/" "*" && [[ -f "$p37" ]]'
ok "PI-16 — the file name is stamp + sanitised slug + 4 random [a-z0-9], nothing else" \
   '[[ "$(basename "$p37")" =~ ^[0-9]{8}T[0-9]{6}Z-[a-z0-9-]+-[a-z0-9]{4}\.md$ ]]'
ok "PI-16 — nothing was created outside docs/handoff" \
   '[[ "$(find "$S37" -type f -not -path "*/.git/*" | grep -vc "/docs/handoff/")" -eq 0 ]]'
S38=$(mkrepo)
LONGB="feature/$(printf 'x%.0s' $(seq 1 80))"
(cd "$S38" && git checkout -q -b "$LONGB")
outw38=$(cd "$S38" && bash "$SCRIPT" log "riga da un ramo dal nome lunghissimo" 2>&1)
slug38=$(basename "${outw38##*— }" .md); slug38="${slug38#*Z-}"; slug38="${slug38%-*}"
ok "PI-16 — the slug is capped at 40 characters" '[[ "${#slug38}" -le 40 ]] && [[ "${#slug38}" -ge 1 ]]'
S39=$(mkrepo)
(cd "$S39" && bash "$SCRIPT" log "primo" >/dev/null 2>&1 && git add -A >/dev/null && git commit -q -m c >/dev/null && git checkout -q --detach HEAD)
outw39=$(cd "$S39" && bash "$SCRIPT" log "da HEAD staccata" 2>&1)
ok "PI-16 — a detached HEAD writes a 'detached-{sha7}' slug, not an empty one" \
   '[[ "$(basename "${outw39##*— }")" =~ ^[0-9]{8}T[0-9]{6}Z-detached-[0-9a-f]{7}-[a-z0-9]{4}\.md$ ]]'

# =================================================================================================
# PI-14 — the read-only composer. Ordering, dedup and retract rules of TAD §4.3, on fixtures that
# encode specific days and timestamps. These fixtures are hand-built ON PURPOSE and it is the only
# class that is: a writer can only ever produce "now" and can no longer produce a frozen file at all,
# so a fixture pinning a source to 2026-09-10 (or holding a frozen file) cannot be generated by running
# the writers — the same exception the over-cap Log section always was. Everything a writer CAN
# produce is produced by running it (see mkpoisoned40 and the PI-40 grid below).
# =================================================================================================
# AC3 — ## Log, ## Fatti, ## Ritirati; two identical log lines in two fragments; an archive section
# sharing a fragment's name (declared copy, counted once); an orphan archive section.
S12=$(mkrepo)
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
recent12=$(clog "$S12")
ok "AC3 — the duplicated log line appears twice (two events, never deduped)" \
   '[[ "$(printf "%s\n" "$recent12" | grep -c "^- 2026-09-13 riga duplicata$")" -eq 2 ]]'
ok "AC3 — the declared copy (archive section == live fragment name) counts once" \
   '[[ "$(printf "%s\n" "$recent12" | grep -c "riga del frammento con copia")" -eq 1 ]]'
ok "AC3 — an archive section with no live fragment (orphan) is still read" \
   '[[ "$(printf "%s\n" "$recent12" | grep -c "riga solo in archivio")" -eq 1 ]]'
facts12=$(cfacts "$S12")
ok "AC3 — the retracted fact (frozen source) does not appear" '! grep -qF "fatto da ritirare" <<<"$facts12"'
ok "AC3 — the retracted fact (fragment source, older than the retract) does not appear" \
   '! grep -qF "fatto vecchio del frammento" <<<"$facts12"'
ok "AC3 — the untouched fact still appears" 'grep -qF "fatto stabile" <<<"$facts12"'
ok "AC3 — the same fact in two sources counts once" \
   '[[ "$(printf "%s\n" "$facts12" | grep -c "^- fatto duplicato$")" -eq 1 ]]'
cat > "$S12/docs/handoff/2026-09/20260915T090000Z-fix-e5e5.md" <<'EOF'
## Fatti
- fatto da ritirare
EOF
ok "AC3 — the same fact rewritten after the retract is visible again" 'grep -qF "fatto da ritirare" <<<"$(cfacts "$S12")"'
# and the same thing through the REAL writers, in the same second: `fact` stamps its fragment after the
# retract it overrides, and `retract` stamps its own after the fact it hides, so the rule stays decidable
# at one-second resolution instead of depending on which of the two happened to be written first.
S40=$(mkrepo)
(cd "$S40" && bash "$SCRIPT" fact "fatto scritto e ritirato nello stesso secondo" >/dev/null 2>&1
              bash "$SCRIPT" retract "fatto scritto e ritirato nello stesso secondo" >/dev/null 2>&1)
ok "PI-16 — fact then retract inside the same second: the fact is hidden" \
   '[[ -z "$(cfacts "$S40")" ]]'
(cd "$S40" && bash "$SCRIPT" fact "fatto scritto e ritirato nello stesso secondo" >/dev/null 2>&1)
ok "PI-16 — and re-declaring it inside the same second brings it back" \
   '[[ "$(cfacts "$S40")" == "- fatto scritto e ritirato nello stesso secondo" ]]'

# AC4 — facts/show/recent/grep/where never write: git status --porcelain identical before and after,
# with and without the frozen file, no file and no directory created.
for variant in bare withold; do
  S13=$(mkrepo)
  if [[ "$variant" == withold ]]; then
    mkdir -p "$S13/docs"
    cp "$REPO/docs/SESSION_HANDOFF.md" "$S13/docs/SESSION_HANDOFF.md"
    (cd "$S13" && git add -A && git commit -q -m init) >/dev/null
  fi
  before13=$(cd "$S13" && git status --porcelain)
  (cd "$S13" && bash "$SCRIPT" facts >/dev/null 2>&1
                bash "$SCRIPT" show >/dev/null 2>&1
                bash "$SCRIPT" recent 5 >/dev/null 2>&1
                bash "$SCRIPT" grep X >/dev/null 2>&1
                bash "$SCRIPT" where >/dev/null 2>&1)
  ok "AC4 [$variant] — git status --porcelain identical before/after five reads" '[[ "$before13" == "$(cd "$S13" && git status --porcelain)" ]]'
  ok "AC4 [$variant] — no docs/handoff created by a read" '[[ ! -d "$S13/docs/handoff" ]]'
done

# A read must not normalise anything either: a stale cap comment, a fragment and an archive section, all
# committed, so any reintroduced rewrite-on-read shows up as a real diff.
S13b=$(mkrepo)
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
before13b=$(statesnap "$S13b")
(cd "$S13b" && bash "$SCRIPT" facts >/dev/null 2>&1
               bash "$SCRIPT" show >/dev/null 2>&1
               bash "$SCRIPT" recent 5 >/dev/null 2>&1
               bash "$SCRIPT" grep X >/dev/null 2>&1
               bash "$SCRIPT" where >/dev/null 2>&1)
ok "AC4 [stale-comment+fragments] — not one file changed, mtimes included" '[[ "$before13b" == "$(statesnap "$S13b")" ]]'
ok "AC4 [stale-comment+fragments] — the stale comment is still 'max 30 righe' after five reads" \
   'grep -qF "max 30 righe" "$S13b/docs/SESSION_HANDOFF.md"'

# outside a repo: exit 1 for everything that needs one, nothing created, no traceback
D13c="$TMPROOT/nonrepo-reads"; mkdir -p "$D13c"
outnr=$(cd "$D13c" && bash "$SCRIPT" facts 2>&1); rcnr=$?
ok "AC4 [outside a repo] — facts exits 1 with a plain message, not a traceback" \
   '[[ "$rcnr" -eq 1 ]] && [[ "$outnr" == "handoff: not a git repository" ]]'
ok "AC4 [outside a repo] — no file created" '[[ -z "$(find "$D13c" -mindepth 1)" ]]'

# AC5 — ordering: day descending, and at equal day fragments (newest timestamp first), then the frozen
# main log top-down, then the frozen archive bottom-up.
S14=$(mkrepo)
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
ok "AC5 — order is 12, 11, 10" \
   '[[ "$(clog "$S14")" == "$(printf "%s\n%s\n%s" "- 2026-09-12 evento frammento" "- 2026-09-11 evento frammento" "- 2026-09-10 evento congelato")" ]]'

S15=$(mkrepo)
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
expected15=$(printf '%s\n%s\n%s\n%s\n%s' \
  "- 2026-09-13 riga frammento tardi" "- 2026-09-13 riga frammento presto" \
  "- 2026-09-13 riga principale" \
  "- 2026-09-13 riga archivio nuova" "- 2026-09-13 riga archivio vecchia")
ok "AC5 — same-day tie-break: fragments (newest ts first), then main log, then archive bottom-up" \
   '[[ "$(clog "$S15")" == "$expected15" ]]'

# Finding 4 — the 10 characters str.splitlines() breaks on and awk's RS="\n" does not. Every one of them
# must survive as DATA, byte for byte, in a frozen source and in a fragment alike.
for sepname in CRLF CR VT FF FS GS RS NEL LS PS; do
  S16=$(mkrepo)
  mkdir -p "$S16/docs" "$S16/docs/handoff/2026-09"
  python3 - "$S16/docs/SESSION_HANDOFF.md" "$S16/docs/handoff/2026-09/20260912T090000Z-sep-s1s1.md" "$sepname" <<'PY'
import sys
path, frag, name = sys.argv[1], sys.argv[2], sys.argv[3]
SEP = {
    "CRLF": "\r\n", "CR": "\r", "VT": "\x0b", "FF": "\x0c",
    "FS": "\x1c", "GS": "\x1d", "RS": "\x1e",
    "NEL": "\x85", "LS": " ", "PS": " ",
}[name]
with open(path, "w", encoding="utf-8", newline="") as f:
    f.write("# Session handoff\n\n"
            "## Fatti che non scadono\n"
            f"- fact a{SEP}b\n\n"
            "## Log (più recente in alto, ultime 40 righe)\n"
            f"- 2026-09-12 log a{SEP}b\n")
with open(frag, "w", encoding="utf-8", newline="") as f:
    f.write("## Fatti\n" f"- fragment fact a{SEP}b\n")
PY
  awkfacts=$(awk '/^## Fatti/{f=1;next} /^## /{f=0} f && /^- /' "$S16/docs/SESSION_HANDOFF.md"; awk '/^## Fatti/{f=1;next} /^## /{f=0} f && /^- /' "$S16/docs/handoff/2026-09/20260912T090000Z-sep-s1s1.md")
  ok "Finding4 [$sepname] — facts byte-identical to awk, frozen source and fragment alike" \
     '[[ "$(cfacts "$S16")" == "$awkfacts" ]]'
  awklog=$(awk '/^## Log/{f=1;next} f && /^- /' "$S16/docs/SESSION_HANDOFF.md")
  ok "Finding4 [$sepname] — recent --all byte-identical to awk with the separator embedded as data" \
     '[[ "$(clog "$S16")" == "$awklog" ]]'
done

# =================================================================================================
# Argv grammar (§5.1). One declaration — SPEC in bin/handoff.sh — drives the real validation, the usage
# text and these tests, so nothing here repeats a number by hand and a subcommand cannot exist outside
# it: after PI-16 there is no bash `case` on the command either, reads and writes go through the same
# single list.
# =================================================================================================
S17=$(mkrepo)
for bad in "recent abc" "recent --al" "recent -1" "grep [" "grep" "log" "fact" "retract" "where X" "facts X" "nosuchcommand"; do
  out17=$(cd "$S17" && bash "$SCRIPT" $bad 2>&1); rc17=$?
  ok "argv — '$bad' exits 2" '[[ "$rc17" -eq 2 ]]'
  ok "argv — '$bad' prints the usage line" '[[ "$out17" == usage:* ]]'
done
ok "argv — a write refused for bad argv writes nothing" '[[ ! -d "$S17/docs" ]]'

S18=$(mkrepo)
speclines=$(cd "$S18" && bash "$SCRIPT" __spec)
ok "argspec — __spec declares exactly the eight subcommands, reads and writes in one list" \
   '[[ "$(printf "%s\n" "$speclines" | awk "{print \$1}" | sort | tr "\n" " ")" == "fact facts grep log recent retract show where " ]]'
usage18=$(cd "$S18" && bash "$SCRIPT" nosuchcommand 2>&1)
while read -r specname lo hi bad kind syntax; do
  [[ -z "$specname" ]] && continue
  ok "argspec[$specname] — the usage line advertises it" '[[ "$usage18" == *"$syntax"* ]]'

  # one argument more than the declared max — only for the subcommands that declare one ("-" is "one or
  # more arguments, joined with a space", which is what keeps an unquoted call from losing a word)
  if [[ "$hi" != "-" ]]; then
    extra=(); for ((i = 0; i <= hi; i++)); do extra+=("X"); done
    outmany=$(cd "$S18" && bash "$SCRIPT" "$specname" "${extra[@]}" 2>&1); rcmany=$?
    ok "argspec[$specname] — $((hi + 1)) args (declared max $hi) → exit 2" '[[ "$rcmany" -eq 2 ]]'
    ok "argspec[$specname] — usage line on too many args" '[[ "$outmany" == usage:* ]]'
  fi

  # one argument fewer than the declared min
  if [[ "$lo" -gt 0 ]]; then
    short=(); for ((i = 0; i < lo - 1; i++)); do short+=("X"); done
    if [[ "${#short[@]}" -gt 0 ]]; then
      outfew=$(cd "$S18" && bash "$SCRIPT" "$specname" "${short[@]}" 2>&1); rcfew=$?
    else
      outfew=$(cd "$S18" && bash "$SCRIPT" "$specname" 2>&1); rcfew=$?
    fi
    ok "argspec[$specname] — $((lo - 1)) args (declared min $lo) → exit 2" '[[ "$rcfew" -eq 2 ]]'
    ok "argspec[$specname] — usage line on too few args" '[[ "$outfew" == usage:* ]]'
  fi

  # the declaration's own known-bad value, for the subcommands that declare a per-argument check
  if [[ "$bad" != "-" ]]; then
    outbad=$(cd "$S18" && bash "$SCRIPT" "$specname" "$bad" 2>&1); rcbad=$?
    ok "argspec[$specname] — declared bad value '$bad' → exit 2" '[[ "$rcbad" -eq 2 ]]'
    ok "argspec[$specname] — usage line on the declared bad value" '[[ "$outbad" == usage:* ]]'
  fi

  # the declared kind, checked where it is observable: outside a git repository
  args=(); for ((i = 0; i < lo; i++)); do args+=("X"); done
  if [[ "${#args[@]}" -gt 0 ]]; then
    rckind=$( (cd "$D13c" && bash "$SCRIPT" "$specname" "${args[@]}" >/dev/null 2>&1); echo $? )
  else
    rckind=$( (cd "$D13c" && bash "$SCRIPT" "$specname" >/dev/null 2>&1); echo $? )
  fi
  if [[ "$kind" == free ]]; then
    ok "argspec[$specname] — declared 'free': exits 0 outside a git repository" '[[ "$rckind" -eq 0 ]]'
  else
    ok "argspec[$specname] — declared 'repo': exits 1 outside a git repository" '[[ "$rckind" -eq 1 ]]'
  fi
done <<<"$speclines"
ok "argspec — nothing was written outside a repo by any of those calls" '[[ -z "$(find "$D13c" -mindepth 1)" ]]'
rc18=$( (cd "$S18" && bash "$SCRIPT" __spec X >/dev/null 2>&1); echo $? )
ok "argspec — __spec is internal and takes no arguments (exit 2, PI-14 review finding)" '[[ "$rc18" -eq 2 ]]'

# =================================================================================================
# PI-40 — no write, of any shape, may add or destroy a heading, or lose a line that was already there.
# The reader half (a heading is "## " at the start of a line, never a substring) is unchanged. The
# WRITER half is now stated on the new write path, which is strictly stronger and is re-derived, not
# re-run: every pre-existing file must be byte-identical afterwards (they are never opened for writing
# at all), the invocation must create EXACTLY ONE new file, and that file must hold exactly one heading
# and exactly one record — so the caller's text, whatever it holds, can only ever be one line of data
# inside a file whose heading the writer put there itself.
# =================================================================================================
# The fixture is PRODUCED BY RUNNING THE REAL WRITERS, never printf'd line by line: a hand-composed
# fixture can only hold lines that already look like data, so it cannot exhibit what the WRITER is able
# to put on disk — and that is where the second half of this bug lived.
mkpoisoned40(){   # $1 = repo dir, $2 = the fact text that quotes a marker, $3.. = log lines, OLDEST first
  local d="$1" poison="$2" l; shift 2
  ( cd "$d" \
    && bash "$SCRIPT" fact "primo fatto, sopra la citazione" \
    && bash "$SCRIPT" fact "$poison" \
    && bash "$SCRIPT" fact "ultimo fatto, SOTTO la citazione" ) >/dev/null 2>&1
  for l in "$@"; do (cd "$d" && bash "$SCRIPT" log "$l") >/dev/null 2>&1; done
}
POISONS40=(
  $'regola: controlla con `awk \'/^## Log/{f=1;next} /^## /{f=0}\'` prima di scrivere'
  'la sezione ## Log sta in fondo al file'
  '## Log è il marcatore che ogni lettore cerca'
  'il file finisce con ## Log (più recente in alto, ultime 40 righe)'
  'due marcatori in una riga: ## Fatti che non scadono e ## Log'
  'vedi ## Log'
  $'## Log\nun testo che comincia con il marcatore e prosegue'
  $'un testo con il marcatore in mezzo\n## Fatti che non scadono\ne del testo dopo'
  $'un testo che finisce con il marcatore\n## Qualunque altra sezione'
  $'\n## Log'
)

# AC1 — one disposable repo per member of the class: after a `log`, the facts are still facts (the one
# quoting a marker included), the new line is the newest log line, and nothing on disk moved.
for idx in $(seq 0 $((${#POISONS40[@]} - 1))); do
  poison40="${POISONS40[$idx]}"
  S20=$(mkrepo)
  mkpoisoned40 "$S20" "$poison40" "una riga di log che c'era già"
  beforefacts20=$(cfacts "$S20"); beforestate20=$(statesnap "$S20"); nb20=$(nfrags "$S20")
  (cd "$S20" && bash "$SCRIPT" log "PI-40 nuova riga di log" >/dev/null 2>&1)
  ok "PI-40 AC1 [$idx] — every file that existed before the write is byte-identical, mtime included" \
     '[[ "$(statesnap "$S20" | grep -vxF -f <(printf "%s\n" "$beforestate20") | grep -c .)" -eq 1 ]]'
  ok "PI-40 AC1 [$idx] — the write created exactly one new file" '[[ "$(nfrags "$S20")" -eq $((nb20 + 1)) ]]'
  ok "PI-40 AC1 [$idx] — every fact is byte-identical, the one quoting the marker included" \
     '[[ "$(cfacts "$S20")" == "$beforefacts20" ]]'
  ok "PI-40 AC1 [$idx] — the fact standing AFTER the quote is still a fact" \
     'grep -qF "ultimo fatto, SOTTO la citazione" <<<"$(cfacts "$S20")"'
  ok "PI-40 AC1 [$idx] — the new line is the newest line of the composed log" \
     '[[ "$(head -1 <<<"$(clog "$S20")")" == *"PI-40 nuova riga di log" ]]'
  ok "PI-40 AC1 [$idx] — the pre-existing log line is still there (2 log lines)" \
     '[[ "$(nlines "$(clog "$S20")")" -eq 2 ]]'
  ok "PI-40 AC1 [$idx] — the composed facts equal the anchored awk extraction over the fragments" \
     '[[ "$(cfacts "$S20")" == "$(fragfacts "$S20")" ]]'
  ok "PI-40 AC1 [$idx] — nothing was rotated and no frozen file was invented" \
     '[[ ! -e "$S20/docs/SESSION_HANDOFF.md" ]] && [[ ! -e "$S20/docs/SESSION_HANDOFF_ARCHIVE.md" ]]'
done

# AC2 — five writes in a row on the same poisoned memory: the facts never shrink, the log grows by
# exactly one each time, and every earlier file stays byte-identical after EVERY write, not just at the
# end (the old defect repeated on each run).
S21=$(mkrepo)
mkpoisoned40 "$S21" "${POISONS40[0]}" "una riga di log che c'era già"
minfacts21=$(nlines "$(cfacts "$S21")"); stateok21=1; factok21=1; logok21=1
for n in 1 2 3 4 5; do
  st21=$(statesnap "$S21"); nlog21=$(nlines "$(clog "$S21")")
  (cd "$S21" && bash "$SCRIPT" log "evento numero $n" >/dev/null 2>&1)
  [[ "$(statesnap "$S21" | grep -vxF -f <(printf "%s\n" "$st21") | grep -c .)" -eq 1 ]] || stateok21=0
  [[ "$(nlines "$(cfacts "$S21")")" -ge "$minfacts21" ]] || factok21=0
  [[ "$(nlines "$(clog "$S21")")" -eq $((nlog21 + 1)) ]] || logok21=0
done
ok "PI-40 AC2 — after each of 5 consecutive writes, exactly one file is new and none changed" '[[ "$stateok21" -eq 1 ]]'
ok "PI-40 AC2 — the fact count never decreases across the 5 writes" '[[ "$factok21" -eq 1 ]]'
ok "PI-40 AC2 — the log grows by exactly one line per write" '[[ "$logok21" -eq 1 ]]'

# AC3 — a frozen file with facts only, one of which reads like a log line: a log write must not
# re-parent it, and must not touch the file at all.
S22=$(mkrepo)
mkdir -p "$S22/docs"
cat > "$S22/docs/SESSION_HANDOFF.md" <<'EOF'
# Session handoff

## Fatti che non scadono
- un fatto che cita ## Log dentro il proprio testo
- 2026-01-01 un fatto che sembra una riga di log ma è un fatto
EOF
beforestate22=$(statesnap "$S22"); beforefacts22=$(cfacts "$S22")
(cd "$S22" && bash "$SCRIPT" log "prima riga di log in assoluto" >/dev/null 2>&1)
ok "PI-40 AC3 — both pre-existing facts are untouched, the dated one included" '[[ "$(cfacts "$S22")" == "$beforefacts22" ]]'
ok "PI-40 AC3 — the frozen file is byte-identical, mtime included" \
   'holds_lines "$(statesnap "$S22")" "$beforestate22"'
ok "PI-40 AC3 — the log holds exactly one line: the new one, nothing re-parented" \
   '[[ "$(nlines "$(clog "$S22")")" -eq 1 ]] && [[ "$(clog "$S22")" == *"prima riga di log in assoluto" ]]'
ok "PI-40 AC3 — the new line is in its own fragment, which holds one heading and one record" \
   '[[ "$(nfrags "$S22")" -eq 1 ]] && [[ "$(allfrags "$S22" | grep -c "^## ")" -eq 1 ]] && [[ "$(allfrags "$S22" | grep -c "^- ")" -eq 1 ]]'

# AC4 (was: rotation) — a Log section already far past the display window, hand-built in a FROZEN file
# because no writer can produce that state any more: a write neither moves a line out of it nor changes
# it, and everything stays readable.
S23=$(mkrepo)
mkpoisoned40 "$S23" "${POISONS40[3]}"
mkdir -p "$S23/docs"
{ echo "# Session handoff"; echo; echo "## Fatti che non scadono"; echo;
  echo "## Log (più recente in alto, ultime 40 righe)";
  for i in $(seq 45 -1 1); do echo "- 2026-01-01 entry $i"; done; } > "$S23/docs/SESSION_HANDOFF.md"
beforestate23=$(statesnap "$S23"); beforefacts23=$(cfacts "$S23")
(cd "$S23" && bash "$SCRIPT" log "entry 46" >/dev/null 2>&1)
ok "PI-40 AC4 — the over-cap frozen file is byte-identical after the write" \
   'holds_lines "$(statesnap "$S23")" "$(grep SESSION_HANDOFF <<<"$beforestate23")"'
ok "PI-40 AC4 — no archive file was created: nothing rotates any more" '[[ ! -e "$S23/docs/SESSION_HANDOFF_ARCHIVE.md" ]]'
ok "PI-40 AC4 — all 46 lines are readable (45 frozen + the new one)" '[[ "$(nlines "$(clog "$S23")")" -eq 46 ]]'
ok "PI-40 AC4 — the display window still shows $LOGCAP of them" \
   "[[ \"\$(nlines \"\$(cd \"\$S23\" && bash \"\$SCRIPT\" recent)\")\" -eq $LOGCAP ]]"
ok "PI-40 AC4 — the facts section is byte-identical after the write" '[[ "$(cfacts "$S23")" == "$beforefacts23" ]]'

# AC5 — one definition of where a section begins, used by the composer and by both writers, on the same
# poisoned memory.
S24=$(mkrepo)
mkpoisoned40 "$S24" "${POISONS40[0]}" "una riga di log che c'era già"
awkfacts24=$(fragfacts "$S24"); awklog24=$(fraglog "$S24")
ok "PI-40 AC5 — the composer's facts equal the anchored awk extraction, quote included" '[[ "$(cfacts "$S24")" == "$awkfacts24" ]]'
ok "PI-40 AC5 — the composer's log equals the anchored awk extraction (the quote is not a log line)" '[[ "$(clog "$S24")" == "$awklog24" ]]'
(cd "$S24" && bash "$SCRIPT" fact "un fatto aggiunto dopo la citazione" >/dev/null 2>&1)
ok "PI-40 AC5 — after a fact write, the facts are the old ones plus the new one, in order" \
   '[[ "$(cfacts "$S24")" == "$(printf "%s\n%s" "$awkfacts24" "- un fatto aggiunto dopo la citazione")" ]]'
ok "PI-40 AC5 — after a fact write, the log is byte-identical" '[[ "$(clog "$S24")" == "$awklog24" ]]'

# AC5 mirror — a LOG line quoting the FACTS heading must not become the place a fact is written.
S25=$(mkrepo)
mkdir -p "$S25/docs"
cat > "$S25/docs/SESSION_HANDOFF.md" <<'EOF'
# Session handoff

## Log (più recente in alto, ultime 40 righe)
- 2026-01-01 i fatti stanno sotto ## Fatti che non scadono
- 2026-01-01 una seconda riga di log
EOF
awklog25=$(awk '/^## Log/{f=1;next} /^## /{f=0} f && /^- /' "$S25/docs/SESSION_HANDOFF.md")
(cd "$S25" && bash "$SCRIPT" fact "il fatto nuovo" >/dev/null 2>&1)
ok "PI-40 AC5 mirror — the new fact is readable as a fact" '[[ "$(cfacts "$S25")" == "- il fatto nuovo" ]]'
ok "PI-40 AC5 mirror — the two log lines are still log lines, byte-identical, and the fact is not one" \
   '[[ "$(clog "$S25")" == "$awklog25" ]]'

# --- The writer grid. Dimensions: (a) all three writers; (b) the marker — the generic "^## " a reader
# searches, so a foreign section name and a plain "##" are in the list and no section name is special;
# (c) where the caller's newline puts it: head, middle, tail, or a text that is nothing but a newline and
# a marker. The oracles are the files themselves and the composer, never the code under test. Two of the
# six checks are the non-vacuity siblings of the others: the write really happened, and the caller's
# marker really did reach the disk (as data, on a "- " line).
MARK40=( '## Log' '## Fatti che non scadono' '## Qualunque cosa' '## Log archiviato' '### sottosezione' '##' '   ## indentata' '## Ritirati' )
badstate40=""; badone40=""; badshape40=""; badcomp40=""; badtext40=""; badhead40=""; n40=0
for writer40 in log fact retract; do
  for mi40 in $(seq 0 $((${#MARK40[@]} - 1))); do
    for shape40 in testa mezzo coda solo; do
      marker40="${MARK40[$mi40]}"
      case "$shape40" in
        testa) text40=$(printf '%s\ntesto dopo il marcatore' "$marker40");;
        mezzo) text40=$(printf 'testo prima\n%s\ntesto dopo' "$marker40");;
        coda)  text40=$(printf 'testo prima del marcatore\n%s' "$marker40");;
        solo)  text40=$(printf '\n%s' "$marker40");;
      esac
      D40=$(mkrepo); case40="$writer40/$mi40/$shape40"; n40=$((n40 + 1))
      ( cd "$D40" && bash "$SCRIPT" fact "un fatto che deve sopravvivere" \
        && bash "$SCRIPT" log "keeper uno" && bash "$SCRIPT" log "keeper due" ) >/dev/null 2>&1
      # `retract` only ever writes when the text names a visible fact, so for that writer the text under
      # test is first declared as a fact and then retracted — the poisoned string goes through both.
      if [[ "$writer40" == retract ]]; then
        (cd "$D40" && bash "$SCRIPT" fact "$text40") >/dev/null 2>&1
      fi
      statb40=$(statesnap "$D40"); fragb40=$(fragfiles "$D40"); nb40=$(nfrags "$D40")
      (cd "$D40" && bash "$SCRIPT" "$writer40" "$text40") >/dev/null 2>&1
      new40=$(fragfiles "$D40" | grep -vxF -f <(printf '%s\n' "$fragb40"))
      # (1) nothing that existed was touched; (2) exactly one file is new
      [[ "$(statesnap "$D40" | grep -vxF -f <(printf '%s\n' "$statb40") | grep -c .)" -eq 1 ]] || badstate40="$badstate40 $case40"
      [[ "$(nfrags "$D40")" -eq $((nb40 + 1)) ]] && [[ "$(printf '%s\n' "$new40" | grep -c .)" -eq 1 ]] \
        || badone40="$badone40 $case40"
      # (3) the new file is one heading and one record — two physical lines, no more
      [[ -f "$new40" ]] \
        && [[ "$(grep -c '^## ' "$new40")" -eq 1 ]] \
        && [[ "$(grep -c '^- ' "$new40")" -eq 1 ]] \
        && [[ "$(wc -l < "$new40" | tr -d ' ')" -eq 2 ]] \
        || badshape40="$badshape40 $case40"
      # (4) the heading is the one the writer chose, never one that came from the caller's text
      case "$writer40" in log) want40='## Log';; fact) want40='## Fatti';; retract) want40='## Ritirati';; esac
      [[ -f "$new40" ]] && [[ "$(head -1 "$new40")" == "$want40" ]] || badhead40="$badhead40 $case40"
      # (5) the composer still reads every line back, with the expected counts
      exprec40=2; expfac40=1
      case "$writer40" in log) exprec40=3;; fact) expfac40=2;; retract) expfac40=1;; esac
      [[ "$(nlines "$(clog "$D40")")" -eq "$exprec40" ]] && [[ "$(nlines "$(cfacts "$D40")")" -eq "$expfac40" ]] \
        || badcomp40="$badcomp40 $case40"
      # (6) sibling: the caller's marker really is on disk, as data on a "- " line
      if [[ "$writer40" == retract ]]; then
        grep -rqF -- "$marker40" "$D40/docs/handoff" || badtext40="$badtext40 $case40"
      else
        [[ -f "$new40" ]] && [[ "$(grep -F -- "$marker40" "$new40" | grep -c '^- ')" -ge 1 ]] || badtext40="$badtext40 $case40"
      fi
    done
  done
done
ok "PI-40 F1 — over all $n40 writer×marcatore×posizione combinations, every file that already existed is byte-identical afterwards${badstate40:+ (rotte:$badstate40)}" \
   '[[ -z "$badstate40" ]]'
ok "PI-40 F1 — over all $n40, the write created exactly one new file${badone40:+ (rotte:$badone40)}" '[[ -z "$badone40" ]]'
ok "PI-40 F1 — over all $n40, that file is exactly one heading and one record: what the caller passed is one line, never two${badshape40:+ (rotte:$badshape40)}" \
   '[[ -z "$badshape40" ]]'
ok "PI-40 F1 — over all $n40, the heading is the writer's own, never one carried in by the caller's text${badhead40:+ (rotte:$badhead40)}" \
   '[[ -z "$badhead40" ]]'
ok "PI-40 F1 — over all $n40, the composer still reads every line back (facts and recent --all counts exact)${badcomp40:+ (rotte:$badcomp40)}" \
   '[[ -z "$badcomp40" ]]'
ok "PI-40 F1 — sibling, so none of the above can pass vacuously: in all $n40 the caller's marker IS on disk, as data on a '- ' line${badtext40:+ (rotte:$badtext40)}" \
   '[[ -z "$badtext40" ]]'

# The reproductions from the PI-40 review, on memory built by the writers themselves.
R40=$(mkrepo)
( cd "$R40" && bash "$SCRIPT" log "prima riga" && bash "$SCRIPT" log "seconda riga" ) >/dev/null 2>&1
(cd "$R40" && bash "$SCRIPT" log $'una riga\n## Qualunque cosa\nfine') >/dev/null 2>&1
ok "PI-40 F1 — after a log carrying a FOREIGN heading, recent --all still returns the two earlier lines plus the new one" \
   '[[ "$(nlines "$(clog "$R40")")" -eq 3 ]]'
ok "PI-40 F1 — sibling: that same text is on disk, whole, on one line" \
   '[[ "$(grep -rc "^- .*una riga ## Qualunque cosa fine$" "$R40/docs/handoff" | grep -c ":1")" -eq 1 ]]'
(cd "$R40" && bash "$SCRIPT" fact $'un fatto\n## Log\ncoda del fatto') >/dev/null 2>&1
ok "PI-40 F1 — after a fact carrying the Log heading, no fragment holds two headings" \
   '[[ -z "$(fragfiles "$R40" | while read -r f; do [[ "$(grep -c "^## " "$f")" -eq 1 ]] || echo bad; done)" ]]'
(cd "$R40" && bash "$SCRIPT" log "la riga successiva alla citazione") >/dev/null 2>&1
ok "PI-40 F1 — and the next log line lands in the log without hiding the fact that quotes the marker" \
   '[[ "$(nlines "$(clog "$R40")")" -eq 4 ]] && [[ "$(nlines "$(cfacts "$R40")")" -eq 1 ]]'
# PI-39 still holds, and the ORDER of the two rules is what makes it hold: the caller's newline is
# collapsed BEFORE the leading-date strip looks at the text. Collapsing afterwards would turn
# "2026-01-01\nfoo" into a line carrying two dates — exactly what PI-39 exists to prevent — and the
# fragment path changes nothing about that, because one_line() runs first there too.
(cd "$R40" && bash "$SCRIPT" log $'2026-01-01\nfoo') >/dev/null 2>&1
ok "PI-40 F1 + PI-39 — a caller date followed by a newline is still stripped: one date on the line" \
   'dated "$(head -1 <<<"$(clog "$R40")")" "foo"'
ok "PI-40 F1 + PI-39 — no line on disk carries two consecutive ISO dates" \
   '! grep -rqE "^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{4}-[0-9]{2}-[0-9]{2}" "$R40/docs/handoff"'
ok "PI-40 F1 — ADR-2 holds on the poisoned memory: reading it changes nothing on disk" \
   'st=$(statesnap "$R40"); (cd "$R40" && bash "$SCRIPT" facts >/dev/null && bash "$SCRIPT" recent --all >/dev/null && bash "$SCRIPT" show >/dev/null && bash "$SCRIPT" where >/dev/null) 2>/dev/null; [[ "$st" == "$(statesnap "$R40")" ]]'

# The 10 line-ish characters, writer side: a fact or a log line may hold any of them as DATA. The
# fragment is written once and never reopened, so what the caller passed must come back byte for byte.
for sepname in CRLF CR VT FF FS GS RS NEL LS PS; do
  S26=$(mkrepo)
  sepchar=$(python3 -c "import sys; sys.stdout.write({'CRLF':'\r\n','CR':'\r','VT':'\x0b','FF':'\x0c','FS':'\x1c','GS':'\x1d','RS':'\x1e','NEL':'\x85','LS':' ','PS':' '}['$sepname'])")
  (cd "$S26" && bash "$SCRIPT" fact "fatto a${sepchar}b" >/dev/null 2>&1)
  (cd "$S26" && bash "$SCRIPT" log "riga a${sepchar}b" >/dev/null 2>&1)
  ok "PI-40 writer [$sepname] — the separator survives in the fact, as data, and the fact is whole" \
     '[[ "$(cfacts "$S26")" == "$(fragfacts "$S26")" ]] && [[ "$(nlines "$(cfacts "$S26")")" -eq 1 ]]'
  ok "PI-40 writer [$sepname] — and in the log line, which is still one record" \
     '[[ "$(nlines "$(clog "$S26")")" -eq 1 ]] && [[ "$(clog "$S26")" == "$(fraglog "$S26")" ]]'
  # CRLF and CR are the two that a naive "\n"-only collapse would leave behind as a line break inside
  # the file; every other one is not a line break for awk, python's re.M or this composer.
  ok "PI-40 writer [$sepname] — every fragment still holds exactly one heading and one record" \
     '[[ -z "$(fragfiles "$S26" | while read -r f; do [[ "$(grep -c "^## " "$f")" -eq 1 ]] && [[ "$(grep -ac "^- " "$f")" -eq 1 ]] || echo bad; done)" ]]'
done

# =================================================================================================
# Structural guards — one home for each rule, repo-wide, so PI-43 (retro-due.sh) has somewhere to load
# from instead of making a second copy.
# =================================================================================================
ok "PI-16 — exactly one definition of where a section begins, in the whole repo" \
   '[[ "$(grep -rn "^def split_section(" "$REPO" --exclude-dir=.git | grep -c .)" -eq 1 ]]'
ok "PI-16 — and it lives in the shared module, which handoff.sh loads instead of redefining it" \
   '[[ "$(grep -c "^def split_section(" "$REPO/bin/handoff_sections.py")" -eq 1 ]] && grep -q "handoff_sections.py" "$SCRIPT"'
ok "PI-16 — exactly one definition of what collapses a caller's text into one record" \
   '[[ "$(grep -rn "^def one_line(" "$REPO" --exclude-dir=.git | grep -c .)" -eq 1 ]]'
ok "PI-16 — the shared module is importable on its own, not only by being prepended" \
   'python3 -c "import sys; sys.path.insert(0, \"$REPO/bin\"); import handoff_sections as h; assert h.split_section(\"## Log\nx\", \"Log\")[1] == \"## Log\"; assert h.one_line(\"a\nb\") == \"a b\""'
ok "PI-40 AC5 — no marker is located by substring partition any more (code lines, not the comments about it)" \
   '! grep -qE "^[^#]*\.partition\(\"#" "$SCRIPT" "$REPO/bin/handoff_sections.py"'
ok "PI-40 AC5 — sibling: that same pattern does match the pre-PI-40 form, so the guard is not vacuous" \
   'grep -qE "^[^#]*\.partition\(\"#" <<<"head,sep,tail=s.partition(\"## Log\")"'
# the pattern lives in a variable so the "$" reaches grep as an escaped literal and not as the ERE
# end-of-line anchor it becomes after one round of double-quote expansion
CASEPAT='^[[:space:]]*case[[:space:]]+"?[$]\{?cmd'
ok "PI-14 review — no second list of subcommands: handoff.sh has no bash dispatch on the command" \
   '! grep -qE "$CASEPAT" "$SCRIPT"'
ok "PI-14 review — sibling: that pattern does match the pre-PI-16 dispatch, so the guard is not vacuous" \
   'grep -qE "$CASEPAT" <<<"case \"\$cmd\" in facts|show)"'
ok "PI-16 — every write goes through exclusive creation: no other open-for-write in the script" \
   '[[ "$(grep -c "O_CREAT | os.O_EXCL" "$SCRIPT")" -eq 1 ]] && [[ "$(grep -cE "open\((path|fp|p)[^)]*, *[\"'"'"']w" "$SCRIPT")" -eq 0 ]]'

# =================================================================================================
# PI-16 AC8 — the instructions agents read at startup must describe the new contract. Every line of the
# repo (outside docs/, tech-analysis/ and tasks/) that still names the frozen file must be talking about
# a source that is read, never about where a write goes.
# =================================================================================================
grepout=$(cd "$REPO" && git grep -n "SESSION_HANDOFF" -- ':!docs' ':!tech-analysis' ':!tasks' 2>/dev/null)
# What is allowed to still name the frozen file: the scripts under bin/, which READ it (handoff.sh and
# this test, plus status.sh and retro-due.sh, whose readers PI-43 moves onto the shared module), and
# reviewer.md, which the task's Notes keep out of this change ("Do not touch reviewer.md — a separate
# change is queued"). Everything else is an instruction an agent reads at startup: it may mention the
# file only as the source that is still read, never as the place a write lands.
badlines=$(printf '%s\n' "$grepout" | grep -v '^bin/' | grep -v '^\.claude/agents/reviewer\.md:' \
           | grep -viE "congelat|frozen|legge|letta|letto|read|sorgente|source|storic" | grep -v '^$')
ok "AC8 — every surviving mention outside bin/ says it is a frozen source that is only read${badlines:+ — offending: $(printf '%s' "$badlines" | head -3 | tr '\n' ' ')}" \
   '[[ -z "$badlines" ]]'
ok "AC8 — sibling: the grep really did return lines, so the check above is not vacuous" \
   '[[ "$(printf "%s\n" "$grepout" | grep -c .)" -ge 5 ]]'
forbidden8="prepends|kept to 40|creates docs/SESSION|remove one line by hand|append to docs/SESSION"
ok "AC8 — no instruction still says a write prepends to it, keeps it to 40, creates it or edits it by hand" \
   '! grep -qiE "$forbidden8" <<<"$grepout"'
ok "AC8 — retro.md prunes facts with retract" \
   'grep -qi "retract" "$REPO/.claude/agents/retro.md"'
ok "AC8 — the developer, the shared rules and the skills name handoff.sh, not the file it used to write" \
   'grep -q "handoff.sh log" "$REPO/.claude/agents/developer.md" && grep -q "handoff.sh" "$REPO/.claude/agents/shared/implementing-common.md"'
# The base is `origin/main` when it is there, `main` only as a fallback. A local `main` ref is whatever the
# last `git fetch` of whichever checkout left behind, so a branch that is simply BEHIND its base fails this
# assertion for a file it never touched — measured on this branch: the base moved 34 commits, one of them
# editing reviewer.md, and the assertion went red while the branch's own diff of that file was empty.
BASEREF=$(cd "$REPO" && git rev-parse --verify -q origin/main >/dev/null 2>&1 && echo origin/main || echo main)
ok "AC8 — reviewer.md is untouched by this task (a separate change is queued for it)" \
   '[[ -z "$(cd "$REPO" && git diff "$BASEREF" --name-only -- .claude/agents/reviewer.md 2>/dev/null)" ]]'

# =================================================================================================
# AC8 (coexistence) — this branch and its base each changed the same instructions. The merge has to keep
# BOTH, and that is a property of the text, not of the merge commit: the base brought a RULE (a write
# stays off the feature branches when more than one is open, and is replayed on the base with the tool,
# never by hand) and this task brings a MECHANIC (a write is a new immutable file, so tool writes merge
# as a union). Dropping either side is a silent, plausible-looking resolution — the rule alone leaves an
# agent grepping for a file nothing writes, the mechanic alone re-authorises the hand-written entries
# that corrupted the memory. Each assertion below names the side it protects, and each is checked INSIDE
# the section that owns it, so a sentence surviving somewhere else in the file does not answer for it.
sec6=$(awk '/^## 6\. /,/^## 7\. /' "$REPO/.claude/agents/shared/implementing-common.md")
ok "AC8 coexistence — §6 keeps the base's rule: a write stays off the feature branches" \
   'grep -qF "every write stays off the feature branches" <<<"$sec6"'
ok "AC8 coexistence — §6 keeps the base's rule: the replay is with the tool, never by hand" \
   'grep -qF "never by hand, never reconciled by hand, never rotated by size" <<<"$sec6"'
ok "AC8 coexistence — §6 keeps the base's forward pointer to the task that makes it a refusal" \
   'grep -qF "tasks/PI-52" <<<"$sec6"'
ok "AC8 coexistence — §6 keeps this task's mechanic: one new file per write, under docs/handoff/" \
   'grep -qF "**Every write creates one new file**" <<<"$sec6" && grep -qF "docs/handoff/" <<<"$sec6"'
# The two halves of the mechanic's own scope, one assertion each, anchored on the single sentence that
# states each — never on an alternation. The first version of this check was `grep -qiE "made with the
# tool. now creates a new file|merge as a union"`, and it measured neither half: its first alternative
# matched 0 lines of the real file (the text is `a write **made with the tool** now creates a new file`
# and `.` matches one character, not two asterisks), while `merge as a union` occurs once in EACH of the
# two paragraphs, so either one alone satisfied it. Measured on the real file: deleting the only
# sentence that says what the mechanic does NOT settle left all 8 coexistence assertions green. A
# sentence that can be deleted with the suite green is unguarded, whatever the assertion is named.
ok "AC8 coexistence — §6 says what the mechanic DOES settle: a tool write creates a new file, so parallel branches merge as a union" \
   'grep -qF "made with the tool** now creates a new file" <<<"$sec6" && grep -qF "so parallel branches merge as a union" <<<"$sec6"'
ok "AC8 coexistence — §6 says what the mechanic does NOT settle: by hand, the memory is corrupted exactly as before" \
   'grep -qF "They remove nothing of the other half" <<<"$sec6" && grep -qF "corrupt the memory exactly as before" <<<"$sec6"'
ok "AC8 coexistence — sibling: the §6 extraction really returned the section, so the checks are not vacuous" \
   '[[ "$(grep -c . <<<"$sec6")" -ge 8 ]] && grep -qF "## 6. Branch, commit, PR" <<<"$sec6"'
row=$(grep -F "| Learning loop |" "$REPO/CLAUDE.md")
ok "AC8 coexistence — the learning-loop row keeps the base's lesson promotion and this task's facts source" \
   '[[ -n "$row" ]] && grep -qF "docs/handoff/" <<<"$row" && grep -qiE "promot" <<<"$row" && ! grep -qF "SESSION_HANDOFF" <<<"$row"'
# The front matter is taken by its own delimiters, never by a line count: a line range is an anchor any
# edit to the block above it invalidates in silence, and the block it is meant to name is the YAML one
# between the first two `---` lines. The sibling below proves the extraction really returned it.
front=$(awk 'NR==1 && $0=="---"{inb=1;next} inb && $0=="---"{exit} inb' "$REPO/.claude/agents/retro.md")
ok "AC8 coexistence — sibling: the retro.md front-matter extraction really returned the YAML block" \
   'grep -qE "^name: retro$" <<<"$front" && grep -qE "^description: " <<<"$front"'
# Same repair as the pair above, applied to this one before it could become the next false-coverage row:
# it read `grep -qiE "method lessons|lesson"`, and the second alternative subsumes the first, so the
# alternation could only ever be satisfied by the weaker of the two. The base's side is named literally —
# the method lessons AND their automatic promotion — and this branch's side stays the frozen-file absence.
ok "AC8 coexistence — retro.md's front matter keeps the base's method lessons and their promotion, and names no frozen file" \
   'grep -qF "method lessons" <<<"$front" && grep -qiE "promot" <<<"$front" && ! grep -qF "SESSION_HANDOFF" <<<"$front"'

[[ "$fail" -eq 0 ]] && echo "handoff.test.sh: all ok" || echo "handoff.test.sh: FAILURES"
exit "$fail"
