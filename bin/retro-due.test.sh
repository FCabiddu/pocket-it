#!/usr/bin/env bash
# Self-test for retro-due.sh (PI-35).
# AC1: output/exit contract — "RETRO DUE: <n> segnali" + one line per signal / exit 10;
#      "retro-due: nothing" / exit 0 with no signals; exit 2 on input error (not a git repo).
# AC2: one positive + one negative fixture per signal type — (a) needs-work cause != first-round,
#      (b) same cause on two different tasks, (c) a task reaching three needs-work lines, (d) BUDGET/STALL.
# AC3: a retro-mark line hides every line before it (mid-log, and across the archive boundary); without
#      any mark, the same lines count.
# AC4: read-only — git status --porcelain is byte-identical before and after, including from a project
#      root with no docs/ directory at all.
# AC5/AC6: run-wave/SKILL.md, quickfix/SKILL.md and retro.md carry the wiring this script is read by.
# Round 2 (review findings 1-5): F1 the mark is recognised only in its exact anchored shape, never a
# mention of the word in prose/a log line/a needs-work line; F2 BUDGET/STALL/needs-work are anchored to
# their real log shape, so a skill's own closing log line never doubles as a review round; F3 a cause
# value stops at the first em-dash, so "cause: X — fix at: A" and "cause: X — fix at: B" compare equal;
# F4 every input error (bad args, an unreadable source, a malformed main file, a composer that fails)
# exits 2, never 0/1; F5 run-wave/quickfix never launch a second retro while one is already open, and
# retro.md declares the Signals: input, its {scope} value, and writes the mark even without a PR.
# QF-1: a cause is a property of the finding, not of the verdict — the cause field is read off ANY log
# line, so one named inside an approval signals on the same terms as one named in a rework (present, not
# first-round). Its three blocks below take their case lists from declarations, never from examples: the
# taxonomy from reviewer.md's own prose and its two log templates (compared with each other for drift),
# the outcome words from this project's real log + archive at run time. The needs-work anchor stays
# exactly as it was and now governs only the round count and the signal's provenance label, so the
# R3F2/F2 negatives assert the signal TYPE rather than the absence of a line.
set -uo pipefail
cd "$(dirname "$0")"
SCRIPT="$PWD/retro-due.sh"
fail=0
ok(){ if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null

# mkrepo DIR — a fresh git repo, resolved absolute (macOS /tmp is a symlink)
mkrepo(){
  local d; d=$(mktemp -d "${TMPDIR:-/tmp}/retro-due-test.XXXXXX"); d=$(cd "$d" && pwd -P)
  git init -q "$d" >/dev/null
  printf '%s' "$d"
}

# writelog DIR "line1" "line2" ... — writes docs/SESSION_HANDOFF.md with a "## Log" section holding the
# given lines in the given order (first argument after DIR is the top of the file, i.e. the newest one).
writelog(){
  local d="$1"; shift
  mkdir -p "$d/docs"
  { echo "# Session handoff"; echo; echo "## Fatti che non scadono"; echo
    echo "## Log (più recente in alto, ultime 40 righe)"
    for l in "$@"; do echo "$l"; done
  } > "$d/docs/SESSION_HANDOFF.md"
}

# writearchive DIR "line1" "line2" ... — oldest first, as the real archive file is written
writearchive(){
  local d="$1"; shift
  mkdir -p "$d/docs"
  { echo "# Session handoff — archive"; echo; echo "## Log archiviato"
    for l in "$@"; do echo "$l"; done
  } > "$d/docs/SESSION_HANDOFF_ARCHIVE.md"
}

run(){ (cd "$1" && bash "$SCRIPT"); }

# mkscript MODE — a private bin/ dir holding our own copy of retro-due.sh plus a crafted sibling
# handoff.sh, so a test can control composer behaviour without touching the real bin/handoff.sh (PI-14).
# MODE composer-fail: declares composer support (facts|show|recent|grep) but every call fails.
# MODE no-composer: log/fact/show only, like a pre-PI-14 install — proves the AC4 fallback path directly,
# now that the real sibling handoff.sh always has a composer and would otherwise never exercise it.
mkscript(){
  local mode="$1" d
  d=$(mktemp -d "${TMPDIR:-/tmp}/retro-due-bin.XXXXXX"); d=$(cd "$d" && pwd -P)
  cp "$SCRIPT" "$d/retro-due.sh"
  case "$mode" in
    composer-fail)
      cat > "$d/handoff.sh" <<'EOF'
#!/usr/bin/env bash
case "${1:-show}" in
  facts|show|recent|grep) echo "boom" >&2; exit 1;;
  *) exit 0;;
esac
EOF
      ;;
    no-composer)
      cat > "$d/handoff.sh" <<'EOF'
#!/usr/bin/env bash
case "${1:-show}" in
  log|fact|show) exit 0;;
  *) echo "usage: handoff.sh log|fact|show" >&2; exit 2;;
esac
EOF
      ;;
  esac
  printf '%s' "$d"
}

# --- AC1: no file at all -> nothing, exit 0 ---
S1=$(mkrepo)
out1=$(run "$S1"); rc1=$?
ok "AC1 — no handoff file: exact output" '[[ "$out1" == "retro-due: nothing" ]]'
ok "AC1 — no handoff file: exit 0" '[[ "$rc1" -eq 0 ]]'
rm -rf "$S1"

# --- AC1: one clean signal -> exact header + line shape, exit 10 ---
S2=$(mkrepo)
writelog "$S2" "- 2026-09-01 BUDGET PI-40 ~250 turns vs 200 — progressing: 4 commits, 2 tests green — bigger scope"
out2=$(run "$S2"); rc2=$?
expected2=$(printf 'RETRO DUE: 1 segnali\nPI-40 — budget — 2026-09-01 BUDGET PI-40 ~250 turns vs 200 — progressing: 4 commits, 2 tests green — bigger scope')
ok "AC1 — one signal: header names the count" '[[ "$out2" == "$expected2" ]]'
ok "AC1 — one signal: exit 10" '[[ "$rc2" -eq 10 ]]'
rm -rf "$S2"

# --- AC1: input error, not a git repository at all -> exit 2 ---
S3=$(mktemp -d "${TMPDIR:-/tmp}/retro-due-test.XXXXXX")
out3=$(cd "$S3" && bash "$SCRIPT" 2>&1); rc3=$?
ok "AC1 — not a git repo: exit 2" '[[ "$rc3" -eq 2 ]]'
ok "AC1 — not a git repo: says so" '[[ "$out3" == *"not a git repository"* ]]'
rm -rf "$S3"

