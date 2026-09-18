#!/usr/bin/env bash
# Self-test for doctor.sh's legacy nested-board check (PI-3): EPIC.md / STORY-n.m.md summaries that nobody
# updated once every child task turned Done, on scratch git repos. Covers AC1-AC4 of PI-3.
cd "$(dirname "$0")"
# PI-29 round 6: doctor.sh resolves its OWN path with `pwd -P` (physical, symlinks resolved) before
# printing it in a command (DOCTOR_ABS). A test comparing that printed text against a path built from
# a plain `pwd` (logical, keeps a symlink component such as macOS's /tmp -> /private/tmp) mismatches
# whenever the checkout is reached through a symlink — every path used in a text comparison below is
# therefore resolved with `pwd -P` too, not just the one `has` assertion that first caught it.
SCRIPT="$(pwd -P)/doctor.sh"
SELF="$(pwd -P)/doctor.test.sh"  # PI-45: absolute, so the recursion test below can invoke this same
                                  # file regardless of how it was itself invoked ($0 stops being a
                                  # usable relative path the moment the `cd` above runs)
GUARD="$(cd .. && pwd -P)/.claude/hooks/guard.sh"  # PI-29 round 4: proves doctor's printed commands pass the real guard
guard_rc(){ # guard_rc <cwd> <command> — exit code of guard.sh given <command> as a PreToolUse Bash payload
  local cwd="$1" cmd="$2"
  ( cd "$cwd" && python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$cmd" | bash "$GUARD" >/dev/null 2>&1 )
  echo $?
}
S=$(mktemp -d "${TMPDIR:-/tmp}/doctor-test.XXXXXX")
cleanup(){ rm -rf "$S"; }
trap cleanup EXIT
# PI-45 AC3: every self-mutating block below (mutate_has_section and its siblings) patches a copy
# of $SCRIPT's content captured ONCE here, never whatever $SCRIPT happens to hold at the moment
# each block runs — so two self-mutations in the same run, or bin/doctor.sh having been mutated
# externally before this suite started (the normal way to prove it is not vacuous), cannot interfere.
SCRIPT_SRC="$S/.doctor.sh.src"
cp "$SCRIPT" "$SCRIPT_SRC"
fail=0
ok(){ if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
has(){ grep -qF "$1" <<<"$OUT"; }
# PI-63 (AC1): a background reader that never stops watching bin/doctor.sh, the checked-out file
# ($SCRIPT — never a copy) for the entire run — proof by continuous sampling, not by reading the
# code below and trusting that nothing in it opens $SCRIPT for writing. Every self-mutating block in
# this file is required to work on a copy (SCRIPT_SRC above, or a throwaway file under $S); if any of
# them, now or later, opens $SCRIPT itself, this catches the byte the moment it differs from HEAD,
# whether or not the writer ever restores it afterwards.
SCRIPT_WATCH_HIT="$S/.doctor.sh.watch-hit"
( while kill -0 $$ 2>/dev/null; do
    cmp -s "$SCRIPT" "$SCRIPT_SRC" || { echo differed > "$SCRIPT_WATCH_HIT"; break; }
    sleep 0.02
  done ) &
SCRIPT_WATCH_PID=$!
cleanup(){ kill "$SCRIPT_WATCH_PID" 2>/dev/null; wait "$SCRIPT_WATCH_PID" 2>/dev/null; rm -rf "$S"; }
trap cleanup EXIT

# --- PI-45: the gate every self-mutation in this file must pass ---------------------------------
# Threat model. Each "mutation ...: proves the test is not vacuous" block below builds a patched copy
# of doctor.sh by matching source text, runs that copy, and asserts on what it printed. The text it
# matches can be gone, edited in place or doubled -- most often because bin/doctor.sh was modified
# outside this run, which is exactly what a reviewer does to prove this suite is not vacuous. When
# that happens the patched copy must never reach the downstream assertion: that assertion would then
# report a real-looking regression against a check that never ran -- a test failure naming the wrong
# test, which is the damage PI-45 exists to close. Covered here: the mutation did not apply, applied
# to a different span than its address assumes, or produced a fragment instead of a script.
# Deliberately left to the assertions themselves: a mutation that lands exactly where it was aimed
# but whose intent has gone stale. Left to doctor.sh's own checks: any defect in doctor.sh.
#
# The rule, and why the obvious check is not it. "The marker text is in the output" is evidence a
# TRUNCATION also satisfies. `sed '/A/,/B/c\...'` whose B no longer matches does not fail: the range
# opens at A, never closes, and runs to end of file -- sed prints the replacement and drops every
# line after A. Measured on this file's own _classify_base block, with one trailing comment appended
# to the closing anchor in bin/doctor.sh and nothing else touched: 446 lines in, 74 out, the `PY`
# heredoc terminator gone, the marker present in all of it, and `bash -n` on that fragment still
# exiting 0. A doubled opening anchor does the same thing one range later; a doubled closing anchor
# closes the range early, over a span the block never meant. So no block may conclude "applied" from
# its own output alone. Every block declares the anchors its address uses, they are counted in the
# SOURCE before sed runs (src_anchors), the address is then built from those same strings (sed_lit,
# so the line counted and the line matched cannot drift apart), and what came out is checked to
# still be a whole script (mutant_whole). Both layers, at every site: the count catches the doubled
# anchor that produces a perfectly whole file over the wrong span, and mutant_whole catches the
# runaway of a future block whose author forgets to declare an anchor at all.
MUT_WHY=""   # why the last gate refused -- quoted verbatim in that block's own named failure
sed_lit(){ # sed_lit <literal> -- BRE-escape <literal> so /^<it>$/ matches exactly that line and
           # nothing else. Used to build every address from the same string src_anchors counted.
  printf '%s' "$1" | sed 's|[][\.*^$/]|\\&|g'
}
src_anchors(){ # src_anchors <file> <line|substr> <count> <anchor>... -- 0 iff every <anchor> occurs
  # exactly <count> times in <file>, matched the way sed matches the address built from it: `line`
  # for /^...$/ (whole line, grep -x, so a comment appended to that line does NOT count -- the
  # substring match a plain grep -F does would accept it and let the range run away), `substr` for
  # /.../ (anywhere on the line). A range address declares BOTH of its anchors here, or the gate is
  # only guessing which lines the range will actually span.
  local f="$1" mode="$2" want="$3"; shift 3
  local a n
  for a in "$@"; do
    if [[ "$mode" == line ]]; then n=$(grep -cxF -- "$a" "$f"); else n=$(grep -cF -- "$a" "$f"); fi
    if [[ "$n" != "$want" ]]; then
      MUT_WHY="anchor found $n times, not $want, in the captured bin/doctor.sh: ${a:0:60}"
      return 1
    fi
  done
  MUT_WHY=""
}
mutant_whole(){ # mutant_whole <file> -- <file> is still a whole doctor.sh and not a fragment: it
  # parses as bash, the python heredoc it opens is closed by its own delimiter, and that python
  # still compiles. Anchor-independent on purpose -- being whole is the property a runaway range
  # destroys whatever anchors it used, so this also covers an address whose anchors nobody declared.
  local f="$1" why
  if ! bash -n "$f" 2>/dev/null; then MUT_WHY="the patched copy no longer parses as bash"; return 1; fi
  why=$(python3 - "$f" <<'MWEOF'
import re, sys
lines = open(sys.argv[1], errors="ignore").read().splitlines(True)
start = delim = None
for i, line in enumerate(lines):
    m = re.match(r"^python3 .*<<'([A-Za-z_][A-Za-z0-9_]*)'\s*$", line)
    if m:
        start, delim = i + 1, m.group(1); break
if start is None:
    print("the patched copy no longer opens a python heredoc at all"); sys.exit(1)
end = None
for j in range(start, len(lines)):
    if lines[j].rstrip("\n") == delim:
        end = j; break
if end is None:
    print("the patched copy is a fragment: its python heredoc is never closed by %s" % delim); sys.exit(1)
try:
    compile("".join(lines[start:end]), "<mutant>", "exec")
except SyntaxError as e:
    print("the patched copy's python no longer compiles: line %s: %s" % (e.lineno, e.msg)); sys.exit(1)
MWEOF
  ) || { MUT_WHY="$why"; return 1; }
  MUT_WHY=""
}
mutation_applied(){ # mutation_applied <mutant> <marker> -- the only way a block below may conclude
  # the mutation applied: the marker landed AND what carries it is still a whole script.
  if ! grep -qF -- "$2" "$1"; then MUT_WHY="the mutation marker never landed in the patched copy"; return 1; fi
  mutant_whole "$1"
}

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
decl "$R8/tasks/e2e-4-a.md" "E2E-4" "digit inside the prefix itself, copy A"
decl "$R8/tasks/e2e-4-b.md" "E2E-4" "digit inside the prefix itself, copy B"
decl "$R8/tasks/welcome-a11y-1-a.md" "WELCOME-A11Y-1" "digit in a middle segment, copy A"
decl "$R8/tasks/welcome-a11y-1-b.md" "WELCOME-A11Y-1" "digit in a middle segment, copy B"
q git -C "$R8" add -A; q git -C "$R8" commit -qm board
OUT=$(cd "$R8" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "letters+digits in the trailing segment (STYLE-PR1) is read: duplicate caught" 'has "ERROR duplicate task id STYLE-PR1: tasks/style-pr1-a.md, tasks/style-pr1-b.md"'
ok "letter after the number (QF-10b) is read: duplicate caught"                  'has "ERROR duplicate task id QF-10b: tasks/qf-10b-a.md, tasks/qf-10b-b.md"'
ok "more than one numeric segment (T-1.2.3) is read: duplicate caught"          'has "ERROR duplicate task id T-1.2.3: tasks/t-1.2.3-a.md, tasks/t-1.2.3-b.md"'
ok "digit inside the prefix itself (E2E-4) is read: duplicate caught"           'has "ERROR duplicate task id E2E-4: tasks/e2e-4-a.md, tasks/e2e-4-b.md"'
ok "digit in a middle segment (WELCOME-A11Y-1) is read: duplicate caught"       'has "ERROR duplicate task id WELCOME-A11Y-1: tasks/welcome-a11y-1-a.md, tasks/welcome-a11y-1-b.md"'
ok "all five shapes: doctor exits 1"                                             '[[ $rc -eq 1 ]]'

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

# --- repo 10: base branch integrity across a real timeline (PI-29) — first run, a normal advance,
# a rewrite (force-push) and a deletion, all against a real local "origin" (a bare repo), so the
# fetch/force-fetch/merge-base machinery in doctor.sh runs for real, not simulated.
seed_origin(){ # seed_origin <bare-path> <scratch-dir> — bare origin + one commit on main, echoes the sha
  q git init -q --bare -b main "$1"
  q git -C "$1" config receive.denyDeleteCurrent ignore  # AC3 needs to delete "main" while it is the bare repo's HEAD
  q git init -q -b main "$2"
  q git -C "$2" remote add origin "$1"
  printf 'v1\n' > "$2/f.txt"
  q git -C "$2" add -A; q git -C "$2" commit -qm c1
  q git -C "$2" push -q origin main
  git -C "$2" rev-parse HEAD
}
common(){ # <work-dir> — the shared, never-committed .git; --git-common-dir is relative for a main checkout
  local d; d=$(git -C "$1" rev-parse --git-common-dir)
  case "$d" in /*) echo "$d" ;; *) echo "$1/$d" ;; esac
}
seen_has(){ grep -q "$2" "$(common "$1")/pocket-it/base-seen" 2>/dev/null; } # <work-dir> <"branch sha">

BARE10="$S/repo10-origin.git"; SEED10="$S/repo10-seed"
SHA1=$(seed_origin "$BARE10" "$SEED10")
WORK10="$S/repo10-work"
q git clone -q "$BARE10" "$WORK10"

# AC4: first run ever — record the current tip, report nothing about the base branch
OUT=$(cd "$WORK10" && bash "$SCRIPT")
ok "AC4 first run: base branch not reported"       '! has "base branch '"'"'main'"'"'"'
ok "AC4 first run: seen commit recorded"           'seen_has "$WORK10" "main $SHA1"'

# advance origin normally (a real commit on top of the seen one)
printf 'v2\n' > "$SEED10/f.txt"; q git -C "$SEED10" add -A; q git -C "$SEED10" commit -qm c2; q git -C "$SEED10" push -q origin main
SHA2=$(git -C "$SEED10" rev-parse HEAD)

# AC1: base advanced normally since the last run — no report, seen commit follows the tip
OUT=$(cd "$WORK10" && bash "$SCRIPT")
ok "AC1 normal advance: base branch not reported"  '! has "base branch '"'"'main'"'"'"'
ok "AC1 normal advance: seen commit follows tip"   'seen_has "$WORK10" "main $SHA2"'

# rewrite origin: force-push an unrelated history — the seen commit falls out of it
SCRATCH10="$S/repo10-scratch"
q git init -q -b main "$SCRATCH10"; q git -C "$SCRATCH10" remote add origin "$BARE10"
printf 'other\n' > "$SCRATCH10/g.txt"; q git -C "$SCRATCH10" add -A; q git -C "$SCRATCH10" commit -qm orphan
q git -C "$SCRATCH10" push -q --force origin main
# a legitimate commit pushed AFTER the bad rewrite — recovery must not discard it (round 3, finding 1)
printf 'after\n' > "$SCRATCH10/h.txt"; q git -C "$SCRATCH10" add -A; q git -C "$SCRATCH10" commit -qm after-rewrite
q git -C "$SCRATCH10" push -q origin main
AFTER_SHA10=$(git -C "$SCRATCH10" rev-parse HEAD)

# AC2/AC3: base rewritten or deleted — an ERROR that says how to inspect it and how to SAVE the lost
# commit LOCALLY, never a command that publishes anything to origin, under ANY name (PI-29 round 5).
# Round 3 pushed a merge commit straight onto the base; round 4 replaced that with a push of a
# "rescue" branch — still a push, and an intentional rewrite can exist precisely to remove something
# (a secret) from origin, so republishing the dropped history under a new name defeats it just the
# same, even though the base ref itself is left alone. So every printed command now only ever writes
# to the LOCAL repository. Proof, per command: (a) the command text itself contains no "push"; (b) the
# ENTIRE remote ref set (`git ls-remote origin`, not just refs/heads/<base>) is byte-identical
# before/after running it, against a test remote whose pre-receive hook rejects EVERY write, not only
# to the base; (c) a local `rescue-<sha12>` branch exists afterwards, pointing at the lost commit; (d)
# it is allowed by the real pocket-it push guard even when the base is literally named "main"; (e) it
# leaves doctor RED until a person restores the base or, for a rewrite, runs --accept-base. Each
# remediation path gets its OWN fresh origin/clone so a mutation's real push in one path never
# disturbs another path's test.
extract_save_cmd(){        grep '^ERROR base branch' | sed -E 's/.*this never pushes: (.*) — restoring.*/\1/'; }        # AC2, from doctor's normal run
extract_accept_cmd(){      grep '^ERROR base branch' | sed -E 's/.*then accept it with: (.*)$/\1/'; }                   # AC2, unchanged shape
extract_save_cmd_del(){    grep '^ERROR base branch' | sed -E 's/.*can be lost: (.*) — whether to publish.*/\1/'; }         # AC3, from doctor's normal run
extract_save_cmd_del_acc(){ grep '^doctor --accept-base' | sed -E 's/.*can be lost: (.*) — whether to publish.*/\1/'; }     # AC3, from --accept-base
seed_prev(){ # seed_prev <clone-dir> <base> <sha> — pre-record doctor's "last seen" baseline for a clone
  mkdir -p "$(common "$1")/pocket-it"
  printf '%s %s\n' "$2" "$3" > "$(common "$1")/pocket-it/base-seen"
}
install_reject_all_hook(){ # install_reject_all_hook <bare-path> — from here on this test remote refuses
  # EVERY write (any ref, any name), so "the command ran clean and the ref set didn't move" is not an
  # accident of only checking the base — a push to ANYTHING would have failed loudly right here.
  mkdir -p "$1/hooks"
  printf '#!/usr/bin/env bash\necho "test remote: every write is rejected" >&2\nexit 1\n' > "$1/hooks/pre-receive"
  chmod +x "$1/hooks/pre-receive"
}
mk_rewritten_bare(){ # mk_rewritten_bare <dest-bare-path> — a fresh origin replaying repo10's own
  # timeline (SHA1 -> SHA2, then SCRATCH10's force-push + after-rewrite commit) — independent of BARE10
  q git init -q --bare -b main "$1"
  q git -C "$1" config receive.denyDeleteCurrent ignore
  q git -C "$SEED10" push -q "$1" main:main
  q git -C "$SCRATCH10" push -q --force "$1" main:main
}
clone_rewritten(){ # clone_rewritten <dest-dir> [reject-all] — a fresh origin + clone at the post-rewrite
  # state, seeded prev=SHA2; with "reject-all" the bare then refuses every further write
  mk_rewritten_bare "$1.git"
  q git clone -q "$1.git" "$1"
  seed_prev "$1" main "$SHA2"
  [[ "${2:-}" == "reject-all" ]] && install_reject_all_hook "$1.git"
}
clone_deleted(){ # clone_deleted <dest-dir> [reject-all] — a fresh origin at SHA1->SHA2, clone (prev=SHA2
  # seeded), THEN main deleted; with "reject-all" the bare then refuses every further write
  local bare="$1.git"
  q git init -q --bare -b main "$bare"
  q git -C "$bare" config receive.denyDeleteCurrent ignore
  q git -C "$SEED10" push -q "$bare" main:main
  q git clone -q "$bare" "$1"
  seed_prev "$1" main "$SHA2"
  q git -C "$SEED10" push -q "$bare" --delete main
  [[ "${2:-}" == "reject-all" ]] && install_reject_all_hook "$bare"
}
RESCUE_BRANCH="rescue-${SHA2:0:12}"  # doctor derives it the same way (prev[:12]) — SHA2 is prev throughout repo10

OUT=$(cd "$WORK10" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
SAVE_CMD=$(extract_save_cmd <<<"$OUT")
ok "AC2 rewritten base: ERROR names the lost commit"        "has \"ERROR base branch 'main' was rewritten on origin: commit $SHA2 is no longer in its history\""
ok "AC2 rewritten base: says how to see what changed"       "has \"git log $SHA2..refs/remotes/origin/main\" && has \"git log refs/remotes/origin/main..$SHA2\""
ok "AC2 rewritten base: the printed command contains no push, at all"  '! grep -q push <<<"$SAVE_CMD"'
ok "AC2 rewritten base: says restoring main is a person's decision, not the script's" \
  'has "decisions for a person, not this script"'
ok "AC2 rewritten base: says how to accept an intentional rewrite, absolute script path" \
  "has \"then accept it with: bash $SCRIPT --accept-base\""
ok "AC2 rewritten base: doctor exits 1"                '[[ $rc -eq 1 ]]'
ok "AC2 rewritten base: seen commit NOT advanced (keeps reporting until fixed)" 'seen_has "$WORK10" "main $SHA2"'

# execute the printed SAVE command verbatim, from its own clone's cwd (an arbitrary project checkout,
# no bin/ dir, nothing pocket-it-specific), against a remote that rejects every write — must run clean,
# must leave the ENTIRE remote ref set untouched, must create a local rescue branch, must pass the real
# push guard, and must leave doctor RED (restoring main is still a human call) until --accept-base.
WORK10R="$S/repo10-work-recover"; clone_rewritten "$WORK10R" reject-all
LOCAL_BEFORE=$(git -C "$WORK10R" for-each-ref --format='%(refname) %(objectname)' refs/heads | sort)
LS_ALL_BEFORE=$(git -C "$WORK10R" ls-remote origin)
GRC=$(guard_rc "$WORK10R" "$SAVE_CMD")
( cd "$WORK10R" && eval "$SAVE_CMD" ) >/dev/null 2>&1; save_rc=$?
LOCAL_AFTER=$(git -C "$WORK10R" for-each-ref --format='%(refname) %(objectname)' refs/heads | sort)
LS_ALL_AFTER=$(git -C "$WORK10R" ls-remote origin)
ok "save command: runs clean against a remote that rejects every write" '[[ $save_rc -eq 0 ]]'
ok "save command: the ENTIRE remote ref set is byte-identical before/after"  '[[ "$LS_ALL_BEFORE" == "$LS_ALL_AFTER" ]]'
ok "save command: local rescue branch created, pointing at the lost commit" \
  '[[ "$(git -C "$WORK10R" rev-parse "refs/heads/$RESCUE_BRANCH")" == "$SHA2" ]]'
EXPECTED_LOCAL_AFTER=$(printf '%s\n%s\n' "$LOCAL_BEFORE" "refs/heads/$RESCUE_BRANCH $SHA2" | sort)
ok "save command: adds only the rescue branch locally, nothing pre-existing discarded" \
  '[[ "$LOCAL_AFTER" == "$EXPECTED_LOCAL_AFTER" ]]'
ok "save command: the pocket-it push guard allows it, even with base=main"   '[[ $GRC -eq 0 ]]'
OUT_POST_SAVE=$(cd "$WORK10R" && bash "$SCRIPT"); rc_post_save=$?
ok "save command alone: doctor stays RED (restoring main is still a human decision)" \
  '[[ $rc_post_save -eq 1 ]] && grep -q "was rewritten on origin" <<<"$OUT_POST_SAVE"'
ACCEPT_CMD_R=$(extract_accept_cmd <<<"$OUT_POST_SAVE")
( cd "$WORK10R" && eval "$ACCEPT_CMD_R" ) >/dev/null 2>&1; accept_r_rc=$?
OUT_POST_ACCEPT_R=$(cd "$WORK10R" && bash "$SCRIPT")
ok "after the save AND --accept-base: doctor turns green"  \
  '[[ $accept_r_rc -eq 0 ]] && ! grep -q "was rewritten on origin" <<<"$OUT_POST_ACCEPT_R"'

# mutation: reintroduce a push of the rescue branch (round 4's own mistake) — on a FRESH clone WITHOUT
# the reject-all hook (so the push can actually land and prove it moved something), the mutated command
# must change the remote's ref set, proving check (b) above is not vacuous; against the reject-all
# remote the same mutated command must fail outright (the hook catches what the diff would have too).
# (the pocket-it push guard is not expected to, and does not, block this mutation: a push to a branch
# named rescue-<sha12> is a legitimate push to a non-base branch by the guard's own, narrower, threat
# model — §6.1 of guard.sh. It is doctor's OWN job never to print it, which is exactly what the diff
# and reject-all checks below measure.)
WORK10MA="$S/repo10-work-mutA"; clone_rewritten "$WORK10MA"
MUT_SAVE_CMD="$SAVE_CMD && git push origin $RESCUE_BRANCH"
LS_ALL_BEFORE_MA=$(git -C "$WORK10MA" ls-remote origin)
( cd "$WORK10MA" && eval "$MUT_SAVE_CMD" ) >/dev/null 2>&1
LS_ALL_AFTER_MA=$(git -C "$WORK10MA" ls-remote origin)
ok "mutation (push the rescue branch): actually changes the remote ref set — proves check (b) is not vacuous" \
  '[[ "$LS_ALL_BEFORE_MA" != "$LS_ALL_AFTER_MA" ]]'
WORK10MAR="$S/repo10-work-mutA-reject"; clone_rewritten "$WORK10MAR" reject-all
MUT_SAVE_CMD_R="$SAVE_CMD && git push origin $RESCUE_BRANCH"
( cd "$WORK10MAR" && eval "$MUT_SAVE_CMD_R" ) >/dev/null 2>&1; mut_r_rc=$?
ok "mutation (push the rescue branch), against the reject-all remote: fails (the hook catches it too)" '[[ $mut_r_rc -ne 0 ]]'

# --accept-base: extract and run the printed command on ITS OWN fresh clone's cwd (no bin/doctor.sh
# there); a human decision that only ever updates doctor's own bookkeeping — never a git ref/branch/commit
WORK10ACC="$S/repo10-work-accept"; clone_rewritten "$WORK10ACC"
OUT_FOR_ACCEPT=$(cd "$WORK10ACC" && bash "$SCRIPT")
ACCEPT_CMD=$(extract_accept_cmd <<<"$OUT_FOR_ACCEPT")
BEFORE_HEAD=$(git -C "$WORK10ACC" rev-parse HEAD); BEFORE_BRANCHES=$(git -C "$WORK10ACC" for-each-ref --format='%(refname)' refs/heads | sort)
OUT_ACCEPT=$(cd "$WORK10ACC" && eval "$ACCEPT_CMD"); rc_accept=$?
ok "--accept-base command, run as printed, from the project's own cwd: exits 0"  '[[ $rc_accept -eq 0 ]]'
ok "--accept-base: confirms the new baseline"  'grep -q "accepted at" <<<"$OUT_ACCEPT"'
ok "--accept-base: touches no local ref or commit (HEAD/branches unchanged)" \
  '[[ "$(git -C "$WORK10ACC" rev-parse HEAD)" == "$BEFORE_HEAD" ]] && [[ "$(git -C "$WORK10ACC" for-each-ref --format="%(refname)" refs/heads | sort)" == "$BEFORE_BRANCHES" ]]'
ok "--accept-base: doctor is quiet on the very next run (rewrite no longer flagged)" \
  '! grep -q "was rewritten on origin" <<<"$(cd "$WORK10ACC" && bash "$SCRIPT")"'

# mutation B: revert the accept command to round 2's hardcoded relative form ("bash bin/doctor.sh
# --accept-base") — running it, as printed, from a project clone (no bin/ subdirectory there) must
# fail exactly the way round 2 failed in production: "No such file or directory"
WORK10MB="$S/repo10-work-mutB"; clone_rewritten "$WORK10MB"
OUT_FOR_MB=$(cd "$WORK10MB" && bash "$SCRIPT")
MUT_ACCEPT=$(mktemp "${TMPDIR:-/tmp}/doctor-mut.XXXXXX")
# PI-45: single-line address (site 2 of 6). The anchor is declared once, counted whole-line in the
# captured source, and the address is then built from that same string — so the line the gate
# counted and the line sed matches cannot drift apart.
ACCEPT_ANCHOR='accept_cmd = f"bash {shlex.quote(doctor_abs)} --accept-base"'
MUT_ACCEPT_OK=0
if src_anchors "$SCRIPT_SRC" line 1 "$ACCEPT_ANCHOR"; then
  { printf '/^%s$/c\\\n' "$(sed_lit "$ACCEPT_ANCHOR")"
    printf '%s\n' 'accept_cmd = "bash bin/doctor.sh --accept-base"  # MUTATED round-2 form for PI-29 round-3 proof'
  } > "$MUT_ACCEPT.sed"
  sed -f "$MUT_ACCEPT.sed" "$SCRIPT_SRC" > "$MUT_ACCEPT"; rm -f "$MUT_ACCEPT.sed"
  mutation_applied "$MUT_ACCEPT" 'MUTATED round-2 form for PI-29 round-3 proof' && MUT_ACCEPT_OK=1
fi
if [[ $MUT_ACCEPT_OK -eq 1 ]]; then
  OUT_MA=$(cd "$WORK10MB" && bash "$MUT_ACCEPT"); rc_ma=$?
  ACCEPT_CMD_MA=$(extract_accept_cmd <<<"$OUT_MA")
  ERR_MA=$( ( cd "$WORK10MB" && eval "$ACCEPT_CMD_MA" ) 2>&1 ); rc_ma_run=$?
  ok "mutation B (round-2 accept form): the printed command, run from the project, fails (no bin/doctor.sh there) — proves the test is not vacuous" \
    '[[ $rc_ma_run -ne 0 ]] && grep -qi "no such file" <<<"$ERR_MA"'
else
  ok "mutation B (round-2 accept form): cannot self-mutate: $MUT_WHY" 'false'
fi
rm -f "$MUT_ACCEPT"

# AC3: deleted base — an ERROR naming the last known-good commit to recover from (unaffected by
# locale: classified from `ls-remote --exit-code`'s exit status, never from stderr text — see the
# fake-git locale regression tests below, repo 13). Its own fresh origin (SHA1->SHA2 only, no
# rewrite needed to test a deletion) so it is independent of everything repo10 did above.
WORK10DEL="$S/repo10-work-deleted"; clone_deleted "$WORK10DEL"
OUT=$(cd "$WORK10DEL" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
SAVE_CMD_DEL=$(extract_save_cmd_del <<<"$OUT")
ok "AC3 deleted base: ERROR reported"                  'has "ERROR base branch '"'"'main'"'"' no longer exists on origin"'
ok "AC3 deleted base: doctor exits 1"                  '[[ $rc -eq 1 ]]'
ok "AC3 deleted base: the printed command contains no push, at all"  '! grep -q push <<<"$SAVE_CMD_DEL"'

# execute the printed SAVE command for a deleted base (finding 2), against a remote that rejects every
# write — must run clean, leave the entire remote ref set untouched, and land a local rescue branch.
WORK10DELR="$S/repo10-del-recover"; clone_deleted "$WORK10DELR" reject-all
LS_ALL_BEFORE_DEL=$(git -C "$WORK10DELR" ls-remote origin)
GRC_DEL=$(guard_rc "$WORK10DELR" "$SAVE_CMD_DEL")
( cd "$WORK10DELR" && eval "$SAVE_CMD_DEL" ) >/dev/null 2>&1; save_rc_del=$?
LS_ALL_AFTER_DEL=$(git -C "$WORK10DELR" ls-remote origin)
ok "deleted base, save command: runs clean against a remote that rejects every write" '[[ $save_rc_del -eq 0 ]]'
ok "deleted base, save command: the ENTIRE remote ref set is byte-identical before/after" \
  '[[ "$LS_ALL_BEFORE_DEL" == "$LS_ALL_AFTER_DEL" ]]'
ok "deleted base, save command: local rescue branch created, pointing at the last-seen commit" \
  '[[ "$(git -C "$WORK10DELR" rev-parse "refs/heads/$RESCUE_BRANCH")" == "$SHA2" ]]'
ok "deleted base, save command: the pocket-it push guard allows it"         '[[ $GRC_DEL -eq 0 ]]'
OUT_POST_DELR=$(cd "$WORK10DELR" && bash "$SCRIPT"); rc_post_delr=$?
ok "deleted base, save command alone: doctor stays RED (base still gone, a person restores it)" '[[ $rc_post_delr -eq 1 ]]'

# mutation: reintroduce a push of the rescue branch for the deleted-base command — on a FRESH clone
# WITHOUT the reject-all hook the push must actually land (proving the diff check is not vacuous), and
# against the reject-all remote it must fail.
# (same note as above: the guard correctly ALLOWS a push to rescue-<sha12>, a non-base branch — it is
# doctor's own job never to print it; that is what the two checks below measure.)
WORK10DELMA="$S/repo10-del-mutA"; clone_deleted "$WORK10DELMA"
MUT_SAVE_CMD_DEL="$SAVE_CMD_DEL && git push origin $RESCUE_BRANCH"
LS_ALL_BEFORE_DELMA=$(git -C "$WORK10DELMA" ls-remote origin)
( cd "$WORK10DELMA" && eval "$MUT_SAVE_CMD_DEL" ) >/dev/null 2>&1
LS_ALL_AFTER_DELMA=$(git -C "$WORK10DELMA" ls-remote origin)
ok "deleted base, mutation (push the rescue branch): actually changes the remote ref set — proves the diff check is not vacuous" \
  '[[ "$LS_ALL_BEFORE_DELMA" != "$LS_ALL_AFTER_DELMA" ]]'
WORK10DELMAR="$S/repo10-del-mutA-reject"; clone_deleted "$WORK10DELMAR" reject-all
( cd "$WORK10DELMAR" && eval "$MUT_SAVE_CMD_DEL" ) >/dev/null 2>&1; mut_delr_rc=$?
ok "deleted base, mutation (push the rescue branch), against the reject-all remote: fails" '[[ $mut_delr_rc -ne 0 ]]'

# --accept-base on a DELETED base (finding 3): must say it is deleted and what to do, never "try
# again once reachable" (that phrase is only true for a transient/unreachable origin), and its own
# printed save command must have the same properties as the ones above. base-seen read BEFORE running
# --accept-base (round 4's own test read it AFTER, comparing the file with itself — vacuous).
WORK10DELACC="$S/repo10-del-accept"; clone_deleted "$WORK10DELACC" reject-all
BASE_SEEN_BEFORE=$(cat "$(common "$WORK10DELACC")/pocket-it/base-seen" 2>/dev/null)
OUT_ACCEPT_DEL=$(cd "$WORK10DELACC" && bash "$SCRIPT" --accept-base); rc_accept_del=$?
ok "--accept-base on deleted base: exits 1"                          '[[ $rc_accept_del -eq 1 ]]'
ok "--accept-base on deleted base: says it no longer exists, not 'try again once reachable'" \
  'grep -q "no longer exists on origin" <<<"$OUT_ACCEPT_DEL" && ! grep -qi "try again once reachable" <<<"$OUT_ACCEPT_DEL"'
ok "--accept-base on deleted base: says how to save the lost commit locally, no git-push command anywhere" \
  'grep -q "save the lost commit locally before it can be lost: git branch rescue-" <<<"$OUT_ACCEPT_DEL" && ! grep -q "git push" <<<"$OUT_ACCEPT_DEL"'
ok "--accept-base on deleted base: base-seen left untouched (compared against the value read BEFORE the run)" \
  '[[ "$(cat "$(common "$WORK10DELACC")/pocket-it/base-seen" 2>/dev/null)" == "$BASE_SEEN_BEFORE" ]]'

SAVE_CMD_DEL_ACC=$(extract_save_cmd_del_acc <<<"$OUT_ACCEPT_DEL")
ok "--accept-base on deleted base: extracted save command itself contains no push"  '! grep -q push <<<"$SAVE_CMD_DEL_ACC"'
LS_ALL_BEFORE_DELACC=$(git -C "$WORK10DELACC" ls-remote origin)
GRC_DELACC=$(guard_rc "$WORK10DELACC" "$SAVE_CMD_DEL_ACC")
( cd "$WORK10DELACC" && eval "$SAVE_CMD_DEL_ACC" ) >/dev/null 2>&1; save_rc_delacc=$?
LS_ALL_AFTER_DELACC=$(git -C "$WORK10DELACC" ls-remote origin)
ok "--accept-base on deleted base, save command: runs clean against a remote that rejects every write"  '[[ $save_rc_delacc -eq 0 ]]'
ok "--accept-base on deleted base, save command: the ENTIRE remote ref set is byte-identical before/after" \
  '[[ "$LS_ALL_BEFORE_DELACC" == "$LS_ALL_AFTER_DELACC" ]]'
ok "--accept-base on deleted base, save command: local rescue branch created, pointing at the last-seen commit" \
  '[[ "$(git -C "$WORK10DELACC" rev-parse "refs/heads/$RESCUE_BRANCH")" == "$SHA2" ]]'
ok "--accept-base on deleted base, save command: the pocket-it push guard allows it"  '[[ $GRC_DELACC -eq 0 ]]'

# finding 5, mutation: doctor's --accept-base, on a deleted base, incorrectly updates base-seen anyway
# — the "left untouched" check above must catch it (proves it is no longer vacuous now that it reads
# the baseline BEFORE the run).
WORK10DELACCMUT="$S/repo10-del-accept-mutBS"; clone_deleted "$WORK10DELACCMUT"
BS_BEFORE_MUT=$(cat "$(common "$WORK10DELACCMUT")/pocket-it/base-seen" 2>/dev/null)
MUT_BS=$(mktemp "${TMPDIR:-/tmp}/doctor-mut.XXXXXX")
# PI-45 (site 3 of 6): the boundaries are located with str.index, which silently takes the FIRST of
# several — so each is required to occur exactly once, and the reason travels back on stderr to be
# named in this block's own failure instead of leaving $MUT_BS empty for the base-seen assertion to
# be blamed for. mutation_applied then confirms what came out is a whole script carrying the marker.
if MUT_WHY=$(python3 - "$SCRIPT_SRC" 2>&1 >"$MUT_BS" <<'PYEOF'
import sys
src = open(sys.argv[1]).read()
for lit in ("if accept_base:", "if common_dir and has_origin:"):
    n = src.count(lit)
    if n != 1:  # a doubled boundary would silently move the segment, not fail
        sys.stderr.write("boundary %r occurs %d times in bin/doctor.sh, not once" % (lit, n)); sys.exit(1)
idx_accept = src.index("if accept_base:")
idx_common = src.index("if common_dir and has_origin:")
segment = src[idx_accept:idx_common]
marker = "        sys.exit(1)\n"
if marker not in segment:
    sys.stderr.write("the first sys.exit(1) inside accept_base is no longer there"); sys.exit(1)
pos = segment.index(marker)  # the FIRST sys.exit(1) inside accept_base closes the "deleted" branch
mutated_segment = segment[:pos] + '        _save_seen(seen_file, {**seen, base: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"})  # MUTATED round-5 proof\n' + segment[pos:]
sys.stdout.write(src[:idx_accept] + mutated_segment + src[idx_common:])
PYEOF
) && mutation_applied "$MUT_BS" 'MUTATED round-5 proof'; then
  OUT_MUT_BS=$(cd "$WORK10DELACCMUT" && bash "$MUT_BS" --accept-base); rc_mut_bs=$?
  ok "mutation (accept-base on deleted base silently updates base-seen): base-seen check catches it — proves it is not vacuous" \
    '[[ "$(cat "$(common "$WORK10DELACCMUT")/pocket-it/base-seen" 2>/dev/null)" != "$BS_BEFORE_MUT" ]]'
else
  ok "mutation (accept-base on deleted base silently updates base-seen): cannot self-mutate: $MUT_WHY" 'false'
fi
rm -f "$MUT_BS"

# finding 6: the lost commit itself already pruned from the local object database — doctor must say so
# and print NO command (a command building on a missing object would just fail), for both the normal
# run and --accept-base. PRUNED_SHA is a valid-looking sha that was never written to any object store
# (git hash-object without -w only computes the hash).
PRUNED_SHA=$(git hash-object --stdin <<<"pi-29-round5-pruned-object")

WORK10PRUNE="$S/repo10-del-pruned"; clone_deleted "$WORK10PRUNE"
printf 'main %s\n' "$PRUNED_SHA" > "$(common "$WORK10PRUNE")/pocket-it/base-seen"
OUT_PRUNE=$(cd "$WORK10PRUNE" && bash "$SCRIPT"); rc_prune=$?
echo "$OUT_PRUNE" | sed 's/^/      | /'
ok "deleted base, prev pruned locally: ERROR, exits 1"                     '[[ $rc_prune -eq 1 ]]'
ok "deleted base, prev pruned locally: says gone from the local object database" \
  'grep -q "gone from the local object database" <<<"$OUT_PRUNE"'
ok "deleted base, prev pruned locally: prints no rescue/push command (there is nothing to run it on)" \
  '! grep -q "git branch rescue-" <<<"$OUT_PRUNE" && ! grep -q push <<<"$OUT_PRUNE"'

WORK10PRUNEACC="$S/repo10-del-pruned-acc"; clone_deleted "$WORK10PRUNEACC"
printf 'main %s\n' "$PRUNED_SHA" > "$(common "$WORK10PRUNEACC")/pocket-it/base-seen"
OUT_PRUNE_ACC=$(cd "$WORK10PRUNEACC" && bash "$SCRIPT" --accept-base); rc_prune_acc=$?
ok "--accept-base, deleted base, prev pruned locally: exits 1"             '[[ $rc_prune_acc -eq 1 ]]'
ok "--accept-base, deleted base, prev pruned locally: says gone from the local object database" \
  'grep -q "gone from the local object database" <<<"$OUT_PRUNE_ACC"'
ok "--accept-base, deleted base, prev pruned locally: prints no rescue/push command" \
  '! grep -q "git branch rescue-" <<<"$OUT_PRUNE_ACC" && ! grep -q push <<<"$OUT_PRUNE_ACC"'

# --- repo 11: the seen commit is shared across worktrees of the same repo (AC5) ---
BARE11="$S/repo11-origin.git"; SEED11="$S/repo11-seed"
SHA11=$(seed_origin "$BARE11" "$SEED11")
WORK11="$S/repo11-work"
q git clone -q "$BARE11" "$WORK11"
WT11="$S/repo11-wt2"
q git -C "$WORK11" worktree add -q -b repo11-wt2-branch "$WT11" main

# a first run from the SECOND worktree records the seen commit
q sh -c "cd '$WT11' && bash '$SCRIPT'"
ok "AC5 setup: worktree 2 recorded the seen commit"    'seen_has "$WORK11" "main $SHA11"'

printf 'v2\n' > "$SEED11/f.txt"; q git -C "$SEED11" add -A; q git -C "$SEED11" commit -qm c2; q git -C "$SEED11" push -q origin main
SHA11B=$(git -C "$SEED11" rev-parse HEAD)

# the FIRST worktree, which never ran doctor before, must see what the second one recorded —
# a normal advance from $SHA11, not a first-ever run (which would silently record and never compare)
OUT=$(cd "$WORK11" && bash "$SCRIPT")
ok "AC5 the other worktree sees it: normal advance, no report" '! has "base branch '"'"'main'"'"'"'
ok "AC5 seen commit shared, advanced from the other worktree's own record" 'seen_has "$WORK11" "main $SHA11B"'

# --- repo 12: origin unreachable — a warn, never a false ERROR (Notes: no network must not lie) ---
BARE12="$S/repo12-origin.git"; SEED12="$S/repo12-seed"
seed_origin "$BARE12" "$SEED12" >/dev/null
WORK12="$S/repo12-work"
q git clone -q "$BARE12" "$WORK12"
rm -rf "$BARE12"   # origin vanishes from under the clone — unreachable, not "branch deleted"
OUT=$(cd "$WORK12" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "unreachable origin: warn, not ERROR"            'has "warn  could not verify base branch '"'"'main'"'"' integrity"'
ok "unreachable origin: no false ERROR"             '! has "ERROR base branch"'
ok "unreachable origin: warnings never fail doctor" '[[ $rc -eq 0 ]]'

# --- repo 13: locale regression (finding 4, round 3) — the earlier "run under LC_ALL=it_IT" tests
# are vacuous on this machine because Apple git ships with no NLS translations at all (confirmed by
# hand: LC_ALL=it_IT.UTF-8 does not change a single message here), so the old, buggy, text-matching
# classifier would have passed those tests too. A fake `git` on PATH, put in front of the real one,
# translates ONLY the one message a text-based classifier would have read (fetch's "couldn't find
# remote ref"), regardless of locale — simulating an NLS build where that string is never English —
# so the round-3 fix (classify from `ls-remote --exit-code` alone) is proven to not depend on it,
# and a mutation that reintroduces text-matching is proven to break under exactly this fake.
FAKEGIT="$S/fakegit"; mkdir -p "$FAKEGIT"
cat > "$FAKEGIT/git" <<'GITEOF'
#!/usr/bin/env bash
if [[ "$1" == "fetch" ]]; then
  err=$("$FAKE_GIT_REAL" "$@" 2>&1 1>/dev/null); rc=$?
  if [[ $rc -ne 0 ]] && grep -qi "couldn.t find remote ref" <<<"$err"; then
    echo "fatal: impossibile trovare il ref remoto" >&2
    exit "$rc"
  fi
  "$FAKE_GIT_REAL" "$@"
  exit $?
fi
exec "$FAKE_GIT_REAL" "$@"
GITEOF
chmod +x "$FAKEGIT/git"
export FAKE_GIT_REAL="$(command -v git)"

BARE13="$S/repo13-origin.git"; SEED13="$S/repo13-seed"
seed_origin "$BARE13" "$SEED13" >/dev/null
WORK13="$S/repo13-work"
q git clone -q "$BARE13" "$WORK13"
(cd "$WORK13" && bash "$SCRIPT") >/dev/null   # AC4: record the baseline
q git -C "$SEED13" push -q origin --delete main   # delete the base branch

OUT_FAKE=$(cd "$WORK13" && PATH="$FAKEGIT:$PATH" LC_ALL=it_IT.UTF-8 LANGUAGE=it bash "$SCRIPT"); rc_fake=$?
echo "$OUT_FAKE" | sed 's/^/      | /'
ok "round 3, under a git that never speaks English on this message: deleted base still an ERROR" \
  '[[ $rc_fake -eq 1 ]] && grep -q "ERROR base branch .main. no longer exists" <<<"$OUT_FAKE"'

MUT_LOCALE=$(mktemp "${TMPDIR:-/tmp}/doctor-mut.XXXXXX")
# PI-45 (site 4 of 6) — the only RANGE address in this file, and the one the first review round
# caught: with the closing anchor edited by one trailing comment in bin/doctor.sh, this range ran to
# end of file and handed the assertion below a 74-line fragment that still contained the marker, so
# the marker grep said "applied" and the failure came out as "degrades to a warn", naming a check
# that never ran. Both anchors are therefore declared here, counted whole-line and exactly once in
# the captured source BEFORE sed is allowed to run, with the address built from those same two
# strings; mutant_whole then rejects any fragment the range could still produce.
CLASSIFY_OPEN='def _classify_base(base, env):'
CLASSIFY_CLOSE='    return "unreachable", (stderr.splitlines()[-1] if stderr else "no network")'
MUT_LOCALE_OK=0
if src_anchors "$SCRIPT_SRC" line 1 "$CLASSIFY_OPEN" "$CLASSIFY_CLOSE"; then
  { printf '/^%s$/,/^%s$/c\\\n' "$(sed_lit "$CLASSIFY_OPEN")" "$(sed_lit "$CLASSIFY_CLOSE")"
    cat <<'SEDEOF'
def _classify_base(base, env):\
    f = subprocess.run(["git", "fetch", "--quiet", "origin", f"+refs/heads/{base}:refs/remotes/origin/{base}"], capture_output=True, text=True, env=env)  # MUTATED round-2 form\
    if f.returncode == 0: return "ok", None\
    stderr = f.stderr.strip()\
    if re.search(r"couldn.t find remote ref", stderr, re.I): return "deleted", None\
    return "unreachable", (stderr.splitlines()[-1] if stderr else "no network")
SEDEOF
  } > "$MUT_LOCALE.sed"
  sed -f "$MUT_LOCALE.sed" "$SCRIPT_SRC" > "$MUT_LOCALE"
  rm -f "$MUT_LOCALE.sed"
  mutation_applied "$MUT_LOCALE" 'MUTATED round-2 form' && MUT_LOCALE_OK=1
fi
if [[ $MUT_LOCALE_OK -eq 1 ]]; then
  OUT_MUT_FAKE=$(cd "$WORK13" && PATH="$FAKEGIT:$PATH" LC_ALL=it_IT.UTF-8 LANGUAGE=it bash "$MUT_LOCALE"); rc_mut_fake=$?
  echo "$OUT_MUT_FAKE" | sed 's/^/      | /'
  ok "mutation (round-2 text-based classify), same fake git: degrades to a warn — proves the test is not vacuous" \
    '[[ $rc_mut_fake -eq 0 ]] && ! grep -q "ERROR base branch" <<<"$OUT_MUT_FAKE" && grep -q "warn  could not verify base branch" <<<"$OUT_MUT_FAKE"'
else
  ok "mutation (round-2 text-based classify): cannot self-mutate: $MUT_WHY" 'false'
fi
rm -f "$MUT_LOCALE"

# --- repo 14: a merged PR left on a non-Done task (PI-37) — real case: PI-29's PR #60, merged 13/09,
# **Status** left "Needs Work" by an earlier review round and never set back to Done; reconstructed
# here as a fixture since the real file was hand-fixed on 15/09 and no longer shows the defect.
# `gh` is entirely simulated below — a fake binary put in front of the real one on PATH answers
# `gh auth status` and `gh pr list --state merged` from a fixed, in-memory table, never a real
# network call. Class covered: status (the full non-final set + one non-canonical value) x PR
# outcome (merged / open / closed-without-merge / absent-in-three-spellings).
task_pr(){ # task_pr <path> <status> <pr-field> — task file with a PR field, otherwise well-formed
  mkdir -p "$(dirname "$1")"
  printf '# %s\n\n**Status**: %s\n**Label**: DevOps\n**Files**: `x`\n**TAD**: none\n**PR**: %s\n\n## Acceptance criteria\n- ok\n' \
    "$(basename "$1" .md)" "$2" "$3" > "$1"
}
FAKEGH="$S/fakegh"; mkdir -p "$FAKEGH"
cat > "$FAKEGH/gh" <<'GHEOF'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then exit 0; fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then printf '[{"number":60},{"number":42}]'; exit 0; fi
exit 1
GHEOF
chmod +x "$FAKEGH/gh"

R14="$S/repo14"
q git init -q -b main "$R14"
task_pr "$R14/tasks/PI-900-todo-merged.md"          "Todo"         "https://github.com/x/y/pull/60"        # AC1/AC2: non-final status, merged -> warn
task_pr "$R14/tasks/PI-901-inprogress-merged.md"    "In Progress"  "https://github.com/x/y/pull/60"        # AC2: same, another non-final status
task_pr "$R14/tasks/PI-902-needswork-merged.md"     "Needs Work"   "https://github.com/x/y/pull/60"        # AC2: the real PI-29 shape
task_pr "$R14/tasks/PI-903-wip-merged.md"           "WIP"          "https://github.com/x/y/pull/60"        # AC2: non-canonical status, still not Done
task_pr "$R14/tasks/PI-904-done-merged.md"          "Done"         "https://github.com/x/y/pull/42"        # AC2: Done + merged -> no warn
task_pr "$R14/tasks/PI-905-needswork-open.md"       "Needs Work"   "https://github.com/x/y/pull/99"        # AC2: PR open (99 not in the merged table) -> no warn
task_pr "$R14/tasks/PI-906-needswork-closed.md"     "Needs Work"   "#77 (chiusa senza merge)"               # AC2: PR closed without merge -> no warn
task_pr "$R14/tasks/PI-907-needswork-dash.md"       "Needs Work"   "—"                                      # AC2: PR absent, dash -> no warn
task_pr "$R14/tasks/PI-908-needswork-empty.md"      "Needs Work"   ""                                       # AC2: PR absent, empty -> no warn
task_pr "$R14/tasks/PI-909-needswork-none.md"       "Needs Work"   "none"                                   # AC2: PR absent, "none" -> no warn
q git -C "$R14" add -A; q git -C "$R14" commit -qm board

OUT=$(cd "$R14" && PATH="$FAKEGH:$PATH" bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "AC1/AC2 Todo + merged: warns, names file, status and PR number"       'has "warn  tasks/PI-900-todo-merged.md: PR #60 is merged but **Status** is '"'"'Todo'"'"' — set it to Done"'
ok "AC2 In Progress + merged: warns"                                      'has "warn  tasks/PI-901-inprogress-merged.md: PR #60 is merged but **Status** is '"'"'In Progress'"'"'"'
ok "AC2 Needs Work + merged: warns (the real PI-29 shape)"                 'has "warn  tasks/PI-902-needswork-merged.md: PR #60 is merged but **Status** is '"'"'Needs Work'"'"'"'
ok "AC2 non-canonical status (WIP) + merged: warns"                       'has "warn  tasks/PI-903-wip-merged.md: PR #60 is merged but **Status** is '"'"'WIP'"'"'"'
ok "AC2 Done + merged: no warn"                                           '! has "PI-904-done-merged.md: PR"'
ok "AC2 PR open (not in merged table): no warn"                           '! has "PI-905-needswork-open.md: PR"'
ok "AC2 PR closed without merge: no warn"                                 '! has "PI-906-needswork-closed.md: PR"'
ok "AC2 PR absent (dash): no warn"                                        '! has "PI-907-needswork-dash.md: PR"'
ok "AC2 PR absent (empty): no warn"                                       '! has "PI-908-needswork-empty.md: PR"'
ok "AC2 PR absent (\"none\"): no warn"                                    '! has "PI-909-needswork-none.md: PR"'
ok "warning count: the 4 merged+non-Done fixtures plus the missing-config warning, nothing else" 'has "doctor: 0 error(s), 5 warning(s), 10 task file(s)"'
ok "AC1 exit stays 0 (a warning never fails doctor)"                      '[[ $rc -eq 0 ]]'

# AC4: doctor is read-only — a second run changes nothing on disk
BEFORE14=$(cd "$R14" && git status --porcelain)
(cd "$R14" && PATH="$FAKEGH:$PATH" bash "$SCRIPT") >/dev/null
AFTER14=$(cd "$R14" && git status --porcelain)
ok "AC4 two runs back to back: git status --porcelain unchanged, no task file touched" '[[ "$BEFORE14" == "$AFTER14" ]]'

# AC3a: no `gh` reachable at all (a PATH holding only what doctor.sh itself needs, no gh anywhere on it)
# — silent skip, no warning, no error, and the rest of doctor.sh keeps working normally.
NOGH_PATH="/usr/bin:/bin"
OUT_NOGH=$(cd "$R14" && PATH="$NOGH_PATH" bash "$SCRIPT"); rc_nogh=$?
ok "AC3a no gh on PATH: none of the merged-PR warnings fire"              '! grep -q "PR #60 is merged" <<<"$OUT_NOGH"'
ok "AC3a no gh on PATH: no ERROR from this check either"                  '! grep -q "ERROR.*PR #" <<<"$OUT_NOGH"'
ok "AC3a no gh on PATH: exit still 0 (nothing else broke)"                '[[ $rc_nogh -eq 0 ]]'

# AC3b: gh present but unauthenticated / no permission / no network — `gh auth status` fails fast.
FAKEGH_NOAUTH="$S/fakegh-noauth"; mkdir -p "$FAKEGH_NOAUTH"
cat > "$FAKEGH_NOAUTH/gh" <<'GHEOF'
#!/usr/bin/env bash
exit 1
GHEOF
chmod +x "$FAKEGH_NOAUTH/gh"
OUT_NOAUTH=$(cd "$R14" && PATH="$FAKEGH_NOAUTH:$PATH" bash "$SCRIPT"); rc_noauth=$?
ok "AC3b gh auth status fails: no merged-PR warning, silent skip"         '! grep -q "PR #60 is merged" <<<"$OUT_NOAUTH"'
ok "AC3b gh auth status fails: exit still 0"                              '[[ $rc_noauth -eq 0 ]]'

# AC3c: `gh auth status` present but never answers (network hangs) — this is the "no long wait"
# clause of AC3: the check must not depend on any wait longer than its own timeout. `exec sleep`
# replaces the fake gh process itself (no child left behind once Python's own subprocess timeout
# kills it), so the bound below is exactly the timeout the check applies, not an approximation.
FAKEGH_HANG="$S/fakegh-hang"; mkdir -p "$FAKEGH_HANG"
cat > "$FAKEGH_HANG/gh" <<'GHEOF'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then exec sleep 6; fi
exit 1
GHEOF
chmod +x "$FAKEGH_HANG/gh"
T0=$(date +%s)
OUT_HANG=$(cd "$R14" && PATH="$FAKEGH_HANG:$PATH" bash "$SCRIPT"); rc_hang=$?
T1=$(date +%s)
ok "AC3c gh auth status hangs: doctor still returns well under the 6s hang (bounded by its own timeout)" \
  '(( T1 - T0 < 5 ))'
ok "AC3c gh auth status hangs: no merged-PR warning, silent skip"        '! grep -q "PR #60 is merged" <<<"$OUT_HANG"'
ok "AC3c gh auth status hangs: exit still 0"                             '[[ $rc_hang -eq 0 ]]'

# --- mutation: remove the PI-37 check (the block between its own markers) and watch AC1/AC2's
# positive cases go red — proves the tests above are not vacuous. Restored automatically: this runs
# against a throwaway copy, $SCRIPT itself is never touched.
MUT_PI37=$(mktemp "${TMPDIR:-/tmp}/doctor-mut-pi37.XXXXXX")
# PI-45 (site 5 of 6): a RANGE address again, this time in `substr` mode — the address is /.../ and
# not /^...$/, so the gate counts the markers the same way, anywhere on the line. Both are declared
# and required exactly once before the delete runs (a missing END deletes to end of file; a doubled
# BEGIN opens a second range that does the same), and the address is built from those same strings.
PI37_BEGIN='# PI-37 CHECK BEGIN'
PI37_END='# PI-37 CHECK END'
MUT_PI37_OK=0
if src_anchors "$SCRIPT_SRC" substr 1 "$PI37_BEGIN" "$PI37_END"; then
  sed "/$(sed_lit "$PI37_BEGIN")/,/$(sed_lit "$PI37_END")/d" "$SCRIPT_SRC" > "$MUT_PI37"
  # this mutation DELETES, so "applied" is the block being gone, not a marker being present
  if ! mutant_whole "$MUT_PI37"; then :
  elif grep -qF "$PI37_BEGIN" "$MUT_PI37"; then MUT_WHY="the PI-37 block is still present after the delete"
  else MUT_PI37_OK=1
  fi
fi
if [[ $MUT_PI37_OK -eq 1 ]]; then
  OUT_MUT_PI37=$(cd "$R14" && PATH="$FAKEGH:$PATH" bash "$MUT_PI37"); rc_mut_pi37=$?
  echo "$OUT_MUT_PI37" | sed 's/^/      | /'
  ok "mutation: check removed, AC1/AC2 positive cases (Todo/In Progress/Needs Work/WIP + merged) all go red" \
    '! grep -q "PR #60 is merged" <<<"$OUT_MUT_PI37" && [[ $rc_mut_pi37 -eq 0 ]]'
else
  ok "mutation (PI-37 check removed): cannot self-mutate: $MUT_WHY" 'false'
fi
rm -f "$MUT_PI37"

# AC5: run-wave/SKILL.md Step 5 (the step right after `gh pr merge`) carries the same instruction
# quickfix/SKILL.md's own close step already has — checked statically, not by running the skill
# (it is markdown for an agent to read, not a script).
RUNWAVE_SKILL="$(cd .. && pwd -P)/.claude/skills/run-wave/SKILL.md"
ok "AC5 run-wave Step 5 checks the merged PR's task file says Status: Done, and fixes it if not" \
  'grep -A2 "gh pr merge {n} --squash --delete-branch" "$RUNWAVE_SKILL" | grep -q "make sure .tasks/{ID}-\*\.md. says .\*\*Status\*\*: Done. (set it if the developer left it otherwise"'

# --- repo 15: PI-42 — §4b checks exactly the sections the board cites, never a hardcoded set ---
# Invented project, invented section numbers: 5.2/9.9/42.7 exist in the project TAD, 7.6 only in a
# delta; none of these are any real project's numbering, on purpose.
tad_task(){ # tad_task <path> <TAD-line> — minimal task file with a given **TAD**: line
  mkdir -p "$(dirname "$1")"
  printf '# %s\n\n**Status**: Todo\n**Label**: DevOps\n**Files**: `x`\n**TAD**: %s\n\n## Acceptance criteria\n- ok\n' \
    "$(basename "$1" .md)" "$2" > "$1"
}
R15="$S/repo15"
q git init -q -b main "$R15"
mkdir -p "$R15/tech-analysis"
cat > "$R15/tech-analysis/PROJECT_TECH_ANALYSIS.md" <<'EOF'
## 3. Stack
Text.

## 5. Endpoints
### 5.2 Widgets
Text.

## 9. Testing
### 9.9 An oddball number this project alone uses
Text.

## 42. Zeta
### 42.7 Also odd, on purpose
Text.
EOF
cat > "$R15/tech-analysis/WIDGETS_TECH_DELTA.md" <<'EOF'
## Delta for widgets

### 7.6 Delta-only section
Text.
EOF
tad_task "$R15/tasks/PI-9001-no-citation.md"          "none"                                                # AC1/AC4: nothing cited -> silent, even though this TAD lacks the old hardcoded numbers (6.2/7.6/8.1/9.3/11.1)
tad_task "$R15/tasks/PI-9002-unqualified-ok.md"       "§5.2 (endpoints)"                                    # AC1: unqualified citation, section exists in the project TAD -> silent
tad_task "$R15/tasks/PI-9003-delta-ok.md"             "DELTA §7.6"                                          # AC2: DELTA-qualified, section exists only in the delta -> silent
tad_task "$R15/tasks/PI-9004-project-missing-section.md" "PROJECT §6.2"                                     # AC3: PROJECT-qualified, section absent from the project TAD -> one warning
tad_task "$R15/tasks/PI-9005-named-file-ok.md"        "tech-analysis/PROJECT_TECH_ANALYSIS.md (§42.7)"     # AC2 (extra qualifier form): document named directly by path, section present -> silent
tad_task "$R15/tasks/PI-9006-named-file-missing-doc.md" "tech-analysis/GHOST_TECH_ANALYSIS.md (§9.9)"       # AC6: named document does not exist -> one warning naming the document
tad_task "$R15/tasks/PI-9007-combined.md"             "PROJECT §5.2 · DELTA §7.6"                           # both keyword-qualified segments on one line, both resolve -> silent
q git -C "$R15" add -A; q git -C "$R15" commit -qm board

OUT=$(cd "$R15" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "AC1/AC4 unusual, uncited numbering: not one 'subsections' warning (the hardcoded set is gone)" '! has "subsections"'
ok "AC1 unqualified citation to an existing section: silent"                    '! has "PI-9002"'
ok "AC2 DELTA-qualified citation resolved against the delta, section there: silent" '! has "PI-9003"'
ok "AC3 PROJECT-qualified citation to a missing section: one warning naming task, document and section" \
  'has "warn  tasks/PI-9004-project-missing-section.md: cites PROJECT §6.2 — no such section in tech-analysis/PROJECT_TECH_ANALYSIS.md"'
ok "AC2 extra qualifier form (document named by path), section present: silent" '! has "PI-9005"'
ok "AC6 citation naming a document that does not exist at all: warns about the missing document" \
  'has "warn  tasks/PI-9006-named-file-missing-doc.md: cites tech-analysis/GHOST_TECH_ANALYSIS.md §9.9 but tech-analysis/GHOST_TECH_ANALYSIS.md does not exist"'
ok "combined PROJECT . DELTA line, both segments resolve: silent"               '! has "PI-9007"'
ok "exactly two subsection citation warnings fired (AC3 + AC6), nothing else"    '[[ $(grep -c "^warn.*: cites " <<<"$OUT") -eq 2 ]]'
ok "a subsection citation warning never fails doctor (exit 0)"                  '[[ $rc -eq 0 ]]'

# mutation: restore the hardcoded expected/present check this task removes, on the same fixture —
# proves the AC1/AC4 assertion above is not vacuous (it would go red without the fix).
MUT_PI42=$(mktemp "${TMPDIR:-/tmp}/doctor-mut-pi42.XXXXXX")
# PI-45 (site 6 of 6): re.subn already counts, so the cardinality is exact here — what was missing
# was a reason the shell could name (an AssertionError left $MUT_PI42 empty and made the "hardcoded
# expected set restored" assertion below fail on that basis, reading exactly like a real regression
# in doctor.sh) and a check that what came out is still a whole script.
if MUT_WHY=$(python3 - "$SCRIPT_SRC" "$MUT_PI42" 2>&1 <<'PYEOF'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
old_bug = (
    'for tad in glob.glob("tech-analysis/*_TECH_ANALYSIS.md"):\n'
    '    txt = open(tad, errors="ignore").read()\n'
    '    expected = {"5.2","6.2","7.6","8.1","9.3","11.1"}\n'
    '    present = set(re.findall(r"^### (\\d+\\.\\d+)", txt, re.M))\n'
    '    missing = expected - present\n'
    '    if missing and cfg.get("scope","medium") != "simple": '
    'warn(f"{tad}: subsections referenced by agents missing: {sorted(missing)}")\n'
)
mutated, n = re.subn(r"# PI-42 CHECK BEGIN.*?# PI-42 CHECK END\n", lambda m: old_bug, text, flags=re.S)
if n != 1:
    sys.stderr.write("the PI-42 CHECK marker block occurs %d times in bin/doctor.sh, not once" % n)
    sys.exit(1)
open(dst, "w").write(mutated)
PYEOF
) && mutation_applied "$MUT_PI42" 'expected = {"5.2","6.2","7.6","8.1","9.3","11.1"}'; then
  OUT_MUT=$(cd "$R15" && bash "$MUT_PI42"); rc_mut=$?
  echo "$OUT_MUT" | sed 's/^/      | /'
  ok "mutation: hardcoded expected set restored -> AC1/AC4's silence on unusual, uncited numbering goes red" \
    'grep -q "subsections referenced by agents missing" <<<"$OUT_MUT"'
else
  ok "mutation (PI-42 CHECK marker block restore): cannot self-mutate: $MUT_WHY" 'false'
fi
rm -f "$MUT_PI42"

# --- repo 16: AC5 — top-level order-out-of-order check is untouched by this task ---
R16="$S/repo16"
q git init -q -b main "$R16"
mkdir -p "$R16/tech-analysis"
cat > "$R16/tech-analysis/PROJECT_TECH_ANALYSIS.md" <<'EOF'
## 40. Zeta
Text.

## 9. Alpha
Text.
EOF
task "$R16/tasks/PI-9101-any.md" "Todo"
q git -C "$R16" add -A; q git -C "$R16" commit -qm board
OUT=$(cd "$R16" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "AC5 top-level sections out of order: still an ERROR, unchanged wording" \
  'has "ERROR tech-analysis/PROJECT_TECH_ANALYSIS.md: top-level sections out of order: [40, 9]"'
ok "AC5 out-of-order TAD: doctor exits 1"           '[[ $rc -eq 1 ]]'


# --- repo 17: F1 regression — the real board's own range spelling (tasks/PI-14's **TAD** line,
# extracted from the file itself, not hand-typed) must expand every interior section, not just the
# two endpoints. Reproduces the reviewer's live finding on this repo's own board. ---
REAL_TAD_LINE=$(sed -n 's/^\*\*TAD\*\*: //p' ../tasks/PI-14-handoff-read-only-composer.md)
ok "F1 fixture: PI-14's real **TAD** line was extracted from the file, not hand-typed" \
  '[[ -n "$REAL_TAD_LINE" ]]'
R17="$S/repo17"
q git init -q -b main "$R17"
mkdir -p "$R17/tech-analysis"
cat > "$R17/tech-analysis/HANDOFF_MEMORY_TECH_ANALYSIS.md" <<'EOF'
## 2. Architettura
### 2.1 Stile
Text.
### 2.4 Decisioni
Text.

## 4. Struttura
### 4.1 Disposizione
Text.
### 4.2 Formato
Text.
### 4.3 Ordinamento
Text.
### 4.4 Ritenzione
Text.

## 5. Contratto
### 5.1 Convenzioni
Text.
### 5.2 Comandi
Text.
### 5.3 Costo
Text.

## 8. Script
### 8.1 Struttura
Text.

## 11. Test
### 11.1 Piramide
Text.
### 11.2 Ambiente
Text.
### 11.3 Porte
Text.

## 12. Task
Text.
EOF
tad_task "$R17/tasks/PI-14-real-spelling.md" "$REAL_TAD_LINE"
q git -C "$R17" add -A; q git -C "$R17" commit -qm board
OUT=$(cd "$R17" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "F1 real-spelling citation, every ranged section present: silent" '! has "PI-14-real-spelling"'
ok "F1 real-spelling citation: doctor exits 0"                        '[[ $rc -eq 0 ]]'

# same repo, now delete two interior sections of the en-dash ranges (§4.2, §4.3 inside §4.1–§4.4) —
# exactly the reviewer's own reproduction. The old endpoints-only read of a range never noticed they
# were gone; the fix must expand the range and catch both.
python3 - "$R17/tech-analysis/HANDOFF_MEMORY_TECH_ANALYSIS.md" <<'PYEOF'
import sys
p = sys.argv[1]
text = open(p).read()
for heading in ("### 4.2 Formato\nText.\n", "### 4.3 Ordinamento\nText.\n"):
    assert heading in text, f"fixture setup drifted: {heading!r} not found"
    text = text.replace(heading, "")
open(p, "w").write(text)
PYEOF
OUT=$(cd "$R17" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "F1 fixed: a range's dropped interior sections (§4.2, §4.3) are now caught, not silently skipped" \
  'has "cites tech-analysis/HANDOFF_MEMORY_TECH_ANALYSIS.md §4.2 — no such section" && has "cites tech-analysis/HANDOFF_MEMORY_TECH_ANALYSIS.md §4.3 — no such section"'
ok "F1 fixed: only the two dropped sections warn, the rest of the same range stays silent" \
  '[[ $(grep -c "^warn.*: cites " <<<"$OUT") -eq 2 ]]'

# --- repo 18: F1 class coverage — every separator/shape the grammar promises, invented numbers ---
R18="$S/repo18"
q git init -q -b main "$R18"
mkdir -p "$R18/tech-analysis"
cat > "$R18/tech-analysis/PROJECT_TECH_ANALYSIS.md" <<'EOF'
## 20. Hyphen range
### 20.1 A
Text.
### 20.2 B
Text.
### 20.3 C
Text.

## 21. Em dash range
### 21.1 A
Text.
### 21.2 B
Text.

## 22. To-word range
### 22.1 A
Text.
### 22.2 B
Text.
### 22.3 C
Text.

## 23. Second section mark omitted
### 23.1 A
Text.
### 23.2 B
Text.
### 23.3 C
Text.

## 24. Single element range
### 24.1 A
Text.

## 25. Bare top-level range, interior missing
Text.

## 27. Bare top-level range, other end
Text.

## 30. Mixed list and range
### 30.1 A
Text.
### 30.2 B
Text.
EOF
tad_task "$R18/tasks/PI-9401-hyphen.md"          "PROJECT §20.1-§20.3"
tad_task "$R18/tasks/PI-9402-emdash.md"          "PROJECT §21.1—§21.2"
tad_task "$R18/tasks/PI-9403-to-word.md"         "PROJECT §22.1 to §22.3"
tad_task "$R18/tasks/PI-9404-no-second-mark.md"  "PROJECT §23.1-23.3"
tad_task "$R18/tasks/PI-9405-single-element.md"  "PROJECT §24.1–§24.1"
tad_task "$R18/tasks/PI-9406-bare-top-missing.md" "PROJECT §25–§27"
tad_task "$R18/tasks/PI-9407-different-depth.md" "PROJECT §28–§28.2"
tad_task "$R18/tasks/PI-9408-descending.md"      "PROJECT §29.3–§29.1"
tad_task "$R18/tasks/PI-9409-mixed-list-range.md" "PROJECT §30.1–§30.2, §31.4"
tad_task "$R18/tasks/PI-9410-different-top.md"   "PROJECT §34.9–§35.2"
q git -C "$R18" add -A; q git -C "$R18" commit -qm board
OUT=$(cd "$R18" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "hyphen range, every section present: silent"            '! has "PI-9401"'
ok "em dash range, every section present: silent"           '! has "PI-9402"'
ok "\"to\"-word range, every section present: silent"       '! has "PI-9403"'
ok "range with second § omitted, every section present: silent" '! has "PI-9404"'
ok "single-element range (a-a), section present: silent"    '! has "PI-9405"'
ok "bare top-level range, interior (§26) missing: exactly one warning naming §26" \
  'has "warn  tasks/PI-9406-bare-top-missing.md: cites PROJECT §26 — no such section in tech-analysis/PROJECT_TECH_ANALYSIS.md"'
ok "range whose ends sit at different depth is malformed, warned by its own text, not checked" \
  "has \"warn  tasks/PI-9407-different-depth.md: cites PROJECT range '§28–§28.2' — malformed\""
ok "descending range is malformed, warned by its own text, not checked"                        \
  "has \"warn  tasks/PI-9408-descending.md: cites PROJECT range '§29.3–§29.1' — malformed\""
ok "a list mixed with a range: the range half silent, the plain section (§31.4, missing) still warns" \
  'has "warn  tasks/PI-9409-mixed-list-range.md: cites PROJECT §31.4 — no such section"'
ok "range naming a different top-level section on each end is malformed"                       \
  "has \"warn  tasks/PI-9410-different-top.md: cites PROJECT range '§34.9–§35.2' — malformed\""
ok "malformed-range warnings never also report individual section numbers for that same range" \
  '! has "cites PROJECT §28" && ! has "cites PROJECT §28.2" && ! has "cites PROJECT §29.3" && ! has "cites PROJECT §29.1" && ! has "cites PROJECT §34.9" && ! has "cites PROJECT §35.2"'
ok "class-table repo: exactly 5 warnings (2 malformed ranges + 2 different-top/descending-shape malformed + 1 missing section from the mixed list), rest silent" \
  '[[ $(grep -c "^warn.*: cites " <<<"$OUT") -eq 5 ]]'

# --- repo 19: F2 class coverage — the qualifier word however a person plausibly writes it ---
R19="$S/repo19"
q git init -q -b main "$R19"
mkdir -p "$R19/tech-analysis"
cat > "$R19/tech-analysis/PROJECT_TECH_ANALYSIS.md" <<'EOF'
## 51. Mixed case qualifier
### 51.1 A
Text.

## 53. Extra whitespace qualifier
### 53.1 A
Text.

## 54. Unrecognised qualifier, section happens to exist here
### 54.1 A
Text.
EOF
cat > "$R19/tech-analysis/WIDGETS_TECH_DELTA.md" <<'EOF'
## Delta
### 52.1 A
Text.
### 55.1 A
Text.
EOF
tad_task "$R19/tasks/PI-9501-lowercase-delta.md"    "delta §55.1"          # F2's exact live repro: lowercase, section only in the delta
tad_task "$R19/tasks/PI-9502-mixed-case-project.md" "Project §51.1"
tad_task "$R19/tasks/PI-9503-colon-delta.md"        "DELTA: §52.1"
tad_task "$R19/tasks/PI-9504-extra-whitespace.md"   "PROJECT    §53.1"
tad_task "$R19/tasks/PI-9505-typo-qualifier.md"     "PROJET §54.1"          # section exists in the project TAD — must NOT silently resolve there
q git -C "$R19" add -A; q git -C "$R19" commit -qm board
OUT=$(cd "$R19" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "F2 fixed: lowercase 'delta', section only in the delta: silent (not checked against the project TAD)" \
  '! has "PI-9501" && ! has "cites the project TAD §55.1"'
ok "mixed-case 'Project' qualifier resolves: silent"        '! has "PI-9502"'
ok "'DELTA:' with trailing colon resolves against the delta: silent" '! has "PI-9503"'
ok "extra whitespace between qualifier and § resolves: silent"       '! has "PI-9504"'
ok "unrecognised qualifier word never silently falls back to the project TAD, even when the section exists there" \
  "has \"warn  tasks/PI-9505-typo-qualifier.md: cites §54.1 with an unrecognised qualifier 'PROJET' (expected PROJECT, DELTA, or a document path) — not resolved\""
ok "F2 class-table repo: exactly one warning (the unrecognised qualifier), the four real spellings silent" \
  '[[ $(grep -c "^warn.*: cites " <<<"$OUT") -eq 1 ]]'

# --- mutation sanity, both directions, run across every PI-42 fixture above plus AC5's repo16 ---
# Mirrors the reviewer's own manual check: patching _has_section to accept-anything or reject-
# everything must each still turn some of the assertions above red, and AC5's out-of-order `err`
# (which never calls _has_section) must keep firing, unaffected, under both.
mutate_has_section(){ # mutate_has_section <return-value> <out-path> — writes a patched copy of
  # $SCRIPT_SRC (AC3); returns 1 with MUT_WHY set when the definition is not there verbatim exactly
  # once, or when what came out is not a whole script (AC2, PI-45 site 1 of 6) — never an uncaught
  # AssertionError leaving <out-path> an empty file for five unrelated fixtures to be judged against
  # in both directions (AC1: that is how nine artifact FAILs were produced).
  MUT_WHY=$(python3 - "$SCRIPT_SRC" "$2" "$1" 2>&1 >/dev/null <<'PYEOF'
import re, sys
src, dst, retval = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(src).read()
old = 'def _has_section(text, sec):\n    if "." in sec: return re.search(rf"^### {re.escape(sec)}\\b", text, re.M) is not None\n    return re.search(rf"^## {re.escape(sec)}\\.", text, re.M) is not None\n'
new = f'def _has_section(text, sec):\n    return {retval}\n'
mutated, n = re.subn(re.escape(old), lambda m: new, text)
if n != 1:
    sys.stderr.write("_has_section's definition occurs %d times verbatim in bin/doctor.sh, not once" % n)
    sys.exit(1)
open(dst, "w").write(mutated)
PYEOF
) || return 1
}
MUT_TRUE=$(mktemp "${TMPDIR:-/tmp}/doctor-mut-true.XXXXXX")
MUT_FALSE=$(mktemp "${TMPDIR:-/tmp}/doctor-mut-false.XXXXXX")
# PI-45 AC1/AC2: MUT_TRUE and MUT_FALSE feed every assertion in this whole section, across five
# unrelated fixtures (repo15-19) in both directions — if either mutation fails to apply, running an
# empty/unmutated script against those fixtures produced 9 artifact FAILs (malformed-range,
# unrecognised-qualifier, AC5) that never call _has_section at all, none of which is a real
# regression. Gate the entire section on both mutations having actually applied, and report exactly
# one named failure instead, so nothing downstream is misjudged (AC5: a genuine regression in
# _has_section is still caught normally by the direct, unmutated-script checks elsewhere in this
# file — this section only proves those checks are not vacuous, and skipping it changes nothing
# about them).
if mutate_has_section True  "$MUT_TRUE"  && mutant_whole "$MUT_TRUE" &&
   mutate_has_section False "$MUT_FALSE" && mutant_whole "$MUT_FALSE"; then
  # accept-anything (_has_section always True): every "missing section" warning must disappear —
  # AC3 (repo15), the F1 dropped-interior-sections warning (repo17, post-deletion), the bare-top-level
  # and mixed-list "missing" warnings (repo18) all go red. Malformed-range and unrecognised-qualifier
  # warnings never call _has_section, so they must be unaffected; AC5 must still fire.
  OUT_15T=$(cd "$R15" && bash "$MUT_TRUE"); OUT_17T=$(cd "$R17" && bash "$MUT_TRUE")
  OUT_18T=$(cd "$R18" && bash "$MUT_TRUE"); OUT_19T=$(cd "$R19" && bash "$MUT_TRUE")
  OUT_16T=$(cd "$R16" && bash "$MUT_TRUE"); rc_16T=$?
  ok "mutation accept-anything: AC3's missing-section warning (repo15) goes red"        '! grep -q "cites PROJECT §6.2 — no such section" <<<"$OUT_15T"'
  ok "mutation accept-anything: F1's dropped-interior-section warnings (repo17) go red" '! grep -q "cites tech-analysis/HANDOFF_MEMORY_TECH_ANALYSIS.md §4.2 — no such section" <<<"$OUT_17T"'
  ok "mutation accept-anything: bare-top-level missing-interior warning (repo18, §26) goes red" '! grep -q "cites PROJECT §26 — no such section" <<<"$OUT_18T"'
  ok "mutation accept-anything: mixed-list missing-section warning (repo18, §31.4) goes red" '! grep -q "cites PROJECT §31.4 — no such section" <<<"$OUT_18T"'
  ok "mutation accept-anything: malformed-range warnings (repo18) unaffected, still fire"    'grep -q "range .§28–§28.2. — malformed" <<<"$OUT_18T" && grep -q "range .§29.3–§29.1. — malformed" <<<"$OUT_18T"'
  ok "mutation accept-anything: unrecognised-qualifier warning (repo19) unaffected, still fires" 'grep -q "unrecognised qualifier .PROJET." <<<"$OUT_19T"'
  ok "mutation accept-anything: AC5's top-level out-of-order error (repo16) is untouched, still fires" \
    'grep -q "ERROR tech-analysis/PROJECT_TECH_ANALYSIS.md: top-level sections out of order: \[40, 9\]" <<<"$OUT_16T" && [[ $rc_16T -eq 1 ]]'

  # reject-everything (_has_section always False): every real citation to a section that genuinely
  # exists must now spuriously warn — the silent AC1/AC2 cases (repo15), the real-spelling silent case
  # (repo17, pre-deletion), every silent class-table case (repo18), and every silent qualifier spelling
  # (repo19) all go red. Malformed-range and unrecognised-qualifier warnings are unaffected; AC5 stays.
  OUT_15F=$(cd "$R15" && bash "$MUT_FALSE"); OUT_17_PRE=$(cd "$R17" && git -C "$R17" show HEAD:tech-analysis/HANDOFF_MEMORY_TECH_ANALYSIS.md > /dev/null; true)
  # repo17's tree was mutated (interior sections deleted) after its first run; rebuild a pristine copy for the reject-everything check of the *positive* (should-be-silent) case.
  R17B="$S/repo17b"; q git init -q -b main "$R17B"; mkdir -p "$R17B/tech-analysis"
  git -C "$R17" show HEAD:tech-analysis/HANDOFF_MEMORY_TECH_ANALYSIS.md > "$R17B/tech-analysis/HANDOFF_MEMORY_TECH_ANALYSIS.md"
  git -C "$R17" show HEAD:tasks/PI-14-real-spelling.md > /dev/null 2>&1 && mkdir -p "$R17B/tasks" && git -C "$R17" show HEAD:tasks/PI-14-real-spelling.md > "$R17B/tasks/PI-14-real-spelling.md"
  q git -C "$R17B" add -A; q git -C "$R17B" commit -qm board
  OUT_17BF=$(cd "$R17B" && bash "$MUT_FALSE")
  OUT_18F=$(cd "$R18" && bash "$MUT_FALSE"); OUT_19F=$(cd "$R19" && bash "$MUT_FALSE")
  OUT_16F=$(cd "$R16" && bash "$MUT_FALSE"); rc_16F=$?
  ok "mutation reject-everything: AC1/AC2 silent citations (repo15) go red"                   'grep -q "cites .*§5\.2\|cites DELTA §7\.6" <<<"$OUT_15F"'
  ok "mutation reject-everything: F1 real-spelling silent case (repo17, all sections present) goes red" 'grep -q "cites tech-analysis/HANDOFF_MEMORY_TECH_ANALYSIS.md §2\.1" <<<"$OUT_17BF"'
  ok "mutation reject-everything: class-table silent ranges (repo18: hyphen/em dash/to/no-second-mark/single-element) all go red" \
    'grep -q "cites PROJECT §20\.1" <<<"$OUT_18F" && grep -q "cites PROJECT §21\.1" <<<"$OUT_18F" && grep -q "cites PROJECT §22\.1" <<<"$OUT_18F" && grep -q "cites PROJECT §23\.1" <<<"$OUT_18F" && grep -q "cites PROJECT §24\.1" <<<"$OUT_18F"'
  ok "mutation reject-everything: F2's four real qualifier spellings (repo19) all go red"     \
    'grep -q "cites DELTA §55\.1" <<<"$OUT_19F" && grep -q "cites PROJECT §51\.1" <<<"$OUT_19F" && grep -q "cites DELTA §52\.1" <<<"$OUT_19F" && grep -q "cites PROJECT §53\.1" <<<"$OUT_19F"'
  ok "mutation reject-everything: malformed-range and unrecognised-qualifier warnings unaffected, unchanged text" \
    'grep -q "range .§28–§28.2. — malformed" <<<"$OUT_18F" && grep -q "unrecognised qualifier" <<<"$(cd "$R19" && bash "$MUT_FALSE")"'
  ok "mutation reject-everything: AC5's top-level out-of-order error (repo16) is untouched, still fires" \
    'grep -q "ERROR tech-analysis/PROJECT_TECH_ANALYSIS.md: top-level sections out of order: \[40, 9\]" <<<"$OUT_16F" && [[ $rc_16F -eq 1 ]]'
else
  ok "mutation sanity (_has_section accept-anything/reject-everything): cannot self-mutate: $MUT_WHY" 'false'
fi
rm -f "$MUT_TRUE" "$MUT_FALSE"

# --- repo 20: board index drift (PI-62) — tasks/INDEX.md is generated by tasks-index.sh, and doctor
# must error when the committed file disagrees with what that same generator produces now. TIDX is
# the real script (not a re-implementation of its table), invoked in the new --stdout mode the check
# itself uses, so a change to the table format cannot silently desync this suite from doctor.sh.
TIDX="$(dirname "$SCRIPT")/tasks-index.sh"
mtime_of(){ stat -f%m "$1" 2>/dev/null || stat -c%Y "$1" 2>/dev/null; }

# AC1: an in-sync board -> no index error, no index warning, and repo2's own pre-existing
# assertions (line ~157 above) still hold once its board is indexed — indexing must add nothing new.
R20="$S/repo20"
cp -r "$R2" "$R20"
q bash "$TIDX" "$R20/tasks"
q git -C "$R20" add -A; q git -C "$R20" commit -qm "board index"
OUT=$(cd "$R20" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "AC1 index in sync: repo2's own assertions (0 errors, 1 warning, 2 task files) still hold once indexed" \
  '[[ $rc -eq 0 ]] && has "doctor: 0 error(s), 1 warning(s), 2 task file(s)"'
ok "AC1 index in sync: no index-related error or warning is emitted" '! has "INDEX.md"'

# AC2: a task file's **Status** changed without re-running tasks-index.sh -> error naming that ID,
# counted in N error(s), exit 1, with the exact one-liner fix command.
R20B="$S/repo20b"
q git init -q -b main "$R20B"
task "$R20B/tasks/PI-1002-c.md" "Todo"
task "$R20B/tasks/PI-1003-d.md" "Todo"
q bash "$TIDX" "$R20B/tasks"
q git -C "$R20B" add -A; q git -C "$R20B" commit -qm board
sed -i.bak -E 's/^\*\*Status\*\*:.*/**Status**: Done/' "$R20B/tasks/PI-1002-c.md"; rm -f "$R20B/tasks/PI-1002-c.md.bak"
OUT=$(cd "$R20B" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "AC2 Status changed, index untouched: ERROR names the stale ID"     'has "tasks/INDEX.md is stale" && has "PI-1002"'
ok "AC2 Status changed, index untouched: the unrelated task is not named" '! has "PI-1003"'
ok "AC2 Status changed, index untouched: counted in N error(s), exit 1" '[[ $rc -eq 1 ]] && has "1 error(s)"'
ok "AC2 Status changed, index untouched: prints the exact self-contained fix command" \
  "has 'regenerate it: bash $TIDX'"

# AC2 variant: **PR** changed instead of Status — same drift, same detection path.
R20B2="$S/repo20b2"
q git init -q -b main "$R20B2"
task_pr "$R20B2/tasks/PI-1004-e.md" "Todo" "—"
q bash "$TIDX" "$R20B2/tasks"
q git -C "$R20B2" add -A; q git -C "$R20B2" commit -qm board
sed -i.bak -E 's#^\*\*PR\*\*:.*#**PR**: https://github.com/x/y/pull/1#' "$R20B2/tasks/PI-1004-e.md"; rm -f "$R20B2/tasks/PI-1004-e.md.bak"
OUT=$(cd "$R20B2" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "AC2 PR changed, index untouched: ERROR names the stale ID" 'has "tasks/INDEX.md is stale" && has "PI-1004"'

# AC3a: a task file ADDED after the index was generated, index untouched -> error naming the new ID.
R20C="$S/repo20c"
q git init -q -b main "$R20C"
task "$R20C/tasks/PI-1010-f.md" "Todo"
q bash "$TIDX" "$R20C/tasks"
q git -C "$R20C" add -A; q git -C "$R20C" commit -qm board
task "$R20C/tasks/PI-1011-g.md" "Todo"
OUT=$(cd "$R20C" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "AC3 task file added, index untouched: ERROR names the new ID"     'has "tasks/INDEX.md is stale" && has "PI-1011"'
ok "AC3 task file added, index untouched: the unrelated task is not named" '! has "PI-1010"'

# AC3b: a task file DELETED after the index was generated, index untouched -> error naming the ID.
R20D="$S/repo20d"
q git init -q -b main "$R20D"
task "$R20D/tasks/PI-1020-h.md" "Todo"
task "$R20D/tasks/PI-1021-i.md" "Todo"
q bash "$TIDX" "$R20D/tasks"
q git -C "$R20D" add -A; q git -C "$R20D" commit -qm board
rm -f "$R20D/tasks/PI-1021-i.md"
OUT=$(cd "$R20D" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "AC3 task file deleted, index untouched: ERROR names the removed ID"   'has "tasks/INDEX.md is stale" && has "PI-1021"'
ok "AC3 task file deleted, index untouched: the surviving task is not named" '! has "PI-1020"'

# AC4: tasks-index.sh's new --stdout mode never touches tasks/INDEX.md, and produces the same bytes
# on stdout that the normal (writing) mode would put in the file — proven by content AND mtime.
R20E="$S/repo20e"
q git init -q -b main "$R20E"
task "$R20E/tasks/PI-1030-j.md" "Todo"
task "$R20E/tasks/PI-1031-k.md" "Done"
STDOUT_GEN=$(bash "$TIDX" "$R20E/tasks" --stdout)
ok "AC4 --stdout mode: tasks/INDEX.md is never created when it did not exist" '[[ ! -e "$R20E/tasks/INDEX.md" ]]'
q bash "$TIDX" "$R20E/tasks"   # now write it for real, the normal way
WRITTEN_CONTENT=$(cat "$R20E/tasks/INDEX.md")
ok "AC4 --stdout mode: identical bytes to what the writing mode puts in the file" '[[ "$STDOUT_GEN" == "$WRITTEN_CONTENT" ]]'
BEFORE_CONTENT=$(cat "$R20E/tasks/INDEX.md"); BEFORE_MTIME=$(mtime_of "$R20E/tasks/INDEX.md")
bash "$TIDX" "$R20E/tasks" --stdout >/dev/null
AFTER_CONTENT=$(cat "$R20E/tasks/INDEX.md"); AFTER_MTIME=$(mtime_of "$R20E/tasks/INDEX.md")
ok "AC4 --stdout mode: an EXISTING tasks/INDEX.md is left byte-identical" '[[ "$BEFORE_CONTENT" == "$AFTER_CONTENT" ]]'
ok "AC4 --stdout mode: an EXISTING tasks/INDEX.md keeps its mtime (never opened for writing)" '[[ "$BEFORE_MTIME" == "$AFTER_MTIME" ]]'
ok "AC4 no new flag: writing mode is unchanged, still prints its own 'wrote' line" \
  '(q git init -q -b main "$S/repo20e2"; task "$S/repo20e2/tasks/PI-1032-l.md" Todo; bash "$TIDX" "$S/repo20e2/tasks") | grep -q "tasks-index: wrote .*INDEX.md (1 tasks)"'

# AC5: no tasks/ directory at all -> the drift check is silently skipped, same as the checks around it.
R20F="$S/repo20f"
q git init -q -b main "$R20F"
q git -C "$R20F" commit -qm empty --allow-empty
OUT=$(cd "$R20F" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "AC5 no tasks/ directory: no index error or warning (regression: doctor stays usable with no board)" '! has "INDEX.md"'

# Regression: a board that has task files but has NEVER had tasks-index.sh run on it (no committed
# tasks/INDEX.md at all) is a different gap from staleness — this check has nothing to compare
# against, so it stays silent rather than erroring on every one of this suite's own earlier fixtures
# (repo1-repo19), none of which carries an INDEX.md. Already proven true by every "0 error(s)"
# assertion above still passing with this check installed; this case asserts it directly too.
R20G="$S/repo20g"
q git init -q -b main "$R20G"
task "$R20G/tasks/PI-1040-m.md" "Todo"
q git -C "$R20G" add -A; q git -C "$R20G" commit -qm board
OUT=$(cd "$R20G" && bash "$SCRIPT"); rc=$?
ok "regression: tasks/INDEX.md never generated at all -> silent, not an error" '! has "INDEX.md"'

# --- PI-45 AC4: the rule, not the call site -----------------------------------------------------
# One shared gate, six blocks, no second copy that can drift. Counted from this file's own text
# rather than from a list written by hand, so the day a seventh self-mutation site is added without
# a gate the count stops matching and this goes red here — instead of waiting for the next reviewer
# to mutate bin/doctor.sh and be told the wrong test broke. (The two sibling sites in
# bin/cleanup-merged.test.sh are the same defect class and are tracked separately; this file's own
# rule is what is enforced here.) The patterns are split mid-string so that these very lines are not
# counted as sites or as gates.
MUT_SITES=$(grep -cF '=$(mktemp "${TMPDIR:-/tmp}/doctor-''mut' "$SELF")
MUT_GATES=$(grep -oF -e 'mutation_applied "$M''UT' -e 'mutant_whole "$M''UT' "$SELF" | grep -c .)
ok "AC4: every self-mutation site in this file passes through the one shared gate — $MUT_SITES sites declared by their own mktemp, $MUT_GATES gate calls, no site ungated and no copy of the rule" \
  '[[ "$MUT_SITES" -ge 6 ]] && [[ "$MUT_GATES" -eq "$MUT_SITES" ]]'

# --- PI-45 round 2: the gate itself, over the whole class of anchor losses ----------------------
# Not a sample of the one case the review executed. The class is every way a text address can stop
# meaning the span the block assumes: each anchor x {removed, edited in place, doubled}, in both
# matching modes, plus the intact control. It is exercised on a SYNTHETIC doctor.sh-shaped script
# with anchors no block in this file uses, because the gate has to hold for the anchors this file
# does not contain yet. Every row asserts both what the gate says and what the raw sed would have
# produced without it, so "the old evidence (a marker in the output) is satisfied by a truncation"
# is demonstrated here, not argued, and so is the one case only the cardinality count catches.
G="$S/gate"; mkdir -p "$G"
gate_open='def gate_target(x):'
gate_close='    return "tail", y'
gate_src(){ # gate_src <file> — pristine synthetic source: bash wrapper, python heredoc, a
            # two-anchor region to address, and lines after it whose survival proves no truncation.
  cat > "$1" <<'GATEEOF'
#!/usr/bin/env bash
python3 - <<'PY'
def alpha(x):
    return "head"
def gate_target(x):
    y = x + 1
    return "tail", y
def omega(x):
    return "after"
print(alpha(0), gate_target(1), omega(2))
PY
GATEEOF
}
gate_mutate(){ # gate_mutate <src> <out> — the very shape site 4 uses (range address, c\ replace),
               # run WITHOUT the gate on purpose so each row can look at the damage it would do.
  { printf '/^%s$/,/^%s$/c\\\n' "$(sed_lit "$gate_open")" "$(sed_lit "$gate_close")"
    printf '%s\n' 'def gate_target(x):\' '    return "GATE MUTATED", 0'
  } > "$2.sed"
  sed -f "$2.sed" "$1" > "$2"; rm -f "$2.sed"
}
gate_case(){ # gate_case <name> <python-edit-expression> — a variant of the pristine source with one
             # anchor loss applied, plus the raw (ungated) mutant built from it. Prints nothing.
  gate_src "$G/$1.sh"
  python3 - "$G/$1.sh" "$2" <<'GPYEOF'
import sys
path, edit = sys.argv[1], sys.argv[2]
text = open(path).read()
OPEN = "def gate_target(x):\n"
CLOSE = '    return "tail", y\n'
if edit == "open-removed":      out = text.replace(OPEN, "", 1)
elif edit == "open-edited":     out = text.replace(OPEN, OPEN.rstrip("\n") + "  # touched\n", 1)
elif edit == "open-doubled":    out = text.replace("def omega(x):\n", "def omega(x):\n" + OPEN, 1)
elif edit == "close-removed":   out = text.replace(CLOSE, "", 1)
elif edit == "close-edited":    out = text.replace(CLOSE, CLOSE.rstrip("\n") + "  # touched\n", 1)
elif edit == "close-doubled":   out = text.replace("    y = x + 1\n", "    y = x + 1\n" + CLOSE, 1)
else: sys.exit("unknown edit")
assert out != text, "gate fixture stale: %s changed nothing" % edit
open(path, "w").write(out)
GPYEOF
  gate_mutate "$G/$1.sh" "$G/$1.mut.sh"
}

gate_src "$G/pristine.sh"; gate_mutate "$G/pristine.sh" "$G/pristine.mut.sh"
ok "gate control: both anchors present exactly once — src_anchors accepts (the sibling that proves the rejections below are not vacuous)" \
  'src_anchors "$G/pristine.sh" line 1 "$gate_open" "$gate_close"'
ok "gate control: on that source the range mutation lands, stays a whole script, and keeps every line after the range" \
  'mutation_applied "$G/pristine.mut.sh" "GATE MUTATED" && grep -qF "def omega(x):" "$G/pristine.mut.sh"'

# the class, one row per anchor x loss. src_anchors must reject every one of them.
for gcase in open-removed open-edited open-doubled close-removed close-edited close-doubled; do
  gate_case "$gcase" "$gcase"
  ok "gate class ($gcase): src_anchors refuses to let the mutation run, and says which anchor and how many times" \
    '! src_anchors "$G/$gcase.sh" line 1 "$gate_open" "$gate_close" && grep -q "^anchor found [0-9]* times, not 1" <<<"$MUT_WHY"'
done

# ...and what the ungated sed would have done, per loss — the evidence the old check trusted.
ok "gate class (close-edited): the ungated sed runs the range to EOF — the marker IS in the output (the old evidence says 'applied') yet everything after the range is gone" \
  'grep -qF "GATE MUTATED" "$G/close-edited.mut.sh" && ! grep -qF "def omega(x):" "$G/close-edited.mut.sh"'
ok "gate class (close-edited): mutant_whole catches that truncation on its own, without knowing any anchor" \
  '! mutant_whole "$G/close-edited.mut.sh" && grep -q "fragment" <<<"$MUT_WHY"'
ok "gate class (close-removed): same truncation, same independent catch" \
  'grep -qF "GATE MUTATED" "$G/close-removed.mut.sh" && ! mutant_whole "$G/close-removed.mut.sh"'
ok "gate class (open-doubled): the second range opens after the first closed and runs to EOF — caught by mutant_whole too" \
  '! mutant_whole "$G/open-doubled.mut.sh"'
ok "gate class (open-removed): the range never opens, the marker never lands — mutation_applied refuses" \
  '! mutation_applied "$G/open-removed.mut.sh" "GATE MUTATED" && grep -q "marker never landed" <<<"$MUT_WHY"'
ok "gate class (open-edited): a comment appended to the opening anchor is the same loss — /^…$/ no longer matches it" \
  '! mutation_applied "$G/open-edited.mut.sh" "GATE MUTATED"'
ok "gate class (close-doubled): the ONLY loss mutant_whole cannot see — the range closes early, the copy is whole and carries the marker, and the span it replaced is not the one the block meant (the real closing line is left behind); the anchor COUNT is what rejects it" \
  'mutation_applied "$G/close-doubled.mut.sh" "GATE MUTATED" && grep -qxF "    return \"tail\", y" "$G/close-doubled.mut.sh" && ! src_anchors "$G/close-doubled.sh" line 1 "$gate_open" "$gate_close"'

# the two matching modes are not interchangeable: `line` mirrors /^…$/, `substr` mirrors /…/.
gate_src "$G/modes.sh"
printf '%s\n' '# MARK BEGIN' 'noise' '# MARK END' >> "$G/modes.sh"
ok "gate modes: substr accepts a marker pair present once each, the way /…/,/…/d addresses them" \
  'src_anchors "$G/modes.sh" substr 1 "# MARK BEGIN" "# MARK END"'
ok "gate modes: substr rejects a missing closing marker (which would delete to end of file)" \
  '! src_anchors "$G/modes.sh" substr 1 "# MARK BEGIN" "# MARK ABSENT"'
sed -i.bak 's/^# MARK BEGIN$/# MARK BEGIN  (annotated)/' "$G/modes.sh"; rm -f "$G/modes.sh.bak"
ok "gate modes: an annotated marker still matches /…/ and substr still accepts it — the gate follows sed, it does not second-guess it" \
  'src_anchors "$G/modes.sh" substr 1 "# MARK BEGIN" "# MARK END"'
ok "gate modes: the same annotated line is correctly REJECTED in line mode, because /^…$/ would no longer match it — this is the difference a plain grep -F gate would have missed" \
  '! src_anchors "$G/modes.sh" line 1 "# MARK BEGIN"'

# --- PI-45 regression, rebuilt by PI-63 on a mirror instead of the real file: the suite survives
# bin/doctor.sh having been modified from OUTSIDE this run, before it started (AC1, AC2, AC5) —
# reproduces the reviewer's own non-vacuity proof that found the defect: 16 FAILs on a mutated
# bin/doctor.sh, 9 of them artifacts (malformed-range, unrecognised-qualifier, AC5) that never call
# _has_section at all. Each row below recurses the WHOLE suite once against a bin/doctor.sh carrying
# ONE external edit that breaks ONE self-mutation site's source text while changing nothing about
# what doctor.sh does — so every OTHER check in the recursed run is a clean control: if any of them
# goes red too, the isolation does not hold. The table is the class of losses end to end, not the one
# case the first review executed: the verbatim literal of a python site, and a range address's
# closing anchor (the runaway-to-EOF that made the suite name "degrades to a warn", a check that
# never ran) and its doubled anchors (a whole, marker-bearing copy over the wrong span, which only
# the anchor count can see).
# PI-63: the mutated content the recursed run reads never touches $SCRIPT, the checked-out
# bin/doctor.sh — not even transiently, not even restored by a trap. Each case builds the mutated
# text into a throwaway file under $S from $SCRIPT_SRC (the same once-captured copy every other
# self-mutating block in this file already uses), then runs the recursed suite inside a mirror
# directory (mirror_run) that is bin/doctor.sh's throwaway copy plus a symlink to every OTHER file
# the recursed run's own `pwd -P`/`cd ..`/`dirname "$SCRIPT"` path resolution needs (the rest of
# bin/, .claude/hooks, .claude/skills) — so the recursed run reads real, current content for
# everything except the one file under test. DOCTOR_TEST_NO_RECURSE stops each child from doing this
# again.
if [[ -z "${DOCTOR_TEST_NO_RECURSE:-}" ]]; then
  REPO_ROOT="$(cd .. && pwd -P)"
  external_mutation(){ # external_mutation <case> <outfile> — write a MUTATED COPY of $SCRIPT_SRC's
    # text to <outfile>, the way an outside hand would edit it: behaviour-preserving, one site's
    # anchors only, loudly stale rather than silently wrong. $SCRIPT (the real, checked-out
    # bin/doctor.sh) is read nowhere here and never opened for writing.
    python3 - "$SCRIPT_SRC" "$1" "$2" <<'EXTEOF'
import sys
path, case, outpath = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
HAS = 'def _has_section(text, sec):\n    if "." in sec: return re.search(rf"^### {re.escape(sec)}\\b", text, re.M) is not None\n    return re.search(rf"^## {re.escape(sec)}\\.", text, re.M) is not None\n'
OPEN = "def _classify_base(base, env):\n"
CLOSE = '    return "unreachable", (stderr.splitlines()[-1] if stderr else "no network")\n'
def need(lit):
    if text.count(lit) != 1:
        sys.stderr.write("PI-45 recursion fixture stale: %r occurs %d times in bin/doctor.sh\n"
                         % (lit[:48], text.count(lit)))
        sys.exit(1)
if case == "has_section_literal":
    need(HAS)
    out = text.replace(HAS, HAS.replace(
        "def _has_section(text, sec):\n",
        "def _has_section(text, sec):  # PI-45 test: externally mutated on purpose, breaks the verbatim literal\n", 1), 1)
elif case == "classify_close_anchor":
    need(CLOSE)
    out = text.replace(CLOSE, CLOSE.rstrip("\n") + "  # PI-45 test: externally edited, closing anchor of a range address\n", 1)
elif case == "classify_anchors_doubled":
    need(OPEN); need(CLOSE)
    i = text.index(OPEN); j = text.index(CLOSE, i) + len(CLOSE)
    out = text[:j] + text[i:j] + text[j:]   # an identical second definition: same behaviour, both anchors now doubled
else:
    sys.stderr.write("PI-45 recursion: unknown case %s\n" % case); sys.exit(1)
open(outpath, "w").write(out)
EXTEOF
  }
  mirror_run(){ # mirror_run <doctor.sh-path> — recurse the whole suite with bin/doctor.sh replaced
    # by <doctor.sh-path>. Every OTHER entry of the checkout — every top-level file and directory,
    # and every other file under bin/ — is a symlink to the real, current one (never copied, never
    # edited), so a relative read anywhere in the recursed run (../tasks/…, .claude/hooks/…,
    # .claude/skills/…) resolves exactly as it would outside this mirror: only bin/doctor.sh
    # differs, and only inside this throwaway directory, removed before this function returns.
    # .git is left out on purpose: nothing in the recursed run treats the mirror itself as a repo,
    # and a worktree's .git is a text file naming a relative gitdir path that is easiest to just
    # not carry here.
    local mut="$1" m f b
    m=$(mktemp -d "$S/mirror.XXXXXX")
    mkdir -p "$m/bin"
    for f in "$REPO_ROOT"/* "$REPO_ROOT"/.[!.]*; do
      [[ -e "$f" ]] || continue
      b="$(basename "$f")"
      [[ "$b" == "bin" || "$b" == ".git" ]] && continue
      ln -s "$f" "$m/$b"
    done
    for f in "$REPO_ROOT"/bin/*; do
      b="$(basename "$f")"
      [[ "$b" == "doctor.sh" ]] && continue
      ln -s "$f" "$m/bin/$b"
    done
    cp "$mut" "$m/bin/doctor.sh"; chmod +x "$m/bin/doctor.sh"
    ( DOCTOR_TEST_NO_RECURSE=1 bash "$m/bin/doctor.test.sh" 2>&1 )
    rm -rf "$m"
  }
  while IFS='|' read -r rcase rexpect rwhat; do
    [[ -z "$rcase" ]] && continue
    MUT_DOCTOR="$S/doctor.$rcase.sh"
    if ! external_mutation "$rcase" "$MUT_DOCTOR"; then
      ok "PI-45 recursion ($rcase): bin/doctor.sh still matches this fixture's source text" 'false'
      continue
    fi
    OUT_SELFMUT=$(mirror_run "$MUT_DOCTOR")
    rm -f "$MUT_DOCTOR"
    FAIL_LINES=$(grep '^FAIL' <<<"$OUT_SELFMUT")
    ok "AC2 ($rcase — $rwhat): the harness reports its own named, isolated self-mutation error" \
      'grep -qF "$rexpect" <<<"$FAIL_LINES"'
    ok "AC1 ($rcase): that is the ONLY FAIL line in the whole recursed run — no unrelated check is blamed for it" \
      '[[ "$(grep -c . <<<"$FAIL_LINES")" -eq 1 ]]'
    ok "AC1 ($rcase): repo18's own direct malformed-range check, wholly unrelated to the broken site, still passes" \
      'grep -qF "ok    range whose ends sit at different depth is malformed, warned by its own text, not checked" <<<"$OUT_SELFMUT"'
    ok "AC1 ($rcase): repo19's own direct unrecognised-qualifier check, wholly unrelated to the broken site, still passes" \
      'grep -qF "ok    unrecognised qualifier word never silently falls back to the project TAD, even when the section exists there" <<<"$OUT_SELFMUT"'
    ok "AC1/AC5 ($rcase): repo16's own direct top-level-order check still passes — isolation is not blanket silence" \
      'grep -qF "ok    AC5 top-level sections out of order: still an ERROR, unchanged wording" <<<"$OUT_SELFMUT"'
    ok "AC1/AC5 ($rcase): the un-mutated deleted-base check, which runs the externally edited script itself, still passes — the edit really is behaviour-preserving, so any FAIL above would have been the harness's own" \
      'grep -qF "ok    round 3, under a git that never speaks English on this message: deleted base still an ERROR" <<<"$OUT_SELFMUT"'
  done <<'RCASES'
has_section_literal|FAIL  mutation sanity (_has_section accept-anything/reject-everything): cannot self-mutate: |site 1's verbatim definition broken by an appended comment
classify_close_anchor|FAIL  mutation (round-2 text-based classify): cannot self-mutate: |site 4's range CLOSING anchor edited, the runaway-to-EOF the review caught
classify_anchors_doubled|FAIL  mutation (round-2 text-based classify): cannot self-mutate: |site 4's range anchors doubled by an identical second definition
RCASES

  # --- AC2, the other direction: the SAME recursion machinery, unmutated — proves the loop above
  # is not vacuously red regardless of what bin/doctor.sh contains. A pristine copy of $SCRIPT_SRC
  # recursed through mirror_run must report none of the three "cannot self-mutate" FAILs above.
  cp "$SCRIPT_SRC" "$S/doctor.pristine.sh"
  OUT_PRISTINE=$(mirror_run "$S/doctor.pristine.sh")
  rm -f "$S/doctor.pristine.sh"
  ok "AC2 control (both directions): recursing on an UNMUTATED copy of bin/doctor.sh reports none of the three self-mutation FAILs — the loop above is not vacuously red" \
    '! grep -q "^FAIL.*cannot self-mutate:" <<<"$OUT_PRISTINE"'

  # --- AC4: SIGINT sent mid-recursion (after the mutated copy exists, while the nested suite is
  # running against it) must leave the real, checked-out bin/doctor.sh exactly as it was — no trap
  # is needed for that anymore, because nothing between here and the nested run ever opens $SCRIPT
  # for writing. Proved by actually interrupting a live case, not by reading the code above.
  BEFORE_SIGINT="$(git -C "$REPO_ROOT" status --porcelain -- bin/doctor.sh 2>/dev/null)"
  ( external_mutation "has_section_literal" "$S/ac4.mut.sh" && mirror_run "$S/ac4.mut.sh" >/dev/null 2>&1 ) &
  SIGINT_PID=$!
  sleep 1
  kill -INT "$SIGINT_PID" 2>/dev/null
  pkill -INT -P "$SIGINT_PID" 2>/dev/null
  wait "$SIGINT_PID" 2>/dev/null
  sleep 0.2
  pkill -KILL -P "$SIGINT_PID" 2>/dev/null
  AFTER_SIGINT="$(git -C "$REPO_ROOT" status --porcelain -- bin/doctor.sh 2>/dev/null)"
  ok "AC4: SIGINT mid-recursion (sent 1s in, to the case's subshell and its direct child) leaves the real bin/doctor.sh exactly as before — git status empty on both sides of the interruption" \
    '[[ -z "$BEFORE_SIGINT" && "$AFTER_SIGINT" == "$BEFORE_SIGINT" ]]'
  rm -f "$S/ac4.mut.sh"
fi

# PI-63 (AC1): the background reader above never saw bin/doctor.sh differ from HEAD's content at
# any sampled instant of this run — the whole point of this task, checked once at the very end so a
# hit recorded at any point during the run (including the recursion block above) is caught here.
kill "$SCRIPT_WATCH_PID" 2>/dev/null; wait "$SCRIPT_WATCH_PID" 2>/dev/null
ok "AC1: bin/doctor.sh on disk never differed from HEAD's own content at any instant of this run (continuous background sampling, byte-for-byte against the copy captured at start)" \
  '[[ ! -e "$SCRIPT_WATCH_HIT" ]] && cmp -s "$SCRIPT" "$SCRIPT_SRC"'

exit $fail
