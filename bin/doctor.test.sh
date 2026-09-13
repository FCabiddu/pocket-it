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

# AC2: rewritten base — an ERROR that says how to inspect it, how to recover without discarding
# anything pushed since, and how to accept it if the rewrite was intentional. Round 3: every command
# it prints must actually RUN, as printed, from inside an arbitrary project (no bin/ dir, nothing
# pocket-it-specific in the clone) and bring doctor back to green — round 2 only checked the text.
# Each remediation path (recover / accept / each mutation) gets its OWN fresh origin replaying the
# same rewrite, and its own clone seeded with the same "last seen" baseline — pushing to origin in
# one path (the real recovery genuinely mutates the remote) must never disturb another path's test.
extract_recover_cmd(){ grep '^ERROR base branch' | sed -E 's/.*discarding anything pushed since: (.*) — if it was intentional.*/\1/'; }
extract_accept_cmd(){ grep '^ERROR base branch' | sed -E 's/.*then accept it with: (.*)$/\1/'; }
seed_prev(){ # seed_prev <clone-dir> <base> <sha> — pre-record doctor's "last seen" baseline for a clone
  mkdir -p "$(common "$1")/pocket-it"
  printf '%s %s\n' "$2" "$3" > "$(common "$1")/pocket-it/base-seen"
}
mk_rewritten_bare(){ # mk_rewritten_bare <dest-bare-path> — a fresh origin replaying repo10's own
  # timeline (SHA1 -> SHA2, then SCRATCH10's force-push + after-rewrite commit) — independent of BARE10
  q git init -q --bare -b main "$1"
  q git -C "$1" config receive.denyDeleteCurrent ignore
  q git -C "$SEED10" push -q "$1" main:main
  q git -C "$SCRATCH10" push -q --force "$1" main:main
}
clone_rewritten(){ # clone_rewritten <dest-dir> — a fresh origin + clone at the post-rewrite state, seeded prev=SHA2
  mk_rewritten_bare "$1.git"
  q git clone -q "$1.git" "$1"
  seed_prev "$1" main "$SHA2"
}