# --- AC2(a) positive: a needs-work line with a real cause is a signal; negative: first-round, and no
# cause at all, are not (isolated on other tasks so they cannot also trip (b)/(c)) ---
S4=$(mkrepo)
writelog "$S4" \
  "- 2026-09-03 PI-1 PR #1 needs work — reason — cause: example-not-class" \
  "- 2026-09-02 PI-2 PR #2 needs work — reason — cause: first-round" \
  "- 2026-09-01 PI-3 PR #3 needs work — reason with no cause field at all"
out4=$(run "$S4")
ok "AC2a positive — cause != first-round is a signal" 'grep -qE "^PI-1 — needs-work-cause —" <<<"$out4"'
ok "AC2a negative — cause: first-round alone is not a signal" '! grep -q "PI-2" <<<"$out4"'
ok "AC2a negative — a needs-work line with no cause field is not a signal" '! grep -q "PI-3" <<<"$out4"'
ok "AC2a — exactly one signal in this fixture" '[[ "$out4" == "RETRO DUE: 1 segnali"* ]]'
rm -rf "$S4"

# --- AC2(b) positive: the same cause recurs on two different tasks -> the second task's line is flagged
# same-cause; negative: the same cause repeating within ONE task's own rounds is not ---
S5=$(mkrepo)
writelog "$S5" \
  "- 2026-09-02 PI-11 PR #11 needs work — reason — cause: example-not-class" \
  "- 2026-09-01 PI-10 PR #10 needs work — reason — cause: example-not-class"
out5=$(run "$S5")
ok "AC2b positive — cause recurring on a different task is flagged" 'grep -qE "^PI-11 — same-cause —" <<<"$out5"'
ok "AC2b positive — the first task carrying that cause is not itself flagged same-cause" '! grep -qE "^PI-10 — same-cause —" <<<"$out5"'
rm -rf "$S5"

S5b=$(mkrepo)
writelog "$S5b" \
  "- 2026-09-02 PI-12 PR #12 needs work round 2 — reason — cause: example-not-class" \
  "- 2026-09-01 PI-12 PR #12 needs work — reason — cause: example-not-class"
out5b=$(run "$S5b")
ok "AC2b negative — same task, same cause across its own rounds: no same-cause signal" '! grep -q "same-cause" <<<"$out5b"'
ok "AC2b negative — both rounds still count as needs-work-cause" '[[ "$out5b" == "RETRO DUE: 2 segnali"* ]]'
rm -rf "$S5b"

# --- AC2(c) positive: a task reaching 3 needs-work lines is signalled once, at the third; negative: 2
# lines is not enough. Causes kept at first-round throughout so only (c) is exercised. ---
S6=$(mkrepo)
writelog "$S6" \
  "- 2026-09-03 PI-20 PR #20 needs work round 3 — reason — cause: first-round" \
  "- 2026-09-02 PI-20 PR #20 needs work round 2 — reason — cause: first-round" \
  "- 2026-09-01 PI-20 PR #20 needs work — reason — cause: first-round"
out6=$(run "$S6")
ok "AC2c positive — third needs-work line for one task is signalled" '[[ "$out6" == "RETRO DUE: 1 segnali"* ]] && grep -qE "^PI-20 — repeat-needs-work —.*round 3" <<<"$out6"'
rm -rf "$S6"

S6b=$(mkrepo)
writelog "$S6b" \
  "- 2026-09-02 PI-21 PR #21 needs work round 2 — reason — cause: first-round" \
  "- 2026-09-01 PI-21 PR #21 needs work — reason — cause: first-round"
out6b=$(run "$S6b")
ok "AC2c negative — two needs-work lines is not enough" '[[ "$out6b" == "retro-due: nothing" ]]'
rm -rf "$S6b"

# --- AC2(d) positive: a BUDGET line and a STALL line are each a signal; negative: the words "budget"/
# "stall" in ordinary lowercase prose are not (case- and word-sensitive, not a substring match) ---
S7=$(mkrepo)
writelog "$S7" \
  "- 2026-09-03 PI-31 PR #31 needs work — mentions budget and stall informally — cause: first-round" \
  "- 2026-09-02 STALL PI-30 ~140 turns — stuck on the same error" \
  "- 2026-09-01 BUDGET PI-29 ~260 turns vs 200 — progressing: 3 commits, 1 test green — bigger scope"
out7=$(run "$S7")
ok "AC2d positive — BUDGET line is a signal" 'grep -qE "^PI-29 — budget —" <<<"$out7"'
ok "AC2d positive — STALL line is a signal" 'grep -qE "^PI-30 — stall —" <<<"$out7"'
ok "AC2d negative — lowercase 'budget'/'stall' in prose is not a signal" '! grep -q "PI-31" <<<"$out7"'
ok "AC2d — exactly two signals in this fixture" '[[ "$out7" == "RETRO DUE: 2 segnali"* ]]'
rm -rf "$S7"

# --- AC3: a retro-mark line hides everything before it; the same log without the mark counts it all ---
S8=$(mkrepo)
writelog "$S8" \
  "- 2026-09-10 STALL PI-51 ~90 turns — stuck" \
  "- 2026-09-05 retro-mark 2026-09-05 EPIC-9" \
  "- 2026-09-01 PI-50 PR #50 needs work — old, before the mark — cause: example-not-class"
out8=$(run "$S8")
ok "AC3 mid-log mark — the line after the mark still counts" 'grep -q "PI-51" <<<"$out8"'
ok "AC3 mid-log mark — the line before the mark is hidden" '! grep -q "PI-50" <<<"$out8"'
ok "AC3 mid-log mark — exactly one signal survives" '[[ "$out8" == "RETRO DUE: 1 segnali"* ]]'
rm -rf "$S8"

# same shape, but the pre-mark line lives in the archive (oldest overall) — exercises the composed
# chronological order (archive, then main log) rather than a single file
S8b=$(mkrepo)
writearchive "$S8b" "- 2026-08-01 PI-50 PR #50 needs work — old, before the mark — cause: example-not-class"
writelog "$S8b" \
  "- 2026-09-10 STALL PI-51 ~90 turns — stuck" \
  "- 2026-09-05 retro-mark 2026-09-05 EPIC-9"
