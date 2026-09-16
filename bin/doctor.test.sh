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
GUARD="$(cd .. && pwd -P)/.claude/hooks/guard.sh"  # PI-29 round 4: proves doctor's printed commands pass the real guard
guard_rc(){ # guard_rc <cwd> <command> — exit code of guard.sh given <command> as a PreToolUse Bash payload
  local cwd="$1" cmd="$2"
  ( cd "$cwd" && python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$cmd" | bash "$GUARD" >/dev/null 2>&1 )
  echo $?
}
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
python3 - "$SCRIPT" > "$MUT_BS" <<'PYEOF'
import sys
src = open(sys.argv[1]).read()
idx_accept = src.index("if accept_base:")
idx_common = src.index('if common_dir and has_origin:')
segment = src[idx_accept:idx_common]
marker = "        sys.exit(1)\n"
pos = segment.index(marker)  # the FIRST sys.exit(1) inside accept_base closes the "deleted" branch
mutated_segment = segment[:pos] + '        _save_seen(seen_file, {**seen, base: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"})  # MUTATED round-5 proof\n' + segment[pos:]
sys.stdout.write(src[:idx_accept] + mutated_segment + src[idx_common:])
PYEOF
OUT_MUT_BS=$(cd "$WORK10DELACCMUT" && bash "$MUT_BS" --accept-base); rc_mut_bs=$?
rm -f "$MUT_BS"
ok "mutation (accept-base on deleted base silently updates base-seen): base-seen check catches it — proves it is not vacuous" \
  '[[ "$(cat "$(common "$WORK10DELACCMUT")/pocket-it/base-seen" 2>/dev/null)" != "$BS_BEFORE_MUT" ]]'

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
sed '/# PI-37 CHECK BEGIN/,/# PI-37 CHECK END/d' "$SCRIPT" > "$MUT_PI37"
OUT_MUT_PI37=$(cd "$R14" && PATH="$FAKEGH:$PATH" bash "$MUT_PI37"); rc_mut_pi37=$?
rm -f "$MUT_PI37"
echo "$OUT_MUT_PI37" | sed 's/^/      | /'
ok "mutation: check removed, AC1/AC2 positive cases (Todo/In Progress/Needs Work/WIP + merged) all go red" \
  '! grep -q "PR #60 is merged" <<<"$OUT_MUT_PI37" && [[ $rc_mut_pi37 -eq 0 ]]'

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
python3 - "$SCRIPT" "$MUT_PI42" <<'PYEOF'
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
assert n == 1, "PI-42 CHECK marker block not found — mutation did not apply"
open(dst, "w").write(mutated)
PYEOF
OUT_MUT=$(cd "$R15" && bash "$MUT_PI42"); rc_mut=$?
rm -f "$MUT_PI42"
echo "$OUT_MUT" | sed 's/^/      | /'
ok "mutation: hardcoded expected set restored -> AC1/AC4's silence on unusual, uncited numbering goes red" \
  'grep -q "subsections referenced by agents missing" <<<"$OUT_MUT"'

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

exit $fail
