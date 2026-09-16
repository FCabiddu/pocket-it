#!/usr/bin/env bash
# Self-test for verify.sh — PI-11: the "test files in diff" check must recognise *.test.sh (this repo's own
# test convention, e.g. bin/*.test.sh and .claude/hooks/*.test.sh) alongside the already-supported
# JS/TS/Python/Go patterns, without widening the match to any *.sh file, and without changing the count or
# behaviour for the languages already covered.
cd "$(dirname "$0")"
# PI-34 giro 2: job control on. Without it, POSIX/bash makes an async command ("cmd &" from a non-interactive,
# job-control-off shell, exactly what the SIGINT test below needs to do) start with SIGINT pre-ignored, and a
# `trap … INT` inside that command has no effect on a signal that was already ignored at its own start — not a
# verify.sh bug, a property of how *this test* has to launch it to be able to signal it mid-run; SIGTERM is
# unaffected and worked already. Measured: identical harness, only `set -m` added, turns the SIGINT case from
# "trap never runs, script finishes normally" to "trap runs, exit 130" — confirmed with a minimal repro.
set -m
SCRIPT="$PWD/verify.sh"
S=$(mktemp -d "${TMPDIR:-/tmp}/verify-test.XXXXXX")
S=$(cd "$S" && pwd -P)   # resolve any symlink (e.g. macOS /tmp) so it matches git's resolved toplevel
UNIQ=$(basename "$S")   # per-run id, only used to name the fixture repo below
# PI-34: verify.sh's own throwaway worktree now lives under <repo>/.claude/worktrees/, i.e. under $M below,
# which is itself under $S — a plain "rm -rf $S" removes it along with everything else this run created.
# Nothing is ever created outside $S any more, so there is no separate shared-directory cleanup left to do.
cleanup(){ rm -rf "$S" 2>/dev/null; }
trap cleanup EXIT
fail=0
ok(){ if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
q(){ "$@" >/dev/null 2>&1; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null

q git init -q --bare "$S/origin.git"
q git init -q -b main "$S/$UNIQ"; M="$S/$UNIQ"
echo base > "$M/README.md"; q git -C "$M" add README.md; q git -C "$M" commit -qm base
q git -C "$M" remote add origin "$S/origin.git"; q git -C "$M" push -q -u origin main

# mkbranch <name> <file>... — a branch off main that adds one commit touching the given files
mkbranch(){
  local name="$1"; shift
  q git -C "$M" checkout -q -b "$name" main
  local f
  for f in "$@"; do mkdir -p "$M/$(dirname "$f")"; echo content > "$M/$f"; q git -C "$M" add "$f"; done
  q git -C "$M" commit -qm "$name"
  q git -C "$M" push -q -u origin "$name"
  q git -C "$M" checkout -q main
}

# AC1 — a diff with a *.test.sh file is reported as a test file, with the right count
mkbranch ac1-shell-test "bin/newthing.test.sh"
OUT1=$(cd "$M" && bash "$SCRIPT" ac1-shell-test main 2>&1)
ok "AC1 — reports the *.test.sh file as a test, count 1" "echo \"\$OUT1\" | grep -qE '^info  test files in diff: 1\$'"
ok "AC1 — no longer falsely warns of an empty diff" "! echo \"\$OUT1\" | grep -q 'warn  no test files in the diff'"

# AC2 — a diff with only a non-test *.sh file: the warning still fires, unchanged
mkbranch ac2-shell-nontest "bin/plainscript.sh"
OUT2=$(cd "$M" && bash "$SCRIPT" ac2-shell-nontest main 2>&1)
ok "AC2 — still warns when the diff has no test files" "echo \"\$OUT2\" | grep -q 'warn  no test files in the diff'"
ok "AC2 — a plain .sh is not misreported as a test file" "! echo \"\$OUT2\" | grep -q 'info  test files in diff'"

# AC3 — a diff with test files in the already-recognised languages: count and behaviour unchanged
mkbranch ac3-other-langs "src/foo.test.ts" "pkg/bar_test.go"
OUT3=$(cd "$M" && bash "$SCRIPT" ac3-other-langs main 2>&1)
ok "AC3 — still reports 2 test files for a JS/TS + Go diff" "echo \"\$OUT3\" | grep -qE '^info  test files in diff: 2\$'"

# mixed — a shell test alongside an already-recognised-language test: both counted together
mkbranch ac1-mixed "bin/other.test.sh" "src/foo.spec.tsx"
OUT4=$(cd "$M" && bash "$SCRIPT" ac1-mixed main 2>&1)
ok "mixed — shell test and JS/TS test are both counted" "echo \"\$OUT4\" | grep -qE '^info  test files in diff: 2\$'"

# --- PI-34: the throwaway worktree lives under <repo>/.claude/worktrees/, never /tmp ---

# AC1 — a git-call log (real git wrapped, args recorded) proves the "worktree add" target path, without
# relying on a racy before/after diff of the real /tmp (this fixture repo itself lives under a mktemp dir).
REALGIT=$(command -v git)
FAKEBIN="$S/fakebin"; mkdir -p "$FAKEBIN"
GITLOG="$S/git-calls.log"; : > "$GITLOG"
cat > "$FAKEBIN/git" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GITLOG"
exec "$REALGIT" "\$@"
SH
chmod +x "$FAKEBIN/git"

mkbranch pi34-ac1 "bin/pi34-ac1.test.sh"
(cd "$M" && PATH="$FAKEBIN:$PATH" bash "$SCRIPT" pi34-ac1 main >/dev/null 2>&1)
ADD_LINE=$(grep '^worktree add ' "$GITLOG" | tail -1)
R1=1; printf '%s' "$ADD_LINE" | grep -qF "$M/.claude/worktrees/" && R1=0
ok "PI-34 AC1 — the throwaway worktree is created under <repo>/.claude/worktrees/" "[ $R1 -eq 0 ]"
R2=0; grep -q pocket-it-verify "$GITLOG" && R2=1
ok "PI-34 AC1 — no worktree is created under the old shared /tmp/pocket-it-verify path" "[ $R2 -eq 0 ]"

# AC2 — a SIGTERM/SIGINT sent once the worktree exists (a slow "affected tests" step gives us the window, via
# a per-branch .pocket-it.json testCommand) leaves no worktree registered, exits non-zero (never GREEN), and
# never runs anything in — or touches — the main checkout: giro 2 finding 1, a bug the earlier version of this
# test could not see (it only checked the worktree was gone, not that the script actually stopped there).
q git -C "$M" checkout -q -b pi34-ac2 main
mkdir -p "$M/bin"; echo content > "$M/bin/pi34-ac2.test.sh"
printf '{"testCommand":"sleep 2"}\n' > "$M/.pocket-it.json"
q git -C "$M" add bin/pi34-ac2.test.sh .pocket-it.json
q git -C "$M" commit -qm pi34-ac2
q git -C "$M" push -q -u origin pi34-ac2
q git -C "$M" checkout -q main

# kill_mid_run <label> <signal> <expected exit code> — runs verify.sh on pi34-ac2, kills it with <signal> once
# its worktree is registered, and checks: no worktree left, that exact exit code, no "GREEN", and the main
# checkout ($M) exactly as it was (git status and the tracked file's mtime, both taken just before the signal).
kill_mid_run(){
  local label="$1" sig="$2" want_rc="$3" log="$S/kmr-$sig.log"
  (cd "$M" && exec bash "$SCRIPT" pi34-ac2 main) >"$log" 2>&1 &
  local kpid=$! i=0 j=0 mstat_before mtime_before rc
  while (( i < 100 )) && ! git -C "$M" worktree list | grep -q '.claude/worktrees/verify-'; do sleep 0.1; i=$((i+1)); done
  mstat_before=$(git -C "$M" status --porcelain)
  mtime_before=$(stat -f%m "$M/README.md" 2>/dev/null || stat -c%Y "$M/README.md" 2>/dev/null)
  kill "-$sig" "$kpid" 2>/dev/null
  while (( j < 100 )) && kill -0 "$kpid" 2>/dev/null; do sleep 0.1; j=$((j+1)); done
  kill -0 "$kpid" 2>/dev/null && kill -KILL "$kpid" 2>/dev/null
  wait "$kpid" 2>/dev/null; rc=$?
  local r_wt=1; git -C "$M" worktree list | grep -q '.claude/worktrees/verify-' || r_wt=0
  ok "$label — leaves no worktree registered" "[ $r_wt -eq 0 ]"
  local r_dir=1; [ -z "$(find "$M/.claude/worktrees" -mindepth 1 -maxdepth 1 -name 'verify-*' 2>/dev/null)" ] && r_dir=0
  ok "$label — no leftover verify-* directory under .claude/worktrees" "[ $r_dir -eq 0 ]"
  ok "$label — exits $want_rc, never 0" "[ $rc -eq $want_rc ]"
  ok "$label — never prints verify: GREEN" "! grep -q 'verify: GREEN' '$log'"
  local mstat_after mtime_after; mstat_after=$(git -C "$M" status --porcelain)
  mtime_after=$(stat -f%m "$M/README.md" 2>/dev/null || stat -c%Y "$M/README.md" 2>/dev/null)
  ok "$label — the main checkout's git status is unchanged" "[ \"$mstat_before\" = \"$mstat_after\" ]"
  ok "$label — the main checkout's tracked file mtime is unchanged" "[ \"$mtime_before\" = \"$mtime_after\" ]"
}
kill_mid_run "PI-34 AC2 SIGTERM (test-run phase)" TERM 143
kill_mid_run "PI-34 AC2 SIGINT (test-run phase)" INT 130

# round 3 — the trap must be armed before the *first* external command verify.sh ever runs, not just from
# worktree creation down. Every external command the script shells out to is either one of the two ungated
# calls before a worktree exists (git fetch, git worktree add — each gets its own phase test here and above/
# below) or funnelled through run()+guard() afterwards (lint, type-check, the test command — one shared
# codepath, already proven by the test-run-phase case above for both INT and TERM). That covers every phase by
# the script's own control flow, not by a hand-picked subset of it: a signal fired at the earliest possible
# point (fetch, before this fix the very first uncovered phase) is the strongest instance of "any phase" left
# to prove, since the trap is armed once and never disabled except inside on_signal itself.
REALGIT3=$(command -v git)
FAKEBIN3="$S/fakebin3"; mkdir -p "$FAKEBIN3"
FETCH_MARK="$S/fetch-started"
cat > "$FAKEBIN3/git" <<SH
#!/usr/bin/env bash
if [[ "\$1" == fetch ]]; then touch "$FETCH_MARK"; sleep 1.5; exec "$REALGIT3" "\$@"; fi
exec "$REALGIT3" "\$@"
SH
chmod +x "$FAKEBIN3/git"
mkbranch pi34-ac2fetch "bin/pi34-ac2fetch.test.sh"
LOG_FETCH="$S/kmr-fetch.log"
rm -f "$FETCH_MARK"
(cd "$M" && exec env PATH="$FAKEBIN3:$PATH" bash "$SCRIPT" pi34-ac2fetch main) >"$LOG_FETCH" 2>&1 &
KPID_F=$!
i=0
while (( i < 50 )) && [ ! -f "$FETCH_MARK" ]; do sleep 0.1; i=$((i+1)); done
mstat_before_f=$(git -C "$M" status --porcelain)
kill -TERM "$KPID_F" 2>/dev/null
j=0
while (( j < 100 )) && kill -0 "$KPID_F" 2>/dev/null; do sleep 0.1; j=$((j+1)); done
kill -0 "$KPID_F" 2>/dev/null && kill -KILL "$KPID_F" 2>/dev/null
wait "$KPID_F" 2>/dev/null; RC_F=$?
R_WT_F=1; git -C "$M" worktree list | grep -q '.claude/worktrees/verify-' || R_WT_F=0
mstat_after_f=$(git -C "$M" status --porcelain)
ok "PI-34 AC2 — SIGTERM during fetch (before any worktree exists) leaves nothing registered" "[ $R_WT_F -eq 0 ]"
ok "PI-34 AC2 — SIGTERM during fetch exits 143, never GREEN" "[ $RC_F -eq 143 ] && ! grep -q 'verify: GREEN' '$LOG_FETCH'"
ok "PI-34 AC2 — SIGTERM during fetch never touches the main checkout" "[ \"\$mstat_before_f\" = \"\$mstat_after_f\" ]"

# same class of check, one signal, during a different phase: right after the worktree is created but before
# any check has run — a git shim delays returning from "worktree add" so the kill lands there instead.
REALGIT2=$(command -v git)
FAKEBIN2="$S/fakebin2"; mkdir -p "$FAKEBIN2"
cat > "$FAKEBIN2/git" <<SH
#!/usr/bin/env bash
if [[ "\$1" == worktree && "\$2" == add ]]; then "$REALGIT2" "\$@"; rc=\$?; sleep 1.5; exit \$rc; fi
exec "$REALGIT2" "\$@"
SH
chmod +x "$FAKEBIN2/git"
mkbranch pi34-ac2creation "bin/pi34-ac2creation.test.sh"
LOG_CREATION="$S/kmr-creation.log"
(cd "$M" && exec env PATH="$FAKEBIN2:$PATH" bash "$SCRIPT" pi34-ac2creation main) >"$LOG_CREATION" 2>&1 &
KPID_C=$!
i=0
while (( i < 50 )) && ! git -C "$M" worktree list | grep -q '.claude/worktrees/verify-'; do sleep 0.1; i=$((i+1)); done
kill -TERM "$KPID_C" 2>/dev/null
j=0
while (( j < 100 )) && kill -0 "$KPID_C" 2>/dev/null; do sleep 0.1; j=$((j+1)); done
kill -0 "$KPID_C" 2>/dev/null && kill -KILL "$KPID_C" 2>/dev/null
wait "$KPID_C" 2>/dev/null; RC_C=$?
R_WT_C=1; git -C "$M" worktree list | grep -q '.claude/worktrees/verify-' || R_WT_C=0
ok "PI-34 AC2 — SIGTERM right after worktree creation (creation phase) still cleans up" "[ $R_WT_C -eq 0 ]"
ok "PI-34 AC2 — SIGTERM in the creation phase exits 143, never GREEN" "[ $RC_C -eq 143 ] && ! grep -q 'verify: GREEN' '$LOG_CREATION'"

# AC3 — a branch with slashes must never collide with an agent's own worktree sitting at the naive slug
# (branch "agent/branch/with/slashes" naively slugs to the same "agent-branch-with-slashes" as a real,
# differently-named branch an agent worktree is already checked out on).
q git -C "$M" checkout -q -b agent-branch-with-slashes main
mkdir -p "$M/bin"; echo content > "$M/bin/agent-marker.test.sh"
q git -C "$M" add bin/agent-marker.test.sh
q git -C "$M" commit -qm agent-branch-with-slashes
q git -C "$M" checkout -q main

AGENT_WT="$M/.claude/worktrees/agent-branch-with-slashes"
q git -C "$M" worktree add -q "$AGENT_WT" agent-branch-with-slashes
q git -C "$M" worktree lock --reason "pocket-it: agent worktree for agent-branch-with-slashes since 2026-01-01T00:00Z" "$AGENT_WT"
echo wip-marker > "$AGENT_WT/WIP.txt"

mkbranch "agent/branch/with/slashes" "bin/pi34-ac3.test.sh"
OUT_AC3=$(cd "$M" && bash "$SCRIPT" "agent/branch/with/slashes" main 2>&1)

R5=1; echo "$OUT_AC3" | grep -qE 'verify: (GREEN|RED)' && R5=0
ok "PI-34 AC3 — verify.sh completes despite an agent worktree at the same naive slug" "[ $R5 -eq 0 ]"
R6=1; [ -f "$AGENT_WT/WIP.txt" ] && R6=0
ok "PI-34 AC3 — the agent worktree's own uncommitted file is untouched" "[ $R6 -eq 0 ]"
LOCK_LINE=$(git -C "$M" worktree list --porcelain | awk -v w="worktree $AGENT_WT" '$0==w{f=1} f&&/^locked/{print;exit} /^$/{f=0}')
R7=1; [ -n "$LOCK_LINE" ] && R7=0
ok "PI-34 AC3 — the agent worktree stays registered and locked, never removed by verify.sh" "[ $R7 -eq 0 ]"

q git -C "$M" worktree unlock "$AGENT_WT"
q git -C "$M" worktree remove --force "$AGENT_WT"

# AC4 — reviewer.md no longer sends a throwaway worktree to /tmp (lines 39 and 73)
# (the script already cd'd into bin/ at the top, so the repo root is simply its parent)
REPO_ROOT="$(cd .. && pwd)"
RVWR="$REPO_ROOT/.claude/agents/reviewer.md"
R8=0; grep -nE '(worktree add|WT=).*/tmp/' "$RVWR" >/dev/null 2>&1 && R8=1
ok "PI-34 AC4 — reviewer.md never creates a worktree at a literal /tmp path" "[ $R8 -eq 0 ]"
R9=0; grep -n '/tmp' "$RVWR" | grep -qvE '\.claude/worktrees|worktree\.sh' && R9=1
ok "PI-34 AC4 — every remaining /tmp mention in reviewer.md points to .claude/worktrees or worktree.sh" "[ $R9 -eq 0 ]"

# PI-34 finding 2 — conflict resolution must never reuse/remove the branch's own (possibly the developer's,
# locked, WIP-holding) worktree: bin/worktree.sh REUSES an existing worktree for the branch, so it is not what
# conflict resolution may call; it must use its own, separately-named, throwaway one.
R13=1; grep -q 'reviewer-conflict-' "$RVWR" && ! grep -q 'bin/worktree.sh "\$PWD" {branch}' "$RVWR" && R13=0
ok "PI-34 finding 2 — conflict resolution uses its own throwaway worktree, not bin/worktree.sh" "[ $R13 -eq 0 ]"
R14=1; grep -qi 'never touch, unlock or remove any worktree already registered' "$RVWR" && R14=0
ok "PI-34 finding 2 — reviewer.md states it must never touch the branch's own worktree" "[ $R14 -eq 0 ]"
# PI-34 finding 3 — $WT must be computed once and reused for removal, not recomputed with $$ in a later call
R15=1; grep -qE 'created and removed in the \*\*same\*\* shell call' "$RVWR" && R15=0
ok "PI-34 finding 3 — local verification computes \$WT once, in the same shell call as its removal" "[ $R15 -eq 0 ]"

# PI-34 finding 3, round 3 — line 39 (conflict resolution) closed the $$ class only on line 73 (single-call
# local verification, where $$ is safe because create+remove share one command); conflict resolution spans
# several Bash calls (create, merge, edit conflicts, commit, push, remove) so $$ there would name a different
# path on each call. The conflict-resolution paragraph must build its path from the stable PR number instead.
CONFLICT_PARA=$(awk '/CONFLICTING.*resolve against/,/UNKNOWN.*re-query/' "$RVWR")
R16=1; echo "$CONFLICT_PARA" | grep -qF '$$' || R16=0
ok "PI-34 finding 3 (round 3) — conflict resolution's worktree path no longer depends on \$\$" "[ $R16 -eq 0 ]"
R17=1; echo "$CONFLICT_PARA" | grep -qF 'reviewer-conflict-pr{N}' && R17=0
ok "PI-34 finding 3 (round 3) — conflict resolution uses a literal, PR-number-based path" "[ $R17 -eq 0 ]"

# PI-34 finding 5 — .git/info/exclude must resolve via --git-common-dir: a linked worktree's own ".git" is a
# FILE (a gitlink), not a directory, and mkdir -p on a path below it used to fail when verify.sh was launched
# from inside one (a reviewer working from their own worktree, not the main checkout).
LINKED_WT="$S/linked-launch-wt"
q git -C "$M" worktree add -q --detach "$LINKED_WT" main
mkbranch pi34-ac5 "bin/pi34-ac5.test.sh"
OUT_AC5=$(cd "$LINKED_WT" && bash "$SCRIPT" pi34-ac5 main 2>&1)
R10=1; echo "$OUT_AC5" | grep -qiE 'not a directory|no such file' || R10=0
ok "PI-34 AC5 — no .git/info/exclude error when launched from a linked worktree" "[ $R10 -eq 0 ]"
R11=1; echo "$OUT_AC5" | grep -qE 'verify: (GREEN|RED)' && R11=0
ok "PI-34 AC5 — verify.sh still completes when launched from a linked worktree" "[ $R11 -eq 0 ]"
R12=1; grep -qxF '.claude/worktrees/' "$M/.git/info/exclude" 2>/dev/null && R12=0
ok "PI-34 AC5 — the exclude entry lands in the shared .git/info/exclude, not a per-worktree one" "[ $R12 -eq 0 ]"
q git -C "$M" worktree remove --force "$LINKED_WT"

# ============================ PI-41 — whose defect is a red check? ============================
# Everything below runs against its own disposable repo ($P, with its own bare origin under $S), because
# these cases move the BASE branch under a fixture branch on purpose (that is the whole mutation proof) and
# must not disturb the branches the tests above built on $M. Both repos die with $S.
#
# The single check these fixtures drive is the "affected tests" one, via a .pocket-it.json testCommand of
# "bash ./check.sh": whichever worktree the command runs in supplies its own check.sh, so the same command
# string can pass on one side and fail on the other — exactly the asymmetry attribution has to read. check.sh
# records the directory it ran in, so one artefact proves both "how many times did it run" (AC4) and "did the
# base re-check really happen inside the throwaway base worktree" (AC5 guard).
P="$S/pi41"; PORIGIN="$S/pi41-origin.git"
CALLLOG="$S/pi41-check-cwds.log"; LINTLOG="$S/pi41-lint-cwds.log"
: > "$CALLLOG"; : > "$LINTLOG"
q git init -q --bare "$PORIGIN"
q git init -q -b main "$P"
wcheck(){ # wcheck <path> <body> — a check script that records its cwd, then runs <body> (e.g. "exit 1")
  printf '#!/usr/bin/env bash\npwd -P >> %s\n%s\n' "$CALLLOG" "$2" > "$1"; chmod +x "$1"; }
wlint(){ printf '#!/usr/bin/env bash\npwd -P >> %s\n%s\n' "$LINTLOG" "$2" > "$1"; chmod +x "$1"; }
pfile(){ mkdir -p "$(dirname "$1")"; echo content > "$1"; }   # bin/ does not survive a checkout of main
p_commit(){ # p_commit <msg> — commit everything on the current branch, push it, go back to main
  local b; b=$(git -C "$P" rev-parse --abbrev-ref HEAD)
  q git -C "$P" add -A; q git -C "$P" commit -qm "$1"; q git -C "$P" push -q -u origin "$b"
  q git -C "$P" checkout -q main; }
set_base(){ # set_base <body> — main's check.sh gets this body; this is the mutation AC2 turns on and off
  q git -C "$P" checkout -q main; wcheck "$P/check.sh" "$1"; p_commit "base check: $1"; }
# runp <branch> [extra PATH dir] — run verify.sh on the pi41 repo, capture output and exit code
runp(){ local br="$1" pre="${2:-}"
  : > "$CALLLOG"; : > "$LINTLOG"
  if [[ -n "$pre" ]]; then OUTP=$(cd "$P" && PATH="$pre:$PATH" bash "$SCRIPT" "$br" main 2>&1); RCP=$?
  else OUTP=$(cd "$P" && bash "$SCRIPT" "$br" main 2>&1); RCP=$?; fi; }
hasl(){ printf '%s\n' "$1" | grep -qF "$2"; }   # fixed-string line match on a captured output

echo base > "$P/README.md"
wcheck "$P/check.sh" "exit 0"
printf '{"testCommand":"bash ./check.sh"}\n' > "$P/.pocket-it.json"
q git -C "$P" add -A; q git -C "$P" commit -qm base
q git -C "$P" remote add origin "$PORIGIN"; q git -C "$P" push -q -u origin main

# a git that records its calls — used to prove a worktree was (or was never) created for the base
GBIN="$S/pi41-gitbin"; mkdir -p "$GBIN"; GLOG="$S/pi41-git.log"; REALGITP=$(command -v git)
cat > "$GBIN/git" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GLOG"
exec "$REALGITP" "\$@"
SH
chmod +x "$GBIN/git"

# --- AC4 — a green run pays nothing: no base worktree, no check re-run -------------------------------------
q git -C "$P" checkout -q -b pi41-green main
pfile "$P/bin/green.test.sh"; p_commit pi41-green
: > "$GLOG"; runp pi41-green "$GBIN"
R41=1; [ "$RCP" -eq 0 ] && R41=0
ok "PI-41 AC4 — an all-green run still exits 0" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "verify: GREEN" && R41=0
ok "PI-41 AC4 — an all-green run still prints verify: GREEN" "[ $R41 -eq 0 ]"
R41=0; grep '^worktree add\|worktree add ' "$GLOG" | grep -q 'verify-base-' && R41=1
ok "PI-41 AC4 — no worktree is created for the base when nothing failed" "[ $R41 -eq 0 ]"
R41=0; [ -n "$(find "$P/.claude/worktrees" -mindepth 1 -maxdepth 1 -name 'verify-base-*' 2>/dev/null)" ] && R41=1
ok "PI-41 AC4 — no verify-base-* directory exists after a green run" "[ $R41 -eq 0 ]"
R41=1; [ "$(grep -c . "$CALLLOG")" -eq 1 ] && R41=0
ok "PI-41 AC4 — the passing check ran exactly once, never re-run against the base" "[ $R41 -eq 0 ]"

# --- AC1 — the branch's own red: base green, branch breaks the check ---------------------------------------
q git -C "$P" checkout -q -b pi41-own main
wcheck "$P/check.sh" "exit 1"; pfile "$P/bin/own.test.sh"; p_commit pi41-own
runp pi41-own
R41=1; [ "$RCP" -eq 1 ] && R41=0
ok "PI-41 AC1 — an own-diff red still exits 1, the code that already meant 'the branch is red'" "[ $R41 -eq 0 ]"
R41=1; printf '%s\n' "$OUTP" | grep -qx 'verify: RED' && R41=0
ok "PI-41 AC1 — an own-diff red still prints exactly 'verify: RED', unqualified" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "own   affected tests — passes at the tip of origin/main" && R41=0
ok "PI-41 AC1 — the failing check is named as this branch's own" "[ $R41 -eq 0 ]"
R41=0; hasl "$OUTP" "pre-existing" && R41=1
ok "PI-41 AC1 — nothing in an own-diff red mentions a pre-existing defect" "[ $R41 -eq 0 ]"
R41=1; [ "$(grep -c . "$CALLLOG")" -eq 2 ] && R41=0
ok "PI-41 AC4 — a failing check is re-run against the base exactly once (2 runs in total)" "[ $R41 -eq 0 ]"

# --- AC2 — inherited red: the same failure is already at the tip of origin/main ------------------------------
set_base "exit 1"
q git -C "$P" checkout -q -b pi41-inherited main
pfile "$P/bin/unrelated.test.sh"; p_commit pi41-inherited
: > "$GLOG"; runp pi41-inherited "$GBIN"
R41=1; [ "$RCP" -eq 3 ] && R41=0
ok "PI-41 AC2 — an inherited red exits 3, a code no other outcome uses" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "verify: RED — pre-existing on base (cause: base-moved)" && R41=0
ok "PI-41 AC2 — the verdict line names the base and the reviewer's own cause vocabulary" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "base  affected tests — already fails at the tip of origin/main" && R41=0
ok "PI-41 AC2 — the check itself is named as pre-existing on the base" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "note  attribution is per check" && R41=0
ok "PI-41 AC2 — the granularity of the word 'pre-existing' is stated on the run that uses it" "[ $R41 -eq 0 ]"
# AC5 — the base re-check happened inside a throwaway worktree under <repo>/.claude/worktrees/, never in the
# main checkout and never in /tmp: check.sh recorded the directory it actually ran in, both times.
CW1=$(sed -n 1p "$CALLLOG"); CW2=$(sed -n 2p "$CALLLOG")
R41=1; case "$CW1" in "$P/.claude/worktrees/verify-"*) R41=0;; esac
ok "PI-41 AC5 — the branch's check ran inside the branch's throwaway worktree" "[ $R41 -eq 0 ]"
R41=1; case "$CW2" in "$P/.claude/worktrees/verify-base-"*) R41=0;; esac
ok "PI-41 AC5 — the base re-check ran inside a throwaway worktree under <repo>/.claude/worktrees/" "[ $R41 -eq 0 ]"
R41=0; { [ "$CW2" = "$P" ] || case "$CW2" in /tmp/*|/private/tmp/*) true;; *) false;; esac; } && R41=1
ok "PI-41 AC5 — the base re-check ran neither in the main checkout nor under /tmp" "[ $R41 -eq 0 ]"
R41=0; [ -n "$(find "$P/.claude/worktrees" -mindepth 1 -maxdepth 1 -name 'verify-base-*' 2>/dev/null)" ] && R41=1
ok "PI-41 AC5 — the base worktree is gone once the run ends normally" "[ $R41 -eq 0 ]"
R41=0; git -C "$P" worktree list | grep -q '.claude/worktrees/verify-' && R41=1
ok "PI-41 AC5 — no worktree of either kind stays registered after a normal run" "[ $R41 -eq 0 ]"

# --- AC2, by mutation — fix the base and the very same run must flip to the branch's own red, then back -----
set_base "exit 0"
runp pi41-inherited
R41=1; [ "$RCP" -eq 1 ] && R41=0
ok "PI-41 AC2 mutation — base made green: the same branch now exits 1, not 3" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "own   affected tests — passes at the tip of origin/main" && R41=0
ok "PI-41 AC2 mutation — base made green: the failure is now attributed to the branch" "[ $R41 -eq 0 ]"
R41=0; hasl "$OUTP" "pre-existing" && R41=1
ok "PI-41 AC2 mutation — base made green: nothing is called pre-existing any more" "[ $R41 -eq 0 ]"
set_base "exit 1"
runp pi41-inherited
R41=1; [ "$RCP" -eq 3 ] && R41=0
ok "PI-41 AC2 mutation — base broken again: the same branch flips back to exit 3" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "base  affected tests — already fails at the tip of origin/main" && R41=0
ok "PI-41 AC2 mutation — base broken again: the check is pre-existing once more" "[ $R41 -eq 0 ]"

# --- AC6 — an attribution that could not be performed is never reported as 'pre-existing on base' ------------
# (a) the throwaway worktree for the base cannot be created. Same fixture as AC2, which without the shim
# reports "pre-existing": only the refusal changes, so the test cannot pass by accident.
GBIN_A="$S/pi41-gitbin-a"; mkdir -p "$GBIN_A"
cat > "$GBIN_A/git" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GLOG"
if [[ "\$*" == *"worktree add"*"verify-base-"* ]]; then echo "fixture: refusing" >&2; exit 128; fi
exec "$REALGITP" "\$@"
SH
chmod +x "$GBIN_A/git"
: > "$GLOG"; runp pi41-inherited "$GBIN_A"
R41=1; [ "$RCP" -eq 1 ] && R41=0
ok "PI-41 AC6a — a refused base worktree falls back to today's plain red, exit 1" "[ $R41 -eq 0 ]"
R41=1; printf '%s\n' "$OUTP" | grep -qx 'verify: RED' && R41=0
ok "PI-41 AC6a — a refused base worktree prints the unqualified 'verify: RED'" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "warn  affected tests — attribution unknown: a throwaway worktree for origin/main could not be created" && R41=0
ok "PI-41 AC6a — the reason the attribution is unknown is named" "[ $R41 -eq 0 ]"
R41=0; hasl "$OUTP" "pre-existing" && R41=1
ok "PI-41 AC6a — a re-check that never ran never says 'pre-existing on base'" "[ $R41 -eq 0 ]"
R41=0; [ -n "$(find "$P/.claude/worktrees" -mindepth 1 -maxdepth 1 -name 'verify-base-*' 2>/dev/null)" ] && R41=1
ok "PI-41 AC6a — a refused base worktree leaves no directory behind" "[ $R41 -eq 0 ]"

# (b) the base's ref cannot be resolved at all (an unfetchable base): no worktree is even attempted.
GBIN_B="$S/pi41-gitbin-b"; mkdir -p "$GBIN_B"
cat > "$GBIN_B/git" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GLOG"
if [[ "\$*" == *"rev-parse --verify -q origin/main^{commit}"* ]]; then exit 1; fi
exec "$REALGITP" "\$@"
SH
chmod +x "$GBIN_B/git"
: > "$GLOG"; runp pi41-inherited "$GBIN_B"
R41=1; [ "$RCP" -eq 1 ] && R41=0
ok "PI-41 AC6b — an unresolvable base ref falls back to plain red, exit 1" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "warn  affected tests — attribution unknown: origin/main is not available locally" && R41=0
ok "PI-41 AC6b — the unknown names the missing base ref" "[ $R41 -eq 0 ]"
R41=0; grep 'worktree add ' "$GLOG" | grep -q 'verify-base-' && R41=1
ok "PI-41 AC6b — no base worktree is attempted when the base ref cannot be resolved" "[ $R41 -eq 0 ]"
R41=1; [ "$(grep -c . "$CALLLOG")" -eq 1 ] && R41=0
ok "PI-41 AC6b — the check is not re-run when there is nothing to re-run it against" "[ $R41 -eq 0 ]"

# (c) the check itself errors rather than fails (command not found, exit 127) on both sides.
q git -C "$P" checkout -q -b pi41-badcmd main
printf '{"testCommand":"pi41_no_such_command_xyz"}\n' > "$P/.pocket-it.json"
pfile "$P/bin/badcmd.test.sh"; p_commit pi41-badcmd
runp pi41-badcmd
R41=1; [ "$RCP" -eq 1 ] && R41=0
ok "PI-41 AC6c — a check that errors on the base is plain red, exit 1" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "attribution unknown: the check itself could not run on origin/main (exit 127)" && R41=0
ok "PI-41 AC6c — erroring is reported as unknown, distinctly from failing" "[ $R41 -eq 0 ]"
R41=0; hasl "$OUTP" "pre-existing" && R41=1
ok "PI-41 AC6c — an erroring check is never called pre-existing on the base" "[ $R41 -eq 0 ]"

# --- AC3 — one check the branch broke, one it inherited: attributed one by one, verdict is the worse one -----
# A second check is needed, so the branch grows a package manifest with a lint script. The fixture's stand-in
# npm runs ./<script>.sh: the point under test is attribution across two checks, not any package manager.
NPMBIN="$S/pi41-npmbin"; mkdir -p "$NPMBIN"
cat > "$NPMBIN/npm" <<'SH'
#!/usr/bin/env bash
# fixture stand-in for npm: `npm run <name>` runs ./<name>.sh in the current directory, nothing else.
[[ "$1" == run ]] || exit 2
exec bash "./$2.sh"
SH
chmod +x "$NPMBIN/npm"
# (c-bis) the base has no script by that name: npm exits 1 for a missing script, which is NOT evidence of a
# pre-existing defect — attribution must be unknown for that check while the other is still read normally.
q git -C "$P" checkout -q -b pi41-noscript main
printf '{"scripts":{"lint":"bash ./lint.sh"}}\n' > "$P/package.json"; printf '{}\n' > "$P/package-lock.json"
wlint "$P/lint.sh" "exit 1"; pfile "$P/bin/noscript.test.sh"; p_commit pi41-noscript
runp pi41-noscript "$NPMBIN"
R41=1; hasl "$OUTP" 'warn  lint — attribution unknown: origin/main has no "lint" script to re-run' && R41=0
ok "PI-41 AC6d — a check the base cannot even declare is unknown, not pre-existing" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "base  affected tests — already fails at the tip of origin/main" && R41=0
ok "PI-41 AC6d — the other failing check is still attributed normally in the same run" "[ $R41 -eq 0 ]"
R41=1; [ "$RCP" -eq 1 ] && R41=0
ok "PI-41 AC6d — one unknown makes the whole verdict the branch's own red, exit 1" "[ $R41 -eq 0 ]"
R41=1; [ "$(grep -c . "$LINTLOG")" -eq 1 ] && R41=0
ok "PI-41 AC6d — a check with no counterpart on the base is not re-run there" "[ $R41 -eq 0 ]"

# now the mixed case itself: lint exists on the base and passes there, the tests check fails on both sides
q git -C "$P" checkout -q main
printf '{"scripts":{"lint":"bash ./lint.sh"}}\n' > "$P/package.json"; printf '{}\n' > "$P/package-lock.json"
wlint "$P/lint.sh" "exit 0"; p_commit "base gets a green lint"
PRE_PKG_MAIN=$(git -C "$P" rev-parse main~1)   # the last main commit without a package manifest (AC5 below)
q git -C "$P" checkout -q -b pi41-mixed main
wlint "$P/lint.sh" "exit 1"; pfile "$P/bin/mixed.test.sh"; p_commit pi41-mixed
runp pi41-mixed "$NPMBIN"
R41=1; hasl "$OUTP" "own   lint — passes at the tip of origin/main" && R41=0
ok "PI-41 AC3 — the check the branch broke is attributed to the branch" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "base  affected tests — already fails at the tip of origin/main" && R41=0
ok "PI-41 AC3 — the check it inherited is attributed to the base, in the same run" "[ $R41 -eq 0 ]"
R41=1; [ "$RCP" -eq 1 ] && R41=0
ok "PI-41 AC3 — the verdict is the worse of the two: exit 1, never 3" "[ $R41 -eq 0 ]"
R41=1; printf '%s\n' "$OUTP" | grep -qx 'verify: RED' && R41=0
ok "PI-41 AC3 — a branch with its own defect is not excused by also inheriting one" "[ $R41 -eq 0 ]"
R41=1; [ "$(grep -c . "$LINTLOG")" -eq 2 ] && [ "$(grep -c . "$CALLLOG")" -eq 2 ] && R41=0
ok "PI-41 AC4 — each failing check is re-run against the base exactly once, no more" "[ $R41 -eq 0 ]"

# --- AC5 — a real signal during the base re-check leaves neither worktree behind ------------------------------
# The base's check.sh sleeps, so the kill lands while the base worktree exists and its command is running.
# The fixture branch forks from the last main commit without a package manifest, so only one check runs.
set_base "sleep 3; exit 1"
q git -C "$P" checkout -q -b pi41-signal "$PRE_PKG_MAIN"
wcheck "$P/check.sh" "exit 1"; pfile "$P/bin/signal.test.sh"; p_commit pi41-signal
kill_in_base(){ # kill_in_base <label> <signal> <expected exit code>
  local label="$1" sig="$2" want="$3" log="$S/pi41-kill-$sig.log" kpid i=0 j=0 rc r
  (cd "$P" && exec bash "$SCRIPT" pi41-signal main) >"$log" 2>&1 &
  kpid=$!
  while (( i < 200 )) && ! git -C "$P" worktree list | grep -q '.claude/worktrees/verify-base-'; do sleep 0.1; i=$((i+1)); done
  r=1; git -C "$P" worktree list | grep -q '.claude/worktrees/verify-base-' && r=0
  ok "$label — the base worktree really existed when the signal was sent" "[ $r -eq 0 ]"
  kill "-$sig" "$kpid" 2>/dev/null
  while (( j < 100 )) && kill -0 "$kpid" 2>/dev/null; do sleep 0.1; j=$((j+1)); done
  kill -0 "$kpid" 2>/dev/null && kill -KILL "$kpid" 2>/dev/null
  wait "$kpid" 2>/dev/null; rc=$?
  r=1; git -C "$P" worktree list | grep -q '.claude/worktrees/verify-' || r=0
  ok "$label — neither worktree stays registered" "[ $r -eq 0 ]"
  r=1; [ -z "$(find "$P/.claude/worktrees" -mindepth 1 -maxdepth 1 -name 'verify-*' 2>/dev/null)" ] && r=0
  ok "$label — no verify-* or verify-base-* directory is left on disk" "[ $r -eq 0 ]"
  r=1; [ "$rc" -eq "$want" ] && r=0
  ok "$label — exits $want, never a verdict" "[ $r -eq 0 ]"
  r=1; grep -qE 'verify: (GREEN|RED)' "$log" || r=0
  ok "$label — prints no verdict at all" "[ $r -eq 0 ]"; }
kill_in_base "PI-41 AC5 SIGTERM during the base re-check" TERM 143
kill_in_base "PI-41 AC5 SIGINT during the base re-check" INT 130
kill_in_base "PI-41 AC5 SIGHUP during the base re-check" HUP 129
[[ $fail -eq 0 ]] && echo "verify.test.sh: ALL PASS" || echo "verify.test.sh: FAILURES"
exit $fail