out8b=$(run "$S8b")
ok "AC3 archive+mark — the archived pre-mark line is hidden" '! grep -q "PI-50" <<<"$out8b"'
ok "AC3 archive+mark — the post-mark line still counts" '[[ "$out8b" == "RETRO DUE: 1 segnali"* ]] && grep -q "PI-51" <<<"$out8b"'
rm -rf "$S8b"

# no mark at all in an otherwise identical log -> both lines count
S8c=$(mkrepo)
writelog "$S8c" \
  "- 2026-09-10 STALL PI-51 ~90 turns — stuck" \
  "- 2026-09-01 PI-50 PR #50 needs work — reason — cause: example-not-class"
out8c=$(run "$S8c")
ok "AC3 no mark — both lines count" '[[ "$out8c" == "RETRO DUE: 2 segnali"* ]] && grep -q "PI-50" <<<"$out8c" && grep -q "PI-51" <<<"$out8c"'
rm -rf "$S8c"

# --- AC4: read-only, from a project root with no docs/ directory at all ---
S9=$(mkrepo)
before9=$(cd "$S9" && git status --porcelain)
out9=$(run "$S9")
after9=$(cd "$S9" && git status --porcelain)
ok "AC4 — output is 'nothing' from a root with no docs/" '[[ "$out9" == "retro-due: nothing" ]]'
ok "AC4 — git status unchanged (no docs/ at all)" '[[ "$before9" == "$after9" ]]'
ok "AC4 — no docs/ directory was created" '[[ ! -d "$S9/docs" ]]'
rm -rf "$S9"

# same check with a populated log, so the read path that actually opens files is covered too
S10=$(mkrepo)
writelog "$S10" "- 2026-09-01 BUDGET PI-60 ~210 turns vs 200 — progressing: 1 commit, 1 test green — bigger scope"
before10=$(cd "$S10" && git status --porcelain)
run "$S10" >/dev/null
after10=$(cd "$S10" && git status --porcelain)
ok "AC4 — git status unchanged with a real log present" '[[ "$before10" == "$after10" ]]'
rm -rf "$S10"

# --- F1 (round 2): the mark is recognised only in its exact anchored shape, never a mention of the word
# in a log line's own prose, a needs-work line, or a PR-title-shaped line ---
S11=$(mkrepo)
writelog "$S11" \
  "- 2026-09-13 PI-35 PR #66 draft — retro-due.sh signal script, run-wave/quickfix trigger, retro-mark write — 34 tests" \
  "- 2026-09-05 PI-99 PR #99 needs work — mentions retro-mark in passing — cause: example-not-class" \
  "- 2026-09-01 PI-50 PR #50 needs work — an older, unrelated signal — cause: base-moved" \
  "- 2026-08-20 QF-9 PR #12 merged — retro-mark: flow-errors"
out11=$(run "$S11")
ok "F1 negative — retro-mark mentioned in a log line's own prose is not a mark (older signal survives)" 'grep -q "PI-50" <<<"$out11"'
ok "F1 negative — retro-mark mentioned inside a needs-work line is not a mark, and the line itself still signals" 'grep -qE "^PI-99 — needs-work-cause —" <<<"$out11"'
ok "F1 negative — a PR-title-shaped mention ('retro-mark: {scope}') is not a mark either" '! grep -q "QF-9" <<<"$out11"'
ok "F1 — nothing before any of these prose mentions is hidden" '[[ "$out11" == "RETRO DUE: 2 segnali"* ]]'
rm -rf "$S11"

# --- F2 (round 2): BUDGET/STALL/needs-work anchored to their real log shape ---
S12=$(mkrepo)
writelog "$S12" "- 2026-09-01 PI-40 PR #70 draft — script reads BUDGET and STALL lines"
out12=$(run "$S12")
ok "F2 negative — BUDGET/STALL named in an unrelated line's own prose is not a signal" '[[ "$out12" == "retro-due: nothing" ]]'
rm -rf "$S12"

S13=$(mkrepo)
writelog "$S13" \
  "- 2026-09-06 QF-9 PR #12 needs-work — round 3 title" \
  "- 2026-09-05 QF-9 PR #12 needs work round 3 — real reviewer round — cause: example-not-class" \
  "- 2026-09-04 QF-9 PR #12 needs-work — round 2 title" \
  "- 2026-09-03 QF-9 PR #12 needs work round 2 — real reviewer round — cause: example-not-class" \
  "- 2026-09-02 QF-9 PR #12 needs-work — round 1 title" \
  "- 2026-09-01 QF-9 PR #12 needs work — real reviewer round — cause: first-round"
out13=$(run "$S13")
ok "F2 negative — a skill's own hyphenated 'needs-work' closing line never counts as a review round" \
   'grep -qE "^QF-9 — repeat-needs-work —.*round 3.*example-not-class" <<<"$out13"'
ok "F2 — exactly 3 signals (2 needs-work-cause + 1 repeat), not inflated by the 3 closing lines" \
   '[[ "$out13" == "RETRO DUE: 3 segnali"* ]]'
rm -rf "$S13"

# --- R3F1 (round 3): the cause field is read only from its own " — cause: …" position, never the first
# "cause:"-shaped substring on the line ("because:", "root cause:", or a mention earlier in the free text)
S20=$(mkrepo)
writelog "$S20" \
  "- 2026-09-03 PI-51 PR #81 needs work — rosso because: trap tardi — cause: first-round" \
  "- 2026-09-02 PI-52 PR #82 needs work — root cause: base mossa — cause: first-round" \
  "- 2026-09-01 PI-53 PR #83 needs work — because: x — cause: example-not-class"
out20=$(run "$S20")
ok "R3F1 negative — 'because:' embedded earlier in the line is not read as the cause field" '! grep -q "PI-51" <<<"$out20"'
ok "R3F1 negative — 'root cause:' (no leading em-dash of its own) is not read as the cause field" '! grep -q "PI-52" <<<"$out20"'
ok "R3F1 positive — the real trailing '— cause:' field is read even after an earlier 'because:' mention" \
   'grep -qE "^PI-53 — needs-work-cause —" <<<"$out20"'
ok "R3F1 — exactly one signal in this fixture" '[[ "$out20" == "RETRO DUE: 1 segnali"* ]]'
rm -rf "$S20"