OUT=$(cd "$WORK10" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "AC2 rewritten base: ERROR names the lost commit"        "has \"ERROR base branch 'main' was rewritten on origin: commit $SHA2 is no longer in its history\""
ok "AC2 rewritten base: says how to see what changed"       "has \"git log $SHA2..refs/remotes/origin/main\" && has \"git log refs/remotes/origin/main..$SHA2\""
ok "AC2 rewritten base: recovery command is not a bare --force onto main" '! has "push --force origin '"$SHA2"':refs/heads/main"'
ok "AC2 rewritten base: says how to accept an intentional rewrite, absolute script path" \
  "has \"then accept it with: bash $SCRIPT --accept-base\""
ok "AC2 rewritten base: doctor exits 1"                '[[ $rc -eq 1 ]]'
ok "AC2 rewritten base: seen commit NOT advanced (keeps reporting until fixed)" 'seen_has "$WORK10" "main $SHA2"'

# execute the printed RECOVERY command verbatim, from its own clone's cwd (an arbitrary project
# checkout, no bin/ dir, nothing pocket-it-specific) — must not discard a single local ref/commit,
# must keep whatever was pushed to main AFTER the rewrite, and bring the next doctor.sh run to green.
WORK10R="$S/repo10-work-recover"; clone_rewritten "$WORK10R"
RECOVER_CMD=$(extract_recover_cmd <<<"$OUT")
LOCAL_BEFORE=$(git -C "$WORK10R" for-each-ref --format='%(refname) %(objectname)' refs/heads | sort)
( cd "$WORK10R" && eval "$RECOVER_CMD" ) >/dev/null 2>&1; recover_rc=$?
LOCAL_AFTER=$(git -C "$WORK10R" for-each-ref --format='%(refname) %(objectname)' refs/heads | sort)
ok "recovery command: runs clean from the project's own cwd" '[[ $recover_rc -eq 0 ]]'
ok "recovery command: local branches/HEAD unchanged (nothing discarded)" '[[ "$LOCAL_BEFORE" == "$LOCAL_AFTER" ]]'
OUT_POST_RECOVER=$(cd "$WORK10R" && bash "$SCRIPT"); rc_post_recover=$?
ok "recovery command: doctor.sh is GREEN on the very next run (not just red-with-different-text)" \
  '[[ $rc_post_recover -eq 0 ]] && ! grep -q "was rewritten on origin" <<<"$OUT_POST_RECOVER"'
ok "recovery command: the commit pushed AFTER the rewrite is still on main's history" \
  '[[ "$(cd "$WORK10R" && git fetch -q origin && git merge-base --is-ancestor '"$AFTER_SHA10"' refs/remotes/origin/main; echo $?)" == 0 ]]'

# mutation A: revert the fix to round 2's non-converging recovery (publish to a side ref, never
# touches main) — on a FRESH clone (BARE10's main is still the raw rewrite, untouched by WORK10R's
# recovery above), the SAME kind of recovery command, executed the SAME way, must fail to go green
WORK10MA="$S/repo10-work-mutA"; clone_rewritten "$WORK10MA"
MUT_RECOVER=$(mktemp "${TMPDIR:-/tmp}/doctor-mut.XXXXXX")
sed '/^                        recover_cmd = ($/,/^                        )$/c\
                        recover_cmd = f"git push origin {prev}:refs/heads/{base}-recovered-{prev[:12]} (a new ref, {base} itself untouched)"  # MUTATED round-2 form' "$SCRIPT" > "$MUT_RECOVER"
OUT_MR=$(cd "$WORK10MA" && bash "$MUT_RECOVER"); rc_mr=$?
RECOVER_CMD_MR=$(extract_recover_cmd <<<"$OUT_MR")
( cd "$WORK10MA" && eval "$RECOVER_CMD_MR" ) >/dev/null 2>&1
OUT_MR_POST=$(cd "$WORK10MA" && bash "$MUT_RECOVER"); rc_mr_post=$?
rm -f "$MUT_RECOVER"
ok "mutation A (round-2 recovery form): fails to turn doctor green — proves the round-3 test is not vacuous" \
  '[[ $rc_mr_post -eq 1 ]] && grep -q "was rewritten on origin" <<<"$OUT_MR_POST"'

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
sed '/^accept_cmd = f"bash {shlex.quote(doctor_abs)} --accept-base"$/c\
accept_cmd = "bash bin/doctor.sh --accept-base"  # MUTATED round-2 form for PI-29 round-3 proof' "$SCRIPT" > "$MUT_ACCEPT"
OUT_MA=$(cd "$WORK10MB" && bash "$MUT_ACCEPT"); rc_ma=$?
ACCEPT_CMD_MA=$(extract_accept_cmd <<<"$OUT_MA")
ERR_MA=$( ( cd "$WORK10MB" && eval "$ACCEPT_CMD_MA" ) 2>&1 ); rc_ma_run=$?
rm -f "$MUT_ACCEPT"
ok "mutation B (round-2 accept form): the printed command, run from the project, fails (no bin/doctor.sh there) — proves the test is not vacuous" \
  '[[ $rc_ma_run -ne 0 ]] && grep -qi "no such file" <<<"$ERR_MA"'

# AC3: deleted base — an ERROR naming the last known-good commit to recover from (unaffected by
# locale: classified from `ls-remote --exit-code`'s exit status, never from stderr text — see the
# fake-git locale regression tests below, repo 13). Its own fresh origin (SHA1->SHA2 only, no
# rewrite needed to test a deletion) so it is independent of everything repo10 did above.
BARE10DEL="$S/repo10-del-origin.git"
q git init -q --bare -b main "$BARE10DEL"
q git -C "$BARE10DEL" config receive.denyDeleteCurrent ignore
q git -C "$SEED10" push -q "$BARE10DEL" main:main
WORK10DEL="$S/repo10-work-deleted"
q git clone -q "$BARE10DEL" "$WORK10DEL"
seed_prev "$WORK10DEL" main "$SHA2"
q git -C "$SEED10" push -q "$BARE10DEL" --delete main
OUT=$(cd "$WORK10DEL" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "AC3 deleted base: ERROR reported"                  'has "ERROR base branch '"'"'main'"'"' no longer exists on origin"'
ok "AC3 deleted base: doctor exits 1"                  '[[ $rc -eq 1 ]]'

# --accept-base on a DELETED base (finding 3, round 3): must say it is deleted and what to do, never
# "try again once reachable" (that phrase is only true for a transient/unreachable origin)
OUT_ACCEPT_DEL=$(cd "$WORK10DEL" && bash "$SCRIPT" --accept-base); rc_accept_del=$?
BASE_SEEN_BEFORE=$(cat "$(common "$WORK10DEL")/pocket-it/base-seen" 2>/dev/null)
ok "--accept-base on deleted base: exits 1"                          '[[ $rc_accept_del -eq 1 ]]'
ok "--accept-base on deleted base: says it no longer exists, not 'try again once reachable'" \
  'grep -q "no longer exists on origin" <<<"$OUT_ACCEPT_DEL" && ! grep -qi "try again once reachable" <<<"$OUT_ACCEPT_DEL"'
ok "--accept-base on deleted base: says how to restore it"           'grep -q "restore it with: git push origin" <<<"$OUT_ACCEPT_DEL"'
ok "--accept-base on deleted base: base-seen left untouched"         '[[ "$(cat "$(common "$WORK10DEL")/pocket-it/base-seen" 2>/dev/null)" == "$BASE_SEEN_BEFORE" ]]'

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
cat > "$MUT_LOCALE.sed" <<'SEDEOF'
/^def _classify_base(base, env):$/,/^    return "unreachable", (stderr\.splitlines()\[-1\] if stderr else "no network")$/c\
def _classify_base(base, env):\
    f = subprocess.run(["git", "fetch", "--quiet", "origin", f"+refs/heads/{base}:refs/remotes/origin/{base}"], capture_output=True, text=True, env=env)  # MUTATED round-2 form\
    if f.returncode == 0: return "ok", None\
    stderr = f.stderr.strip()\
    if re.search(r"couldn.t find remote ref", stderr, re.I): return "deleted", None\
    return "unreachable", (stderr.splitlines()[-1] if stderr else "no network")
SEDEOF
sed -f "$MUT_LOCALE.sed" "$SCRIPT" > "$MUT_LOCALE"
rm -f "$MUT_LOCALE.sed"
OUT_MUT_FAKE=$(cd "$WORK13" && PATH="$FAKEGIT:$PATH" LC_ALL=it_IT.UTF-8 LANGUAGE=it bash "$MUT_LOCALE"); rc_mut_fake=$?
rm -f "$MUT_LOCALE"
echo "$OUT_MUT_FAKE" | sed 's/^/      | /'
ok "mutation (round-2 text-based classify), same fake git: degrades to a warn — proves the test is not vacuous" \
  '[[ $rc_mut_fake -eq 0 ]] && ! grep -q "ERROR base branch" <<<"$OUT_MUT_FAKE" && grep -q "warn  could not verify base branch" <<<"$OUT_MUT_FAKE"'

exit $fail
