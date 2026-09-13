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

# --- AC5/AC6: the wiring this script is read by ---
ok "AC5 — run-wave/SKILL.md calls retro-due.sh after review" 'grep -q "bin/retro-due.sh" ../.claude/skills/run-wave/SKILL.md'
ok "AC5 — run-wave/SKILL.md launches retro on exit 10, in background, unprompted" \
   "grep -q 'Exit 10' ../.claude/skills/run-wave/SKILL.md && grep -qE 'subagent_type: .?retro.?' ../.claude/skills/run-wave/SKILL.md && grep -q 'never asking, never waiting' ../.claude/skills/run-wave/SKILL.md"
ok "AC5 — quickfix/SKILL.md calls retro-due.sh after review" 'grep -q "bin/retro-due.sh" ../.claude/skills/quickfix/SKILL.md'
ok "AC5 — quickfix/SKILL.md launches retro on exit 10, in background, unprompted" \
   "grep -q 'Exit 10' ../.claude/skills/quickfix/SKILL.md && grep -qE 'subagent_type: .?retro.?' ../.claude/skills/quickfix/SKILL.md && grep -q 'never asking, never waiting' ../.claude/skills/quickfix/SKILL.md"
ok "AC6 — retro.md writes the retro-mark line with handoff.sh log" 'grep -q "handoff.sh log \"retro-mark" ../.claude/agents/retro.md'
ok "AC6 — retro.md writes it after its PR(s) are merged" 'grep -qi "after every PR above is merged" ../.claude/agents/retro.md'

[[ "$fail" -eq 0 ]] && echo "retro-due.test.sh: all ok" || echo "retro-due.test.sh: FAILURES"
exit "$fail"