# a Facts-section line mentioning "cause:"/"needs work" as ordinary words is never read at all — the Log
# section is a hard boundary, so it cannot leak a false positive or hide a real one
S21=$(mkrepo)
mkdir -p "$S21/docs"
HF21="$S21/docs/SESSION_HANDOFF.md"
cat > "$HF21" <<'EOF'
# Session handoff

## Fatti che non scadono
- a fact mentioning cause: something and needs work as ordinary words, never a log signal

## Log (più recente in alto, ultime 40 righe)
- 2026-09-01 PI-55 PR #85 needs work — reason — cause: example-not-class
EOF
out21=$(cd "$S21" && bash "$SCRIPT")
ok "R3F1 — a fact mentioning 'cause:'/'needs work' never affects the Log-derived signal" \
   '[[ "$out21" == "RETRO DUE: 1 segnali"* ]] && grep -q "PI-55" <<<"$out21"'
rm -rf "$S21"

# --- R3F2 (round 3) + QF1: the needs-work outcome must be the word right after "PR #<n>" itself, in one
# of its real qualified forms — not merely present somewhere before the next em-dash on the same line.
# Positive: every real form from the log (implementing-common.md / reviewer.md); negative: "needs work"
# named in another outcome's own free text (approved/re-review/merged/draft).
# Since QF-1 the discriminator is the signal TYPE, not the absence of a line: every line here carries a
# real "— cause: …" field of its own, so a false form now signals as a plain "cause" (correct — a cause
# is read off any line, whatever its outcome word) and must never signal as "needs-work-cause", which is
# what being read as a review ROUND looks like. Absence could not tell "not a round" from "a round with
# no cause"; the type can, and it keeps the negative load-bearing after the widening.
S22=$(mkrepo)
writelog "$S22" \
  "- 2026-09-10 PI-93 PR #93 draft — needs work fixes applied — 3 tests — cause: other: fake93" \
  "- 2026-09-09 PI-92 PR #92 merged after needs work — ok — cause: other: fake92" \
  "- 2026-09-08 PI-91 PR #91 re-review after needs work fixed — ok — cause: other: fake91" \
  "- 2026-09-07 PI-90 PR #90 approved (delta 3, 2 needs work closed) — merge: orchestrator — cause: other: fake90" \
  "- 2026-09-06 PI-66 PR #66 needs work (delta) — reason — cause: other: r7" \
  "- 2026-09-06 PI-65 PR #65 delta needs work round 2 — reason — cause: other: r6" \
  "- 2026-09-05 PI-64 PR #64 delta needs work — reason — cause: other: r5" \
  "- 2026-09-04 PI-63 PR #63 needs work round 2 delta — reason — cause: other: r4" \
  "- 2026-09-03 PI-62 PR #62 needs work round 2 — reason — cause: other: r3" \
  "- 2026-09-02 PI-61 PR #61 needs work (delta 2) — reason — cause: other: r2" \
  "- 2026-09-01 PI-60 PR #60 needs work — reason — cause: other: r1"
out22=$(run "$S22")
ok "R3F2 positive — plain 'PR #n needs work'"               'grep -qE "^PI-60 — needs-work-cause —" <<<"$out22"'
ok "R3F2 positive — 'PR #n needs work (delta n)'"           'grep -qE "^PI-61 — needs-work-cause —" <<<"$out22"'
ok "R3F2 positive — 'PR #n needs work round n'"              'grep -qE "^PI-62 — needs-work-cause —" <<<"$out22"'
ok "R3F2 positive — 'PR #n needs work round n delta'"        'grep -qE "^PI-63 — needs-work-cause —" <<<"$out22"'
ok "R3F2 positive — 'PR #n delta needs work'"                 'grep -qE "^PI-64 — needs-work-cause —" <<<"$out22"'
ok "R3F2 positive — 'PR #n delta needs work round n'"         'grep -qE "^PI-65 — needs-work-cause —" <<<"$out22"'
ok "R3F2 positive — 'PR #n needs work (delta)' with no number"  'grep -qE "^PI-66 — needs-work-cause —" <<<"$out22"'
# each false form also carries a real "— cause: …" field of its own: read as a review round it would be
# typed "needs-work-cause", read as what it is it is typed "cause". Asserting the TYPE (not the absence
# of the line) is what keeps these negatives load-bearing now that a cause is read off any line —
# an absent line alone cannot tell "correctly not a round" apart from "a round with no cause".
ok "R3F2 negative — 'approved (… 2 needs work closed)' is not a review round" '! grep -qE "^PI-90 — needs-work-cause —" <<<"$out22"'
ok "R3F2 negative — 're-review after needs work fixed' is not a review round" '! grep -qE "^PI-91 — needs-work-cause —" <<<"$out22"'
ok "R3F2 negative — 'merged after needs work' is not a review round" '! grep -qE "^PI-92 — needs-work-cause —" <<<"$out22"'
ok "R3F2 negative — a draft line's own 'needs work fixes' mention is not a review round" '! grep -qE "^PI-93 — needs-work-cause —" <<<"$out22"'
ok "R3F2/QF1 positive — those same four lines are still signals, by their own cause field" \
   'grep -qE "^PI-90 — cause —" <<<"$out22" && grep -qE "^PI-91 — cause —" <<<"$out22" && grep -qE "^PI-92 — cause —" <<<"$out22" && grep -qE "^PI-93 — cause —" <<<"$out22"'
ok "R3F2 — exactly the 7 real forms are read as rounds, the 4 false ones as plain causes, nothing else" \
   '[[ "$out22" == "RETRO DUE: 11 segnali"* ]] && [[ $(grep -cE "^[A-Za-z0-9.-]+ — needs-work-cause — " <<<"$out22") -eq 7 ]] && [[ $(grep -cE "^[A-Za-z0-9.-]+ — cause — " <<<"$out22") -eq 4 ]]'
rm -rf "$S22"

# the same false forms, all three on ONE task: read as rounds they would reach the third-round signal.
# Its sibling — three REAL rounds on one task producing exactly that signal — is the AC2(c) fixture above.
S22b=$(mkrepo)
writelog "$S22b" \
  "- 2026-09-03 PI-95 PR #95 approved (delta 3, 2 needs work closed) — merge: orchestrator — cause: other: f3" \
  "- 2026-09-02 PI-95 PR #95 re-review after needs work fixed — ok — cause: other: f2" \
  "- 2026-09-01 PI-95 PR #95 needs-work — a skill's own closing line — cause: other: f1"
