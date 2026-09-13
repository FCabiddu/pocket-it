#!/usr/bin/env bash
# Self-test for doctor.sh's legacy nested-board check (PI-3): EPIC.md / STORY-n.m.md summaries that nobody
# updated once every child task turned Done, on scratch git repos. Covers AC1-AC4 of PI-3.
cd "$(dirname "$0")"
SCRIPT="$PWD/doctor.sh"
S=$(mktemp -d "${TMPDIR:-/tmp}/doctor-test.XXXXXX")
cleanup(){ rm -rf "$S"; }
trap cleanup EXIT
fail=0
ok(){ if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
has(){ grep -qF "$1" <<<"$OUT"; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
q(){ "$@" >/dev/null 2>&1; }
task(){ # task <path> <status> — minimal well-formed task file (no missing-field warnings of its own)
  mkdir -p "$(dirname "$1")"
  printf '# %s\n\n**Status**: %s\n**Label**: DevOps\n**Files**: `x`\n**TAD**: none\n\n## Acceptance criteria\n- ok\n' "$(basename "$1" .md)" "$2" > "$1"
}

# --- repo 1: nested board (tasks/EPIC-n-slug/EPIC.md, STORY-n.m.md, T-n.m.k.md) ---
R1="$S/repo1"
q git init -q -b main "$R1"
task "$R1/tasks/EPIC-1-x/EPIC.md"    "Not Started"   # AC1: epic summary stale, all children Done
task "$R1/tasks/EPIC-1-x/T-1.1.md"   "Done"
task "$R1/tasks/EPIC-1-x/T-1.2.md"   "Done — merged"
task "$R1/tasks/EPIC-4-w/EPIC.md"    "Done"          # already accurate, no epic-level warning expected
task "$R1/tasks/EPIC-4-w/STORY-4.1.md" "In Progress" # AC2: story summary stale, its children Done
task "$R1/tasks/EPIC-4-w/T-4.1.1.md" "Done"
task "$R1/tasks/EPIC-4-w/T-4.1.2.md" "Done"
task "$R1/tasks/EPIC-2-y/EPIC.md"    "Not Started"   # AC3a: children not all Done — no warning
task "$R1/tasks/EPIC-2-y/T-2.1.md"   "Done"
task "$R1/tasks/EPIC-2-y/T-2.2.md"   "Todo"
task "$R1/tasks/EPIC-3-z/EPIC.md"    "Not Started"   # AC3b: no T-*.md children at all — no warning
q git -C "$R1" add -A; q git -C "$R1" commit -qm board

OUT=$(cd "$R1" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "AC1 epic summary warned, exact wording"        'has "warn  tasks/EPIC-1-x/EPIC.md: says \"Not Started\" but all 2 children are Done — update the summary"'
ok "AC2 story summary warned, exact wording"        'has "warn  tasks/EPIC-4-w/STORY-4.1.md: says \"In Progress\" but all 2 children are Done — update the summary"'
ok "EPIC-4-w already-Done summary not re-warned"    '! has "EPIC-4-w/EPIC.md: says"'
ok "AC3a mismatched children: no warning"           '! has "EPIC-2-y/EPIC.md: says"'
ok "AC3b no children: no warning"                   '! has "EPIC-3-z/EPIC.md: says"'
ok "warnings never fail doctor (exit 0)"            '[[ $rc -eq 0 ]]'

# --- repo 2: flat board only — behaviour and exit code unchanged (AC4) ---
R2="$S/repo2"
q git init -q -b main "$R2"
task "$R2/tasks/T-1.md" "Done"
task "$R2/tasks/T-2.md" "Todo"
q git -C "$R2" add -A; q git -C "$R2" commit -qm board
OUT=$(cd "$R2" && bash "$SCRIPT"); rc=$?
ok "AC4 flat board: no summary warning emitted"     '! has "update the summary"'
ok "AC4 flat board: exit 0, 2 task files counted"   '[[ $rc -eq 0 ]] && has "doctor: 0 error(s), 1 warning(s), 2 task file(s)"'

# --- repo 3: duplicate task ids (PI-25) ---
# task() ties the header id to the filename, so a real duplicate needs two files declaring the
# same id in their header with different filenames — write those by hand instead of via task().
decl(){ # decl <path> <declared-id> [title]
  mkdir -p "$(dirname "$1")"
  printf '# %s — %s\n\n**Status**: Todo\n**Label**: DevOps\n**Files**: `x`\n**TAD**: none\n\n## Acceptance criteria\n- ok\n' "$2" "${3:-t}" > "$1"
}
R3="$S/repo3"
q git init -q -b main "$R3"
decl "$R3/tasks/PI-9-hello.md" "PI-9" "Hello"          # AC1: two files declare PI-9
decl "$R3/tasks/PI-9-world.md" "PI-9" "World"
decl "$R3/tasks/PI-19-other.md" "PI-19" "Other"        # AC3: PI-9 vs PI-19 must not collide
decl "$R3/tasks/EPIC-9-x/EPIC.md" "PI-9" "Epic summary"        # AC4: excluded before duplicate check ever sees it
decl "$R3/tasks/EPIC-9-x/STORY-9.1.md" "PI-9" "Story summary"  # AC4: same
q git -C "$R3" add -A; q git -C "$R3" commit -qm board
OUT=$(cd "$R3" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "AC1 duplicate id is an ERROR with id and both paths" 'has "ERROR duplicate task id PI-9: tasks/PI-9-hello.md, tasks/PI-9-world.md"'
ok "AC1 duplicate id fails doctor (exit 1)"               '[[ $rc -eq 1 ]]'
ok "AC3 PI-9 and PI-19 not treated as the same id"        '! has "duplicate task id PI-19"'
ok "AC4 epic/story summaries not pulled into the duplicate error" '! has "EPIC.md" && ! has "STORY-9.1.md"'

# --- repo 4: no duplicate ids — the check is silent (AC2) ---
R4="$S/repo4"
q git init -q -b main "$R4"
decl "$R4/tasks/PI-30-a.md" "PI-30" "A"
decl "$R4/tasks/PI-31-b.md" "PI-31" "B"
q git -C "$R4" add -A; q git -C "$R4" commit -qm board
OUT=$(cd "$R4" && bash "$SCRIPT"); rc=$?
ok "AC2 no duplicates: check produces no output"  '! has "duplicate task id"'
ok "AC2 no duplicates: doctor stays green"        '[[ $rc -eq 0 ]]'

# --- repo 5: AC3 regression — a same-prefix, different-number pair alone must never collide.
# Catches a dedup key like "prefix + last digit" (PI-19 -> PI-9), which repo 3's AC3 assertion
# above misses because it only greps for the exact string "duplicate task id PI-19".
R5="$S/repo5"
q git init -q -b main "$R5"
decl "$R5/tasks/PI-9-only.md" "PI-9" "Only"
decl "$R5/tasks/PI-19-only.md" "PI-19" "Only"
q git -C "$R5" add -A; q git -C "$R5" commit -qm board
OUT=$(cd "$R5" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "AC3 regression: PI-9 alone next to PI-19 alone — no duplicate at all" '! has "duplicate task id"'
ok "AC3 regression: doctor stays green"                                   '[[ $rc -eq 0 ]]'

# --- repo 6: a plain hyphenated word is not an id (PI-25 second round — false positive on real boards) ---
# Five closed notes titled "# Follow-up: ..." on a real board all produced the same fake id
# "Follow-up" under the old regex (any word with a hyphen), which doctor.sh then reported as
# a duplicate even though these are not tasks at all.
R6="$S/repo6"
q git init -q -b main "$R6"
decl "$R6/tasks/follow-up-1.md" "Follow-up" "the first one"
decl "$R6/tasks/follow-up-2.md" "Follow-up" "the second one"
decl "$R6/tasks/PI-41-real.md" "PI-41" "a real task, so the board is not empty"
q git -C "$R6" add -A; q git -C "$R6" commit -qm board
OUT=$(cd "$R6" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "no id: two Follow-up notes are not a duplicate id"  '! has "duplicate task id"'
ok "no id: doctor stays green"                           '[[ $rc -eq 0 ]]'

# --- repo 7: a numbered id must not swallow trailing punctuation ("T-2.1.1." vs "T-2.1.1") ---
# If the id regex greedily consumes a trailing "." after the last digit, "T-2.1.1." and "T-2.1.1"
# extract to two different strings and a real duplicate goes undetected.
R7="$S/repo7"
q git init -q -b main "$R7"
mkdir -p "$R7/tasks"
printf '# T-2.1.1. Title with a period after the number\n\n**Status**: Todo\n**Label**: DevOps\n**Files**: `x`\n**TAD**: none\n\n## Acceptance criteria\n- ok\n' > "$R7/tasks/t-2.1.1-a.md"
printf '# T-2.1.1 Title without a period\n\n**Status**: Todo\n**Label**: DevOps\n**Files**: `x`\n**TAD**: none\n\n## Acceptance criteria\n- ok\n' > "$R7/tasks/t-2.1.1-b.md"
q git -C "$R7" add -A; q git -C "$R7" commit -qm board
OUT=$(cd "$R7" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "trailing dot stripped: both extract to T-2.1.1, caught as duplicate" 'has "ERROR duplicate task id T-2.1.1: tasks/t-2.1.1-a.md, tasks/t-2.1.1-b.md"'
ok "trailing dot stripped: doctor exits 1"                                '[[ $rc -eq 1 ]]'

# --- repo 8: an id must actually be READ for each shape of the class (PI-25 fourth round) ---
# Asserting "no ERROR" on a single, un-duplicated file per shape is a vacuous test: if the regex
# stops reading that shape as an id entirely, there is still no ERROR (nothing to compare against),
# so the assertion holds either way. The reviewer proved it: putting the round-2 (pure-digit-only)
# regex back in doctor.sh left those old assertions green. The only way to prove the id is read is
# to declare the SAME id, of that exact shape, in two different files and require the duplicate to
# be caught — that fails shut if the shape stops being recognised.
R8="$S/repo8"
q git init -q -b main "$R8"
decl "$R8/tasks/style-pr1-a.md" "STYLE-PR1" "letters and digits in the same segment, copy A"
decl "$R8/tasks/style-pr1-b.md" "STYLE-PR1" "letters and digits in the same segment, copy B"
decl "$R8/tasks/qf-10b-a.md" "QF-10b" "a letter after the number, copy A"
decl "$R8/tasks/qf-10b-b.md" "QF-10b" "a letter after the number, copy B"
decl "$R8/tasks/t-1.2.3-a.md" "T-1.2.3" "more than one numeric segment, copy A"
decl "$R8/tasks/t-1.2.3-b.md" "T-1.2.3" "more than one numeric segment, copy B"
q git -C "$R8" add -A; q git -C "$R8" commit -qm board
OUT=$(cd "$R8" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "letters+digits in one segment (STYLE-PR1) is read: duplicate caught" 'has "ERROR duplicate task id STYLE-PR1: tasks/style-pr1-a.md, tasks/style-pr1-b.md"'
ok "letter after the number (QF-10b) is read: duplicate caught"         'has "ERROR duplicate task id QF-10b: tasks/qf-10b-a.md, tasks/qf-10b-b.md"'
ok "more than one numeric segment (T-1.2.3) is read: duplicate caught" 'has "ERROR duplicate task id T-1.2.3: tasks/t-1.2.3-a.md, tasks/t-1.2.3-b.md"'
ok "all three shapes: doctor exits 1"                                   '[[ $rc -eq 1 ]]'

# --- repo 9: a letter suffix on the numeric segment must not be truncated away (PI-25 third round) ---
# The round-2 regex stopped at the digit run, so "T-1.2.3a"/"T-1.2.3b" both extracted to "T-1.2.3"
# and "QF-10b" extracted to "QF-10": two distinct real ids collided into one, a false duplicate
# (or a silent overwrite in next-wave.sh, same family of bug PI-25 exists to catch).
R9="$S/repo9"
q git init -q -b main "$R9"
decl "$R9/tasks/t-1.2.3a.md" "T-1.2.3a" "letter suffix a"
decl "$R9/tasks/t-1.2.3b.md" "T-1.2.3b" "letter suffix b"
decl "$R9/tasks/qf-10.md" "QF-10" "plain"
decl "$R9/tasks/qf-10b.md" "QF-10b" "letter suffix on a shorter id"
q git -C "$R9" add -A; q git -C "$R9" commit -qm board
OUT=$(cd "$R9" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "T-1.2.3a and T-1.2.3b are distinct ids, not merged" '! has "ERROR"'
ok "QF-10 and QF-10b are distinct ids, not merged"      '! has "ERROR"'
ok "letter-suffixed ids: doctor stays green"            '[[ $rc -eq 0 ]]'

exit $fail