out22b=$(run "$S22b")
ok "R3F2 — three false forms on one task never reach the third-round signal" '! grep -q "repeat-needs-work" <<<"$out22b"'
ok "R3F2 — and each of the three is still counted once, as its own cause" \
   '[[ "$out22b" == "RETRO DUE: 3 segnali"* ]] && [[ $(grep -cE "^[A-Za-z0-9.-]+ — cause — " <<<"$out22b") -eq 3 ]]'
rm -rf "$S22b"

# --- R4F1 (round 4): the needs-work qualifier forms are derived from THIS project's own real log +
# archive at test time, never a hand-copied example list again — round 3's own list (copied from the
# reviewer's examples) missed the real form "needs work (delta)" with no number, present 3 times in this
# project's own history. Classification reuses the SCRIPT'S OWN compiled NEEDS_WORK_RE (exec'd from the
# script's embedded python body with harmless argv) rather than a second regex written by hand here,
# which could itself drift from the real one the same way the reviewer.md template already had.
REAL_NEEDS_WORK=$(bash ../bin/handoff.sh recent --all 2>/dev/null | grep -E 'PR #[0-9]+.*needs work')
real_count=$(printf '%s\n' "$REAL_NEEDS_WORK" | grep -c . || true)
ok "R4F1 setup — this project's own log/archive has real needs-work lines to test against (not vacuous)" \
   '[[ "$real_count" -gt 0 ]]'
classify_real=$(python3 - "$SCRIPT" "$REAL_NEEDS_WORK" <<'PY'
import sys, re, io, contextlib
script_path, lines_blob = sys.argv[1], sys.argv[2]
body = re.search(r"<<'PY'\n(.*?)\nPY\n", open(script_path).read(), re.S).group(1)
ns = {}
sys.argv = ["retro-due.sh", "/nonexistent-root-for-test", "/nonexistent-handoff-for-test"]
try:
    with contextlib.redirect_stdout(io.StringIO()):   # run()'s own "retro-due: nothing"/exit never leaks
        exec(compile(body, "retro-due-embedded", "exec"), ns)
except SystemExit:
    pass
NEEDS_WORK_RE = ns["NEEDS_WORK_RE"]
unrecognised = [l for l in lines_blob.split("\n") if l and not NEEDS_WORK_RE.match(l)]
print(("UNRECOGNISED:\n" + "\n".join(unrecognised)) if unrecognised else "ALL RECOGNISED")
PY
)
ok "R4F1 — every real 'PR #n … needs work …' line in this project's own log/archive is recognised" \
   '[[ "$classify_real" == "ALL RECOGNISED" ]]'
[[ "$classify_real" != "ALL RECOGNISED" ]] && echo "$classify_real"

# --- R4F2 (round 4): the reviewer's own NEEDS WORK log template (reviewer.md:142) is read as a signal —
# the template line is taken from the file itself, not hand-copied here, so the producer (reviewer.md)
# and this consumer (retro-due.sh) are checked against the same text and can never drift apart again.
TEMPLATE=$(grep -oE '\{ID\} PR #\{N\} needs work\{ \(delta N\)\} — \{first finding, six words\} — cause: \{[^}]*\}' ../.claude/agents/reviewer.md)
ok "R4F2 setup — the exact template line is present in reviewer.md (not hand-copied here)" '[[ -n "$TEMPLATE" ]]'

instantiate(){ # instantiate ID N DELTA_SUFFIX CAUSE — fills the extracted template, nothing hand-built
  local id="$1" n="$2" delta="$3" cause="$4" line="$TEMPLATE"
  line="${line/\{ID\}/$id}"
  line="${line/\{N\}/$n}"
  line="${line/\{ (delta N)\}/$delta}"
  line="${line/\{first finding, six words\}/a short finding description}"
  # the cause alternation is the only {…} group left at this point, so it is cut generically: a
  # hand-copied copy of it here went stale the moment the taxonomy gained a value (QF-1), and the
  # instantiated line then carried the literal placeholder as its cause — which still signalled, so
  # three of these assertions stayed green on a fixture that no longer tested anything.
  line="${line%%\{*}$cause"
  printf -- '- 2026-09-01 %s' "$line"
}

# the values come from the template's own alternation too, so a taxonomy value added to reviewer.md is
# exercised here the day it is declared, and never because this file happens to quote it
TAXONOMY=$(printf '%s' "$TEMPLATE" | python3 -c 'import sys,re; m=re.search(r"cause: \{([^}]*)\}", sys.stdin.read()); print("\n".join(v.strip() for v in m.group(1).split("|")) if m else "")')
ok "R4F2 setup — the taxonomy is derived from the template, not quoted here (>= 4 values)" \
   '[[ $(printf "%s\n" "$TAXONOMY" | grep -c .) -ge 4 ]]'

while IFS= read -r cause; do
  [ -n "$cause" ] || continue
  [ "$cause" = "first-round" ] && continue          # its own negative assertion follows the loop
  case "$cause" in other*) cause="other: something specific";; esac
  Sx=$(mkrepo)
  writelog "$Sx" "$(instantiate PI-80 80 '' "$cause")"
  outx=$(run "$Sx")
  ok "R4F2 — the template instantiated with cause: $cause is read as a signal" \
     '[[ "$outx" == "RETRO DUE: 1 segnali"* ]] && grep -qE "^PI-80 — needs-work-cause — " <<<"$outx"'
  rm -rf "$Sx"
done <<<"$TAXONOMY"

Sfr=$(mkrepo)
writelog "$Sfr" "$(instantiate PI-81 81 '' "first-round")"
outfr=$(run "$Sfr")
ok "R4F2 — the template instantiated with cause: first-round alone is not a signal (unchanged convention)" \
   '[[ "$outfr" == "retro-due: nothing" ]]'
rm -rf "$Sfr"

Sdelta=$(mkrepo)
writelog "$Sdelta" "$(instantiate PI-82 82 ' (delta 2)' "example-not-class")"
outdelta=$(run "$Sdelta")
ok "R4F2 — the template's optional '(delta N)' qualifier still reads as a signal" \
   '[[ "$outdelta" == "RETRO DUE: 1 segnali"* ]]'
rm -rf "$Sdelta"

# --- F3 (round 2): a cause value stops at the first em-dash, so "cause: X — fix at: A" and
# "cause: X — fix at: B" are recognised as the same cause ---
S14=$(mkrepo)
writelog "$S14" \
  "- 2026-09-02 PI-9 PR #9 needs work — reason — cause: example-not-class — fix at: developer prompt" \
  "- 2026-09-01 PI-8 PR #8 needs work — reason — cause: example-not-class — fix at: task file"
out14=$(run "$S14")
ok "F3 — same cause recognised across different 'fix at' suffixes" 'grep -qE "^PI-9 — same-cause —" <<<"$out14"'
rm -rf "$S14"

# --- F4 (round 2): every input error is exit 2, never a silent "nothing"/exit 0 or a bare crash/exit 1 ---
S15=$(mkrepo)
out15=$(cd "$S15" && bash "$SCRIPT" --bogus 2>&1); rc15=$?
ok "F4a — a bogus argument is an input error, not nothing" '[[ "$rc15" -eq 2 ]]'
rm -rf "$S15"

S16=$(mkrepo)
mkdir -p "$S16/docs/SESSION_HANDOFF.md"   # a directory where a file is expected
out16=$(cd "$S16" && bash "$SCRIPT" 2>&1); rc16=$?
ok "F4b — an unreadable (directory) handoff file is an input error, not nothing" '[[ "$rc16" -eq 2 ]]'
rm -rf "$S16"

S17=$(mkrepo)
mkdir -p "$S17/docs"
printf '# Session handoff\n\n## Fatti che non scadono\n- a fact, no Log section at all\n' > "$S17/docs/SESSION_HANDOFF.md"
out17=$(cd "$S17" && bash "$SCRIPT" 2>&1); rc17=$?
ok "F4c — a handoff file with no '## Log' section is an input error, not nothing" '[[ "$rc17" -eq 2 ]]'
rm -rf "$S17"

S18=$(mkrepo)
writelog "$S18" "- 2026-09-01 BUDGET PI-70 ~210 turns vs 200 — progressing: 1 commit, 1 test green — bigger scope"
BINF=$(mkscript composer-fail)
out18=$(cd "$S18" && bash "$BINF/retro-due.sh" 2>&1); rc18=$?
ok "F4d — a declared composer that fails is an input error, not a silent fallback" '[[ "$rc18" -eq 2 ]]'
rm -rf "$S18" "$BINF"

# AC4 fallback, exercised directly: the real sibling handoff.sh always has a composer now (PI-14 merged),
# so without this fixture the fallback path in read_log_fallback() would never run in this suite again.
S19=$(mkrepo)
writelog "$S19" "- 2026-09-01 BUDGET PI-71 ~210 turns vs 200 — progressing: 1 commit, 1 test green — bigger scope"
BINN=$(mkscript no-composer)
out19=$(cd "$S19" && bash "$BINN/retro-due.sh"); rc19=$?
ok "AC4 fallback — still exercised directly when the sibling handoff.sh has no composer" \
   '[[ "$rc19" -eq 10 ]] && grep -q "PI-71" <<<"$out19"'
rm -rf "$S19" "$BINN"

# --- QF1 (AC1/AC2/AC5): a cause is a property of the finding, not of the verdict ---
# Both log templates are extracted from reviewer.md itself and instantiated with the taxonomy values
# reviewer.md declares, so the class under test is "every cause value a reviewer may write, on either
# outcome", never the example lines the task quotes: a value added to the taxonomy is exercised the day
# it is declared. The three places that declare that taxonomy — the Step 0 prose, the NEEDS WORK log
# template, the APPROVED log template — are also compared with each other, because a value added to one
# and not the others is exactly how a producer and this consumer drifted apart before.
QF1_RECORDS=$(python3 - ../.claude/agents/reviewer.md <<'PY'
import re, sys

src = open(sys.argv[1], encoding="utf-8").read()
NW = re.search(r'\{ID\} PR #\{N\} needs work\{ \(delta N\)\} — \{first finding, six words\} — cause: \{([^}]*)\}', src)
AP = re.search(r'\{ID\} PR #\{N\} approved — merge: \{orchestrator\|user\}\{ — cause: \{([^}]*)\}\}', src)
TAX = re.search(r'using this taxonomy:(.*?)Say this even', src, re.S)
out = [("meta", "NW_TEMPLATE", "yes" if NW else "no"),
       ("meta", "AP_TEMPLATE", "yes" if AP else "no"),
       ("meta", "TAXONOMY_PARAGRAPH", "yes" if TAX else "no")]


def members(alt):
    vals = [v.strip() for v in alt.split("|") if v.strip()]
    return sorted(v for v in vals if not v.startswith("other")), any(v.startswith("other") for v in vals)


if NW and AP and TAX:
    nw_fixed, nw_free = members(NW.group(1))
    ap_fixed, ap_free = members(AP.group(1))
    # each taxonomy member in the prose is a backticked token followed by its parenthesised gloss
    prose_fixed = sorted(set(re.findall(r'`([a-z][a-z-]+)` \(', TAX.group(1))))
    prose_free = bool(re.search(r'`other: \{one line\}`', TAX.group(1)))
    out.append(("meta", "DRIFT_PROSE_VS_NW", "OK" if (prose_fixed == nw_fixed and prose_free and nw_free)
                else "prose=%s nw=%s" % (prose_fixed, nw_fixed)))
    out.append(("meta", "DRIFT_AP_VS_NW", "OK" if (ap_fixed == [v for v in nw_fixed if v != "first-round"]
                                                   and ap_free and nw_free)
                else "ap=%s nw=%s" % (ap_fixed, nw_fixed)))
    out.append(("meta", "TAXONOMY_SIZE", str(len(prose_fixed))))
    out.append(("meta", "FALSE_COVERAGE_EVIDENCE", "yes" if "false-coverage-evidence" in prose_fixed else "no"))

    def ap_line(cause):   # cause None = the whole optional cause group dropped, as an approval with
        l = AP.group(0).replace("{ID}", "PI-101").replace("{N}", "101")   # nothing to name is written
        l = l.replace("{orchestrator|user}", "orchestrator")
        grp = re.search(r'\{ — cause: \{[^}]*\}\}', l).group(0)
        return "- 2026-09-01 " + l.replace(grp, "" if cause is None else " — cause: " + cause)

    def nw_line(cause):
        l = NW.group(0).replace("{ID}", "PI-102").replace("{N}", "102")
        l = l.replace("{ (delta N)}", "").replace("{first finding, six words}", "a short finding description")
        grp = re.search(r'\{[^}]*\}$', l).group(0)
        return "- 2026-09-01 " + (l.replace(grp, cause) if cause is not None else l.replace(" — cause: " + grp, ""))

    for v in ap_fixed + (["other: something specific"] if ap_free else []):
        out.append(("ap-cause", v, ap_line(v)))
    out.append(("ap-first-round", "first-round", ap_line("first-round")))
    out.append(("ap-absent", "no cause field at all", ap_line(None)))
    out.append(("ap-empty", "an empty cause field", ap_line("")))
    out.append(("ap-empty-mid", "an empty cause field before another field", ap_line("") + "— fix at: task file"))
    out.append(("nw-absent", "no cause field at all", nw_line(None)))

for r in out:
    print("|".join(r))
PY
)
ok "QF1 setup — reviewer.md declares a NEEDS WORK log template with its own cause field" 'grep -q "^meta|NW_TEMPLATE|yes$" <<<"$QF1_RECORDS"'
ok "QF1 setup — reviewer.md declares an APPROVED log template carrying the same cause field" 'grep -q "^meta|AP_TEMPLATE|yes$" <<<"$QF1_RECORDS"'
ok "QF1 setup — the Step 0 taxonomy paragraph is where those values are declared" 'grep -q "^meta|TAXONOMY_PARAGRAPH|yes$" <<<"$QF1_RECORDS"'
ok "QF1 setup — the taxonomy is not vacuous (4 fixed values or more)" '[[ "$(sed -n "s/^meta|TAXONOMY_SIZE|//p" <<<"$QF1_RECORDS")" -ge 4 ]]'
ok "QF1 — prose taxonomy and NEEDS WORK template declare the same set (no drift)" 'grep -q "^meta|DRIFT_PROSE_VS_NW|OK$" <<<"$QF1_RECORDS"'
ok "QF1/AC5 — the APPROVED template offers that same set minus first-round" 'grep -q "^meta|DRIFT_AP_VS_NW|OK$" <<<"$QF1_RECORDS"'
ok "QF1 — the taxonomy names false-coverage-evidence" 'grep -q "^meta|FALSE_COVERAGE_EVIDENCE|yes$" <<<"$QF1_RECORDS"'

while IFS='|' read -r kind label logline; do
  case "$kind" in ""|meta) continue;; esac
  Sq=$(mkrepo); writelog "$Sq" "$logline"; outq=$(run "$Sq"); rm -rf "$Sq"
  case "$kind" in
    ap-cause)
      ok "QF1/AC2 — an APPROVAL naming cause: $label is a signal, typed as a plain cause" \
         '[[ "$outq" == "RETRO DUE: 1 segnali"* ]] && grep -qE "^PI-101 — cause — " <<<"$outq"' ;;
    ap-first-round)
      ok "QF1/AC2 — an APPROVAL naming cause: first-round is not a signal (the same terms as a rework)" \
         '[[ "$outq" == "retro-due: nothing" ]]' ;;
    ap-absent|ap-empty|ap-empty-mid)
      ok "QF1/AC5 — an APPROVAL with $label is not a signal" '[[ "$outq" == "retro-due: nothing" ]]' ;;
    nw-absent)
      ok "QF1/AC5 — a NEEDS WORK with $label is not a signal either (unchanged)" \
         '[[ "$outq" == "retro-due: nothing" ]]' ;;
  esac
done <<<"$QF1_RECORDS"

ok "QF1/AC1 — reviewer.md states the rule this rests on, where the reviewer reads it" \
   'grep -q "A cause is a property of the finding, not of the verdict" ../.claude/agents/reviewer.md'
ok "QF1/AC1 — reviewer.md's Step 6 report line carries the cause on the APPROVED branch too" \
   'grep -q "APPROVED (merge: orchestrator|user){ — cause:" ../.claude/agents/reviewer.md'
ok "QF1/AC5 — reviewer.md says the approval's cause field is absent when there is nothing to name" \
   'grep -q "absent entirely when it did not" ../.claude/agents/reviewer.md'

# --- QF1 (AC2/AC6): outcome-independence over the class of outcome words this project really writes,
# harvested from its own log + archive at run time rather than from the four example lines the task
# quotes — a new outcome word is covered the day it is first written. Three corpora over the same
# harvested forms: with a real cause every line must signal, with cause: first-round none may, with no
# cause field at all none may. The last two are what make the first mean anything: a corpus that
# signalled whatever it said would come out green on the first assertion alone.
FORMS=$(grep -hoE '^- [0-9]{4}-[0-9]{2}-[0-9]{2} [^ ]+ PR #[0-9]+ [^—]*' ../docs/SESSION_HANDOFF.md ../docs/SESSION_HANDOFF_ARCHIVE.md 2>/dev/null \
        | sed -E 's/^- [0-9-]+ [^ ]+ PR #[0-9]+ //; s/[[:space:]]+$//' | grep -v '^$' | sort -u)
form_count=$(printf '%s\n' "$FORMS" | grep -c . || true)
ok "QF1 setup — this project's own log/archive yields several distinct outcome words (not vacuous)" \
   '[[ "$form_count" -ge 5 ]]'

corpus(){ # corpus cause|first-round|none — one line per harvested outcome form, with a distinct task id
          # and a distinct cause on each, so neither (b) nor (c) can add a signal of its own to the count
  local mode="$1" i=0 f suffix
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    i=$((i+1))
    case "$mode" in
      cause) suffix=" — cause: other: c$i" ;;
      first-round) suffix=" — cause: first-round" ;;
      none) suffix="" ;;
    esac
    printf -- '- 2026-09-01 PI-%d PR #%d %s — a short description%s\n' "$((500+i))" "$((500+i))" "$f" "$suffix"
  done <<<"$FORMS"
}

run_corpus(){
  local d l lines=()
  d=$(mkrepo)
  while IFS= read -r l; do lines+=("$l"); done < <(corpus "$1")
  writelog "$d" "${lines[@]}"
  run "$d"
  rm -rf "$d"
}
outq1=$(run_corpus cause); outq2=$(run_corpus first-round); outq3=$(run_corpus none)
ok "QF1/AC2 — every outcome word this project writes carries its cause into exactly one signal" \
   '[[ "$outq1" == "RETRO DUE: $form_count segnali"* ]]'
ok "QF1/AC2 — that corpus really spans both provenances, so the equality is not one outcome repeated" \
   '[[ $(grep -cE "^[A-Za-z0-9.-]+ — needs-work-cause — " <<<"$outq1") -gt 0 ]] && [[ $(grep -cE "^[A-Za-z0-9.-]+ — cause — " <<<"$outq1") -gt 0 ]]'
ok "QF1/AC2 — the same corpus with cause: first-round raises nothing, whatever the outcome word" \
   '[[ "$outq2" == "retro-due: nothing" ]]'
ok "QF1/AC2 — the same corpus with no cause field raises nothing, whatever the outcome word" \
   '[[ "$outq3" == "retro-due: nothing" ]]'

# --- QF1 (AC4): widening WHICH lines are asked for a cause must not widen HOW one is recognised inside
# a line. Every negative below sits in a fixture whose sibling line carries the real field, so "no
# signal" can never come from the fixture not being read at all.
S24=$(mkrepo)
writelog "$S24" \
  "- 2026-09-05 PI-70 PR #70 approved — merge: orchestrator — the false-coverage-evidence cause found in round 2 is closed" \
  "- 2026-09-04 PI-71 PR #71 draft — retro-due.sh reads a cause on an approval too — 8 tests" \
  "- 2026-09-03 PI-72 PR #72 approved — merge: orchestrator — root cause: base mossa" \
  "- 2026-09-02 PI-73 PR #73 merged — because: the evidence row was never run" \
  "- 2026-09-01 PI-74 PR #74 approved — merge: orchestrator — cause: false-coverage-evidence"
out24=$(run "$S24")
ok "AC4 — a taxonomy word named in an approval's own prose is not a cause field" '! grep -q "PI-70" <<<"$out24"'
ok "AC4 — a PR-title-shaped line describing the cause mechanism is not a cause field" '! grep -q "PI-71" <<<"$out24"'
ok "AC4 — 'root cause:' on an approval is not a cause field" '! grep -q "PI-72" <<<"$out24"'
ok "AC4 — 'because:' on a merged line is not a cause field" '! grep -q "PI-73" <<<"$out24"'
ok "AC4 — the sibling line with the real field, same fixture, IS a signal (the negatives are not vacuous)" \
   'grep -qE "^PI-74 — cause —" <<<"$out24"'
ok "AC4 — exactly one signal in this fixture" '[[ "$out24" == "RETRO DUE: 1 segnali"* ]]'
rm -rf "$S24"

# a fact written in the exact cause-field shape is outside the log section and is never read as a signal;
# the log line in the same file is, which is what proves the file was read at all
S25=$(mkrepo)
mkdir -p "$S25/docs"
cat > "$S25/docs/SESSION_HANDOFF.md" <<'EOF'
# Session handoff

## Fatti che non scadono
- QF-1: a cause is read off any log line now — cause: false-coverage-evidence — a fact is not a log line

## Log (più recente in alto, ultime 40 righe)
- 2026-09-01 PI-76 PR #76 approved — merge: orchestrator — cause: base-moved
EOF
out25=$(cd "$S25" && bash "$SCRIPT")
ok "AC4 — a fact written in the exact cause-field shape is never read as a signal" '! grep -q "QF-1" <<<"$out25"'
ok "AC4 — while the approval line in the same file is (the section boundary excludes it, not the shape)" \
   '[[ "$out25" == "RETRO DUE: 1 segnali"* ]] && grep -qE "^PI-76 — cause —" <<<"$out25"'
rm -rf "$S25"

# --- AC5/AC6: the wiring this script is read by ---
ok "AC5 — run-wave/SKILL.md calls retro-due.sh after review" 'grep -q "bin/retro-due.sh" ../.claude/skills/run-wave/SKILL.md'
ok "AC5 — run-wave/SKILL.md launches retro on exit 10, in background, unprompted" \
   "grep -q 'Exit 10' ../.claude/skills/run-wave/SKILL.md && grep -qE 'subagent_type: .?retro.?' ../.claude/skills/run-wave/SKILL.md && grep -q 'never asking, never waiting' ../.claude/skills/run-wave/SKILL.md"
ok "AC5 — quickfix/SKILL.md calls retro-due.sh after review" 'grep -q "bin/retro-due.sh" ../.claude/skills/quickfix/SKILL.md'
ok "AC5 — quickfix/SKILL.md launches retro on exit 10, in background, unprompted" \
   "grep -q 'Exit 10' ../.claude/skills/quickfix/SKILL.md && grep -qE 'subagent_type: .?retro.?' ../.claude/skills/quickfix/SKILL.md && grep -q 'never asking, never waiting' ../.claude/skills/quickfix/SKILL.md"
ok "AC6 — retro.md writes the retro-mark line with handoff.sh log" 'grep -q "handoff.sh log \"retro-mark" ../.claude/agents/retro.md'
ok "AC6 — retro.md writes it as the last thing it does" 'grep -qi "the last thing you do" ../.claude/agents/retro.md'

# --- F5 (round 2): run-wave/quickfix never launch a second retro while one is already open (a); retro.md
# declares the Signals: input and its {scope} value (b); retro.md writes the mark even without a PR (c) ---
ok "F5a — run-wave/SKILL.md checks for an already-open retro/ branch before launching" \
   "grep -q 'gh pr list --state open --json headRefName' ../.claude/skills/run-wave/SKILL.md && grep -q \"'\\^retro/'\" ../.claude/skills/run-wave/SKILL.md"
ok "F5a — quickfix/SKILL.md checks for an already-open retro/ branch before launching" \
   "grep -q 'gh pr list --state open --json headRefName' ../.claude/skills/quickfix/SKILL.md && grep -q \"'\\^retro/'\" ../.claude/skills/quickfix/SKILL.md"
ok "F5b — retro.md declares the Signals: input" 'grep -q "Signals:" ../.claude/agents/retro.md'
ok "F5b — retro.md defines {scope} for a Signals: run" 'grep -q "signals-{date}" ../.claude/agents/retro.md'
ok "F5c — retro.md writes the mark even when no PR was opened" 'grep -qi "found no pattern worth a PR at all" ../.claude/agents/retro.md'
ok "F5c — retro.md still excludes the draft-not-merged case" 'grep -qi "stayed in draft" ../.claude/agents/retro.md'

[[ "$fail" -eq 0 ]] && echo "retro-due.test.sh: all ok" || echo "retro-due.test.sh: FAILURES"
exit "$fail"
