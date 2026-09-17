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
R41=1; hasl "$OUTP" "own   affected tests — passes at origin/main@" && R41=0
ok "PI-41 AC1 — the failing check is named as this branch's own" "[ $R41 -eq 0 ]"
R41=0; { hasl "$OUTP" "also fails at" || hasl "$OUTP" "pre-existing"; } && R41=1
ok "PI-41 AC1 — an own-diff red never says the base fails too" "[ $R41 -eq 0 ]"
R41=1; [ "$(grep -c . "$CALLLOG")" -eq 2 ] && R41=0
ok "PI-41 AC4 — a failing check is re-run against the base exactly once (2 runs in total)" "[ $R41 -eq 0 ]"

# --- AC2 — inherited red: the same failure is already at the tip of origin/main ------------------------------
set_base "exit 1"
q git -C "$P" checkout -q -b pi41-inherited main
pfile "$P/bin/unrelated.test.sh"; p_commit pi41-inherited
: > "$GLOG"; runp pi41-inherited "$GBIN"
R41=1; [ "$RCP" -eq 3 ] && R41=0
ok "PI-41 AC2 — an inherited red exits 3, a code no other outcome uses" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "verify: RED — inherited: every failing check also fails at origin/main@" && R41=0
ok "PI-41 AC2 — the verdict line states what was observed, and names the base commit it was observed at" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "base  affected tests — the same command also fails at origin/main@" && R41=0
ok "PI-41 AC2 — the check itself is named as pre-existing on the base" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "note  attribution is per check" && R41=0
ok "PI-41 AC2 — the granularity of the inherited verdict is stated on the run that uses it" "[ $R41 -eq 0 ]"
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
R41=1; hasl "$OUTP" "own   affected tests — passes at origin/main@" && R41=0
ok "PI-41 AC2 mutation — base made green: the failure is now attributed to the branch" "[ $R41 -eq 0 ]"
R41=0; { hasl "$OUTP" "also fails at" || hasl "$OUTP" "pre-existing"; } && R41=1
ok "PI-41 AC2 mutation — base made green: nothing is said to also fail there any more" "[ $R41 -eq 0 ]"
set_base "exit 1"
runp pi41-inherited
R41=1; [ "$RCP" -eq 3 ] && R41=0
ok "PI-41 AC2 mutation — base broken again: the same branch flips back to exit 3" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "base  affected tests — the same command also fails at origin/main@" && R41=0
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
R41=0; { hasl "$OUTP" "also fails at" || hasl "$OUTP" "pre-existing"; } && R41=1
ok "PI-41 AC6a — a re-check that never ran never says the base fails too" "[ $R41 -eq 0 ]"
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
ok "PI-41 AC6c — a check whose runner is absent on the base is plain red, exit 1" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" 'attribution unknown: "pi41_no_such_command_xyz" does not resolve here' && R41=0
ok "PI-41 AC6c — a command that does not resolve on the base is unknown, and is never even run there" "[ $R41 -eq 0 ]"
R41=0; { hasl "$OUTP" "also fails at" || hasl "$OUTP" "pre-existing"; } && R41=1
ok "PI-41 AC6c — a check that cannot resolve on the base is never said to fail there" "[ $R41 -eq 0 ]"

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
# round 2: the branch also adds the manifest itself, so the rule that fires first is the marker-file one —
# the base has no package.json at all, so `npm run lint` there is not the same check, not a base defect.
# The script rule proper (a base that HAS a manifest but not that script) is fixture F1a further down.
R41=1; hasl "$OUTP" 'warn  lint — attribution unknown: origin/main has no package.json, so this is not the same check there' && R41=0
ok "PI-41 AC6d — a check the base cannot even declare is unknown, never attributed to the base" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "base  affected tests — the same command also fails at origin/main@" && R41=0
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
R41=1; hasl "$OUTP" "own   lint — passes at origin/main@" && R41=0
ok "PI-41 AC3 — the check the branch broke is attributed to the branch" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "base  affected tests — the same command also fails at origin/main@" && R41=0
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

# ============ PI-41 round 2, F1 — "the base could not really run this check" is a CLASS, not two cases =======
# Round 1 guarded exactly one member of it (a package script missing on the base) and read every other
# non-zero exit as evidence of a base defect — so a brand-new failing test that belonged to the branch was
# certified as the base's. The guard is now a single choke point (base_blockers) every re-run goes through,
# and the case list below is REGENERATED from verify.sh's own producer block at run time instead of being a
# list of examples: a command producer added later is covered by these assertions without editing this file.
eval "$(awk '/^# --- base-runnability helpers/,/^# --- end base-runnability helpers/' "$SCRIPT")"
BASE=main   # base_blockers names the base in its reasons; what is asserted is only whether a reason came back
SBX="$S/blockers"
mkdir -p "$SBX/empty" "$SBX/full/node_modules/.bin" "$SBX/full/bin" "$SBX/full/tests" "$SBX/full/src" \
         "$SBX/branch/tests" "$SBX/branch/src"
WT_REAL="$SBX/branch"   # base_blockers compares against the branch worktree it was told about
: > "$SBX/branch/tests/test_x.py"; : > "$SBX/branch/src/new.ts"; : > "$SBX/branch/check.sh"
# reuse base_blockers' own list of package-manager subcommands (verify.sh's $pmsub) instead of keeping a
# second copy of it here — a subcommand added there (a new pm's own verb) is excluded here too, no edit needed.
PMSUB=$(grep -o 'local pmsub=" [^"]*"' "$SCRIPT" | sed -E 's/^local pmsub="//; s/"$//' | head -1)
# PI-46 F1 — PMSUB above is read out of the script it also verifies: if verify.sh's own pmsub ever shrank
# or emptied, PMSUB would shrink or empty with it, and any assertion that only loops over PMSUB would have
# nothing left to check and pass on an empty loop (measured: dropping exec/dlx, or emptying the list to
# nothing, both left the suite ALL PASS). PMSUB_FLOOR is a second, independent list — the test's own, never
# read out of verify.sh — that (a) is looped over instead of PMSUB for the negative half of AC2, so a
# shrunk PMSUB cannot empty that loop, and (b) is checked as a subset of PMSUB below, so a shrunk or emptied
# PMSUB is caught and named on its own, not just silently under-tested.
PMSUB_FLOOR=" install ci add remove rm uninstall link unlink exec dlx why audit publish pack init create update outdated list ls info view config cache dedupe prune store rebuild version "
R46=0
for sub in $PMSUB_FLOOR; do
  case "$PMSUB" in *" $sub "*) ;; *) R46=1; echo "      verify.sh's pmsub no longer has \"$sub\", which this suite's floor requires";; esac
done
ok "PI-46 F1 — verify.sh's pmsub is still a superset of this suite's own floor list" "[ $R46 -eq 0 ]"
# scripts_named <command> — every package script this command runs: `<pm> run <script>` / `<pm> run-script
# <script>`, and the bare `<pm> <script>` form npm/pnpm/yarn/bun also accept — never a subcommand (checked
# against PMSUB above, base_blockers' own list), a flag, or an argument that follows the script name.
scripts_named(){
  local cmd="$1" toks tok pend="" seg=1
  toks=$(shlex "$cmd") || return 0
  while IFS= read -r tok; do
    [[ -n "$tok" ]] || continue
    case "$tok" in '&&'|'||'|';'|'|'|'&') seg=1; pend=""; continue;; esac
    if [[ $seg -eq 1 ]]; then
      pend=""
      case "$tok" in env|bash|sh|zsh|command|nice|time|xargs) continue;; esac
      seg=0
      case "$tok" in npm|pnpm|yarn|bun) pend=pm;; esac
      continue
    fi
    case "$pend" in
      pm)
        case "$tok" in -*) continue;; run|run-script) pend=pmrun; continue;; esac
        pend=""
        case "$PMSUB" in *" $tok "*) continue;; esac
        printf '%s\n' "$tok";;
      pmrun)
        case "$tok" in -*) continue;; esac
        pend=""
        printf '%s\n' "$tok";;
    esac
  done <<< "$toks"
}
# one expansion for both sandboxes: the producer templates are shell, and these are the variables they read
expand(){ PM=npm QUOTED="'src/new.ts' " PYQUOTED="'tests/test_x.py' " BASE_REF=0123456789ab \
          VITCFG=vitest.config.ts PYCFG=pyproject.toml eval "printf '%s' \"$1\""; }
PRODBLOCK=$(awk '/^# --- command producers/,/^# --- end command producers/' "$SCRIPT")
# the "full" tree has everything any producer can name: scripts, runners, selectors and marker files. The
# scripts are DERIVED from the producers' own commands (never typed here, PI-46 AC1): a producer added later
# that names a script never seen before is declared the moment scripts_named sees it, no edit to this file.
SCRIPTNAMES=""
while IFS= read -r pline; do
  ptpl=$(printf '%s\n' "$pline" | grep -oE 'CMD_[A-Z0-9]+="[^"]+"' | head -1 | sed 's/^CMD_[A-Z0-9]*="//; s/"$//')
  [ -n "$ptpl" ] || continue
  SCRIPTNAMES="$SCRIPTNAMES
$(scripts_named "$(expand "$ptpl")")"
done <<EOF
$(printf '%s\n' "$PRODBLOCK" | grep -E 'CMD_[A-Z0-9]+=("[^"]+"|\$\()')
EOF
FULLSCRIPTS=$(printf '%s\n' "$SCRIPTNAMES" | awk 'NF' | sort -u | python3 -c 'import json,sys
names=[l.strip() for l in sys.stdin if l.strip()]
print(json.dumps({n: "x" for n in names}))')
printf '{"scripts":%s,"jest":{}}\n' "$FULLSCRIPTS" > "$SBX/full/package.json"
for b in vitest jest tsc; do printf '#!/usr/bin/env bash\nexit 0\n' > "$SBX/full/node_modules/.bin/$b"; chmod +x "$SBX/full/node_modules/.bin/$b"; done
printf '#!/usr/bin/env bash\nexit 0\n' > "$SBX/full/bin/go"; chmod +x "$SBX/full/bin/go"
: > "$SBX/full/tests/test_x.py"; : > "$SBX/full/src/new.ts"; : > "$SBX/full/check.sh"
: > "$SBX/full/pytest.py"   # makes `python3 -m pytest` resolvable here without installing anything
for f in go.mod tsconfig.json pyproject.toml vitest.config.ts .pocket-it.json; do : > "$SBX/full/$f"; done
# the "marked" tree is the full one MINUS the package scripts and minus every file a command names: it is
# what isolates "the base cannot declare this script" and "the base does not have that file" from the
# cheaper marker-file rule, which would otherwise be the only rule any of these assertions ever exercised.
mkdir -p "$SBX/marked"; cp -R "$SBX/full/." "$SBX/marked/"
printf '{"scripts":{},"jest":{}}\n' > "$SBX/marked/package.json"
rm -f "$SBX/marked/tests/test_x.py" "$SBX/marked/src/new.ts" "$SBX/marked/check.sh"
# PI-46 AC3 — a green run of the ordinary assertions below is not evidence that `marked` really excludes the
# scripts AC1 now derives: the cp -R above copies `full`'s package.json (with those scripts) before the empty
# one overwrites it, so the subtraction is one edit away from silently breaking. Execute the failure: make
# `marked` declare one of the derived scripts, as an accidental inheritance would, and show base_blockers
# WRONGLY clears the very check it exists to block — then restore it and require the correct, unmutated answer.
MUTSCRIPT=$(printf '%s' "$FULLSCRIPTS" | python3 -c 'import json,sys; print(next(iter(json.load(sys.stdin))))' 2>/dev/null)
R46=1; [ -n "$MUTSCRIPT" ] && R46=0
ok "PI-46 AC1 — at least one script was really derived from a producer command" "[ $R46 -eq 0 ]"
cp "$SBX/marked/package.json" "$SBX/marked/package.json.orig"
python3 -c 'import json,sys
p, s = sys.argv[1], sys.argv[2]
d = json.load(open(p)); d["scripts"][s] = "x"; json.dump(d, open(p, "w"))' "$SBX/marked/package.json" "$MUTSCRIPT"
POISONED=$(cd "$SBX/marked" && PATH="$SBX/marked/bin:$PATH" base_blockers "npm run $MUTSCRIPT" package.json)
mv "$SBX/marked/package.json.orig" "$SBX/marked/package.json"
R46=1; [ -z "$POISONED" ] && R46=0
ok "PI-46 AC3 mutation — marked wrongly declaring a derived script really makes base_blockers clear it (the subtraction is load-bearing, not assumed)" "[ $R46 -eq 0 ]"
CLEAN=$(cd "$SBX/marked" && PATH="$SBX/marked/bin:$PATH" base_blockers "npm run $MUTSCRIPT" package.json)
R46=1; [ -n "$CLEAN" ] && R46=0
ok "PI-46 AC3 — marked, unmutated, still answers 'not declared' for a script AC1's derivation added to full" "[ $R46 -eq 0 ]"
# PI-46 AC2 — the WHOLE CLASS of invocation shapes a producer can emit, not the ones in use today: every
# package manager x every accepted shape (`run`, `run-script`, bare `<pm> <script>`), a flag before and
# after the script name — and, the negative half of the same class, every word on PMSUB_FLOOR (this
# suite's own list, F1 above — never the live PMSUB, or a shrunk PMSUB would shrink this loop's coverage
# along with it), which must never be read as a script whatever manager it follows.
R46=0
for pm in npm pnpm yarn bun; do
  for shape in "run build" "run-script build" "build"; do
    got=$(scripts_named "$pm $shape --flag" | tr '\n' ' ')
    [ "$got" = "build " ] || { R46=1; echo "      scripts_named('$pm $shape --flag') => '$got', want 'build '"; }
    got=$(scripts_named "$pm --flag $shape" | tr '\n' ' ')
    [ "$got" = "build " ] || { R46=1; echo "      scripts_named('$pm --flag $shape') => '$got', want 'build '"; }
  done
done
ok "PI-46 AC2 — every package manager and every accepted run-shape yields the script, never a flag around it" "[ $R46 -eq 0 ]"
R46=0
for sub in $PMSUB_FLOOR; do
  for pm in npm pnpm yarn bun; do
    got=$(scripts_named "$pm $sub" | tr '\n' ' ')
    [ -z "$got" ] || { R46=1; echo "      scripts_named('$pm $sub') => '$got', want nothing (a pm subcommand, never a script)"; }
  done
done
ok "PI-46 AC2 — every package-manager subcommand on the floor is excluded, whatever manager it follows" "[ $R46 -eq 0 ]"
NPROD=0; NLIT=0; NONLIT=0; NONEEDS=""; NOTREFUSED=""; NOTREFUSED2=""; NOTCLEARED=""
while IFS= read -r pline; do
  [ -n "$pline" ] || continue
  NPROD=$((NPROD+1))
  case "$pline" in *'_NEEDS='*) ;; *) NONEEDS="$NONEEDS
      $pline";; esac
  ptpl=$(printf '%s\n' "$pline" | grep -oE 'CMD_[A-Z0-9]+="[^"]+"' | head -1 | sed 's/^CMD_[A-Z0-9]*="//; s/"$//')
  pnds=$(printf '%s\n' "$pline" | grep -oE 'CMD_[A-Z0-9]+_NEEDS="[^"]+"' | head -1 | sed 's/^CMD_[A-Z0-9]*_NEEDS="//; s/"$//')
  if [ -z "$ptpl" ]; then NONLIT=$((NONLIT+1)); continue; fi
  NLIT=$((NLIT+1))
  pcmd=$(expand "$ptpl"); pnee=$(expand "$pnds")
  pres=$(cd "$SBX/empty" && base_blockers "$pcmd" "$pnee")
  [ -z "$pres" ] && NOTREFUSED="$NOTREFUSED
      $pcmd"
  # Teach both sandboxes what THIS producer needs, read off the producer itself — so the two passes below
  # stay meaningful for a producer added after this file was written: its declared marker file is created,
  # and every bare word it invokes that this machine does not have gets a stub that exits 0.
  for pn in $pnee; do
    mkdir -p "$SBX/full/$(dirname "$pn")" "$SBX/marked/$(dirname "$pn")"
    [ -e "$SBX/full/$pn" ]   || : > "$SBX/full/$pn"      # never truncate a marker these sandboxes rely on
    [ -e "$SBX/marked/$pn" ] || : > "$SBX/marked/$pn"
  done
  for ptok in $(printf '%s' "$pcmd" | tr -d "'"); do
    case "$ptok" in -*|*/*) continue;; esac
    command -v "$ptok" >/dev/null 2>&1 && continue
    for pd in "$SBX/full/bin" "$SBX/marked/bin"; do printf '#!/usr/bin/env bash\nexit 0\n' > "$pd/$ptok"; chmod +x "$pd/$ptok"; done
  done
  pres=$(cd "$SBX/full" && PATH="$SBX/full/bin:$PATH" base_blockers "$pcmd" "$pnee")
  [ -n "$pres" ] && NOTCLEARED="$NOTCLEARED
      $pcmd => $pres"
  # does this command name a package script, or a file that exists on the branch? Read off the command
  # itself, never from a list kept here — if it does, the base not having it must stop the attribution.
  pexp=0
  case "$pcmd" in *"npm run "*|*"pnpm run "*|*"yarn run "*|*"bun run "*) pexp=1;; esac
  for ptok in $(printf '%s' "$pcmd" | tr -d "'"); do
    [ -n "$ptok" ] && [ -e "$SBX/branch/$ptok" ] && pexp=1
  done
  if [ $pexp -eq 1 ]; then
    pres=$(cd "$SBX/marked" && PATH="$SBX/marked/bin:$PATH" base_blockers "$pcmd" "$pnee")
    [ -z "$pres" ] && NOTREFUSED2="$NOTREFUSED2
      $pcmd"
  fi
done <<EOF
$(printf '%s\n' "$PRODBLOCK" | grep -E 'CMD_[A-Z0-9]+=("[^"]+"|\$\()')
EOF
R41=0; [ -n "$NONEEDS" ] && { R41=1; echo "      producers with no _NEEDS on their own line:$NONEEDS"; }
ok "PI-41 F1 — every command producer declares, on its own line, the file the base must have too" "[ $R41 -eq 0 ]"
R41=0; [ -n "$NOTREFUSED" ] && { R41=1; echo "      not refused against a base tree that has nothing:$NOTREFUSED"; }
ok "PI-41 F1 — every command producer is refused when the base has none of what the command names" "[ $R41 -eq 0 ]"
R41=0; [ -n "$NOTREFUSED2" ] && { R41=1; echo "      not refused although the base has neither its script nor the file it names:$NOTREFUSED2"; }
ok "PI-41 F1 — every producer that names a script or a file is refused when the base has that one thing missing" "[ $R41 -eq 0 ]"
R41=0; [ -n "$NOTCLEARED" ] && { R41=1; echo "      wrongly refused against a base tree that has everything:$NOTCLEARED"; }
ok "PI-41 F1 — every command producer is cleared when the base does have what the command names" "[ $R41 -eq 0 ]"
R41=1; [ "$NPROD" -ge 7 ] && R41=0
ok "PI-41 F1 — the case list really was regenerated from the producer block (7 producers or more)" "[ $R41 -eq 0 ]"
# PI-46 F3 — the bash/grep selector above (CMD_[A-Z0-9]+=) and the sandbox's own producer loop must see the
# SAME producers a genuinely different extraction finds: a future producer name outside that character
# class (an underscore, say) would otherwise drop out of NPROD silently, the suite staying green about
# producers it never saw. Independent of the bash/grep selector: python's own regex, over \w+ (letters,
# digits AND underscore), excluding _NEEDS lines and empty initializers by name/content, not by a
# character-class boundary — so a narrowing in one does not also narrow the other the same way.
GROUND_TRUTH=$(python3 -c 'import re,sys
text = sys.stdin.read()
n = 0
for m in re.finditer(r"CMD_(\w+)=(\"[^\"]*\"|\$\()", text):
    name, val = m.group(1), m.group(2)
    if name.endswith("_NEEDS"): continue
    if val == "\"\"": continue
    n += 1
print(n)' <<< "$PRODBLOCK")
R46=1; [ "$NPROD" -eq "$GROUND_TRUTH" ] && R46=0
ok "PI-46 F3 — the producer selector finds exactly as many producers as an independent count ($NPROD == $GROUND_TRUTH)" "[ $R46 -eq 0 ]"
R41=1; [ "$NONLIT" -eq 1 ] && R41=0
ok "PI-41 F1 — exactly one producer has no literal command (the configured testCommand, covered end to end below)" "[ $R41 -eq 0 ]"
R41=1; [ "$(grep -c 'base_blockers "\${FAIL_CMD\[\$i\]}"' "$SCRIPT")" -eq 1 ] && [ "$(grep -c 'bash -c "\${FAIL_CMD\[\$i\]}"' "$SCRIPT")" -eq 1 ] && R41=0
ok "PI-41 F1 — there is exactly one place a check is re-run on the base, and exactly one guard in front of it" "[ $R41 -eq 0 ]"

# --- F1 end to end (a): a configured testCommand naming a package script the base does not declare ----------
# The measured case: the base has no such script, the branch adds it AND a failing test of its own. A package
# manager exits 1 for a missing script, so before this round the branch's own new red came out as the base's.
FA="$S/f1a"; FAO="$S/f1a-origin.git"
q git init -q --bare "$FAO"; q git init -q -b main "$FA"
echo base > "$FA/README.md"
printf '{"name":"f1a","version":"1.0.0","scripts":{}}\n' > "$FA/package.json"
printf '{}\n' > "$FA/package-lock.json"
printf '{"testCommand":"npm run test:ci"}\n' > "$FA/.pocket-it.json"
q git -C "$FA" add -A; q git -C "$FA" commit -qm base
q git -C "$FA" remote add origin "$FAO"; q git -C "$FA" push -q -u origin main
q git -C "$FA" checkout -q -b f1a-branch main
printf '{"name":"f1a","version":"1.0.0","scripts":{"test:ci":"bash ./t.sh"}}\n' > "$FA/package.json"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FA/t.sh"; chmod +x "$FA/t.sh"
mkdir -p "$FA/bin"; echo content > "$FA/bin/f1a.test.sh"
q git -C "$FA" add -A; q git -C "$FA" commit -qm f1a; q git -C "$FA" push -q -u origin f1a-branch
q git -C "$FA" checkout -q main
OUTP=$(cd "$FA" && bash "$SCRIPT" f1a-branch main 2>&1); RCP=$?
R41=1; hasl "$OUTP" "FAIL  affected tests" && R41=0
ok "PI-41 F1a — the branch's own new test really does fail (the fixture is not vacuous)" "[ $R41 -eq 0 ]"
R41=1; [ "$RCP" -eq 1 ] && R41=0
ok "PI-41 F1a — a script the base never declared is the branch's own red, exit 1, never 3" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" 'attribution unknown: origin/main has no "test:ci" script to re-run' && R41=0
ok "PI-41 F1a — the configured testCommand is guarded by the same script rule as any other command" "[ $R41 -eq 0 ]"
R41=0; hasl "$OUTP" "also fails at" && R41=1
ok "PI-41 F1a — nothing claims the base fails too" "[ $R41 -eq 0 ]"

# --- F1 end to end (b): a per-file selector, with the runner absent from this environment -------------------
# The measured case: pytest is not installed, `python3 -m pytest` exits 1 (not 127), and the selector names a
# file the base does not have at all. Either reason alone must stop the attribution; the verdict is the same
# whether or not this machine happens to have pytest, which is what the assertions below read.
FB="$S/f1b"; FBO="$S/f1b-origin.git"
q git init -q --bare "$FBO"; q git init -q -b main "$FB"
echo base > "$FB/README.md"; printf '[project]\nname = "f1b"\n' > "$FB/pyproject.toml"
q git -C "$FB" add -A; q git -C "$FB" commit -qm base
q git -C "$FB" remote add origin "$FBO"; q git -C "$FB" push -q -u origin main
q git -C "$FB" checkout -q -b f1b-branch main
mkdir -p "$FB/tests"; printf 'def test_x():\n    assert False\n' > "$FB/tests/test_x.py"
q git -C "$FB" add -A; q git -C "$FB" commit -qm f1b; q git -C "$FB" push -q -u origin f1b-branch
q git -C "$FB" checkout -q main
OUTP=$(cd "$FB" && bash "$SCRIPT" f1b-branch main 2>&1); RCP=$?
R41=1; hasl "$OUTP" "FAIL  affected tests" && R41=0
ok "PI-41 F1b — the selector check really does fail on the branch (the fixture is not vacuous)" "[ $R41 -eq 0 ]"
R41=1; [ "$RCP" -eq 1 ] && R41=0
ok "PI-41 F1b — a selector naming a file the base does not have is the branch's own red, exit 1, never 3" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "warn  affected tests — attribution unknown:" && R41=0
ok "PI-41 F1b — the attribution is reported unknown, with its reason" "[ $R41 -eq 0 ]"
R41=0; hasl "$OUTP" "also fails at" && R41=1
ok "PI-41 F1b — a base where nothing is broken is never said to fail" "[ $R41 -eq 0 ]"

# --- F1 end to end (c): the selector rule on its own, with a runner that resolves and a check that fails ----
# Nothing here is missing except the file the command names: the runner is present on both sides and exits 1
# on both sides. Only the "the base does not have that path" rule can tell these two failures apart.
FC="$S/f1c"; FCO="$S/f1c-origin.git"
q git init -q --bare "$FCO"; q git init -q -b main "$FC"
echo base > "$FC/README.md"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FC/runner.sh"; chmod +x "$FC/runner.sh"
printf '{"testCommand":"bash ./runner.sh tests/new_case.py"}\n' > "$FC/.pocket-it.json"
q git -C "$FC" add -A; q git -C "$FC" commit -qm base
q git -C "$FC" remote add origin "$FCO"; q git -C "$FC" push -q -u origin main
q git -C "$FC" checkout -q -b f1c-branch main
mkdir -p "$FC/tests"; echo content > "$FC/tests/new_case.py"
q git -C "$FC" add -A; q git -C "$FC" commit -qm f1c; q git -C "$FC" push -q -u origin f1c-branch
q git -C "$FC" checkout -q main
OUTP=$(cd "$FC" && bash "$SCRIPT" f1c-branch main 2>&1); RCP=$?
R41=1; [ "$RCP" -eq 1 ] && R41=0
ok "PI-41 F1c — a runner that fails on both sides is still the branch's own red when the base lacks the file" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "attribution unknown: origin/main does not have tests/new_case.py, which this check names" && R41=0
ok "PI-41 F1c — the reason names the path the base does not have" "[ $R41 -eq 0 ]"
R41=0; hasl "$OUTP" "also fails at" && R41=1
ok "PI-41 F1c — an identical exit code on both sides is not read as evidence on its own" "[ $R41 -eq 0 ]"

# --- F1, the wording: this script reports an observation and never a cause ----------------------------------
R41=0; grep -n 'echo "' "$SCRIPT" | grep -q 'cause:' && R41=1
ok "PI-41 F1 — no line verify.sh prints names a cause it never determined" "[ $R41 -eq 0 ]"
R41=0; grep -q 'base-moved' "$SCRIPT" && R41=1
ok "PI-41 F1 — 'base-moved' is gone from verify.sh: it never looked at history" "[ $R41 -eq 0 ]"

# --- F2 — the base is resolved to a commit once, and that same commit is what everything below uses ---------
# Proved by moving origin/main UNDER the run: the branch's own check.sh pushes a fix to main and fetches it,
# then fails. Reading origin/<base> a second time would re-check against that new, green commit and call the
# failure the branch's own (exit 1) — against a base commit the diff never used and the output never named.
FD="$S/f2"; FDO="$S/f2-origin.git"
q git init -q --bare "$FDO"; q git init -q -b main "$FD"
echo base > "$FD/README.md"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FD/check.sh"; chmod +x "$FD/check.sh"
printf '{"testCommand":"bash ./check.sh"}\n' > "$FD/.pocket-it.json"
q git -C "$FD" add -A; q git -C "$FD" commit -qm base
q git -C "$FD" remote add origin "$FDO"; q git -C "$FD" push -q -u origin main
q git -C "$FD" checkout -q -b f2-branch main
cat > "$FD/check.sh" <<SH
#!/usr/bin/env bash
# the base moves while this run is in flight: main is fixed, pushed and fetched, so origin/main read a second
# time would point at a green commit. Then this check fails, exactly as it did before the base moved.
printf '#!/usr/bin/env bash\nexit 0\n' > "$FD/check.sh"
git -C "$FD" add -A >/dev/null 2>&1
git -C "$FD" commit -qm "base fixed mid-run" >/dev/null 2>&1
git -C "$FD" push -q origin main >/dev/null 2>&1
git -C "$FD" fetch -q origin main >/dev/null 2>&1
exit 1
SH
chmod +x "$FD/check.sh"
mkdir -p "$FD/bin"; echo content > "$FD/bin/f2.test.sh"
q git -C "$FD" add -A; q git -C "$FD" commit -qm f2; q git -C "$FD" push -q -u origin f2-branch
q git -C "$FD" checkout -q main
OLDSHA=$(git -C "$FD" rev-parse origin/main)
OUTP=$(cd "$FD" && bash "$SCRIPT" f2-branch main 2>&1); RCP=$?
NEWSHA=$(git -C "$FD" rev-parse origin/main)
R41=1; [ "$OLDSHA" != "$NEWSHA" ] && R41=0
ok "PI-41 F2 — origin/main really did move during the run (the fixture is not vacuous)" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "vs origin/main@${OLDSHA:0:12}" && R41=0
ok "PI-41 F2 — the run names the base commit it is judging against" "[ $R41 -eq 0 ]"
R41=1; [ "$RCP" -eq 3 ] && R41=0
ok "PI-41 F2 — the attribution uses the commit the diff used, not whatever origin/main points at now" "[ $R41 -eq 0 ]"
R41=1; hasl "$OUTP" "also fails at origin/main@${OLDSHA:0:12}" && R41=0
ok "PI-41 F2 — the per-check line names that same commit, so the verdict can be audited afterwards" "[ $R41 -eq 0 ]"
R41=0; hasl "$OUTP" "${NEWSHA:0:12}" && R41=1
ok "PI-41 F2 — the commit the base moved to is never the one the verdict is reported against" "[ $R41 -eq 0 ]"
R41=1; [ "$(grep -c 'rev-parse --verify -q "origin/\$BASE' "$SCRIPT")" -eq 1 ] && R41=0
ok "PI-41 F2 — origin/<base> is resolved in exactly one place in the script" "[ $R41 -eq 0 ]"

# --- PI-41, the caller side — the distinction is worthless if the reviewer still acts on "red = needs work" ---
# ($RVWR was resolved above, from this script's own repo root)
VSTEP=$(awk '/^## Step 3 — Mechanical verification/,/^```bash$/{print} /^It runs lint, type-check/{print}' "$RVWR")
R41=0; grep -qF 'verify.sh $N 2>&1 | tail -40' "$RVWR" && R41=1
ok "PI-41 caller — reviewer.md no longer throws the exit code away in a pipe" "[ $R41 -eq 0 ]"
R41=1; grep -qF 'VRC=$?' "$RVWR" && R41=0
ok "PI-41 caller — reviewer.md captures verify.sh's exit code and prints it" "[ $R41 -eq 0 ]"
R41=1; printf '%s\n' "$VSTEP" | grep -qF 'verify: RED — inherited: every failing check also fails at origin/{base}@{commit}' && R41=0
ok "PI-41 caller — reviewer.md names the inherited verdict verbatim, as the script now prints it" "[ $R41 -eq 0 ]"
R41=0; printf '%s\n' "$VSTEP" | grep -qF 'cause: base-moved' && R41=1
ok "PI-41 caller (F1) — reviewer.md no longer repeats a cause the script never established" "[ $R41 -eq 0 ]"
# F3 — the Step used to forbid re-running the attribution by hand and require a hand check two sentences
# later. One rule now, and the base's own red is routed to the one reader who acts on it.
R41=0; printf '%s\n' "$VSTEP" | grep -qF 'never re-run it by hand to prove it' && R41=1
ok "PI-41 caller (F3) — reviewer.md no longer forbids by hand what it then requires by hand" "[ $R41 -eq 0 ]"
R41=1; printf '%s\n' "$VSTEP" | grep -qF 'do not re-derive the attribution as routine' && printf '%s\n' "$VSTEP" | grep -qF 'run that one area yourself' && R41=0
ok "PI-41 caller (F3) — the routine and the exception are stated as one rule, in one sentence" "[ $R41 -eq 0 ]"
R41=1; printf '%s\n' "$VSTEP" | grep -qF 'ORCHESTRATOR:' && R41=0
ok "PI-41 caller (F3) — reviewer.md names where a base-red goes: the report's ORCHESTRATOR line" "[ $R41 -eq 0 ]"
R41=1; printf '%s\n' "$VSTEP" | grep -qF 'origin/{base}@{commit}' && R41=0
ok "PI-41 caller (F2) — reviewer.md tells the reviewer the verdict names a base commit" "[ $R41 -eq 0 ]"
R41=1; printf '%s\n' "$VSTEP" | grep -qF 'NEEDS WORK immediately' && R41=0
ok "PI-41 caller — reviewer.md still sends an own-diff red straight to NEEDS WORK" "[ $R41 -eq 0 ]"
R41=1; printf '%s\n' "$VSTEP" | grep -qF 'attribution unknown' && R41=0
ok "PI-41 caller — reviewer.md treats an unknown attribution as the PR's own red" "[ $R41 -eq 0 ]"
R41=1; printf '%s\n' "$VSTEP" | grep -qF 'per check, never per assertion' && R41=0
ok "PI-41 caller — reviewer.md states the limit of what a base-red check excuses" "[ $R41 -eq 0 ]"
# the rule lives in more than one file, and a second copy is exactly how it goes stale: no doc may still
# reduce verify.sh to "red = needs work" (tasks/ and docs/reports/ are history, not instructions)
# The paths are matched RELATIVE to the repo root, never absolute: this suite normally runs from an agent
# worktree, whose own absolute path contains /.claude/worktrees/, so an absolute filter would exclude every
# file in the repo and the assertion would pass no matter what any file said (measured: it did).
# Excluded on purpose: tasks/ and docs/reports/ are history, .claude/worktrees/ holds other branches.
# Widened after round 2: one literal phrasing was not the class, and docs/SESSION_HANDOFF* is memory, not
# an instruction — a fact quoting the old wording must not turn this suite red.
STALE=$(cd "$REPO_ROOT" && grep -rniE --include='*.md' 'red = needs work|a red = needs work|red means needs work|red is needs work|any red .{0,20}needs work' . \
  | grep -vE '^\./(tasks|docs/reports|\.claude/worktrees)/' | grep -v '^\./docs/SESSION_HANDOFF')
R41=0; [ -n "$STALE" ] && R41=1
ok "PI-41 caller — no instruction file still reduces a red to 'red = needs work'" "[ $R41 -eq 0 ]"
R41=1; grep -qF 'a red that also fails at the base commit it pinned for the run' "$REPO_ROOT/CLAUDE.md" && R41=0
ok "PI-41 caller — CLAUDE.md's script table states the new exit codes" "[ $R41 -eq 0 ]"
# and the script's own header must document the codes a caller is now expected to read
R41=1; grep -qE '^#   3  RED, inherited' "$SCRIPT" && grep -qE '^#   1  RED, this branch' "$SCRIPT" && R41=0
ok "PI-41 caller — verify.sh documents every exit code it can return" "[ $R41 -eq 0 ]"

# ============ PI-51 — a verdict about code that is not installed is not a verdict ============================
# Same disposable repo as PI-41 ($P, its own origin), for the same reason: these cases move the base tree and
# the shared install under a fixture branch on purpose. The mutation here is of the WORLD, not of the script:
# one byte of the installed react/package.json is the only thing that changes between the red run and the
# green one, so neither can pass by accident — and the pair is run in both directions.
# bin/install-drift.test.sh carries the code-level mutations (the comparison removed, scoped packages ignored).
q git -C "$P" checkout -q main
printf 'node_modules/\n' > "$P/.gitignore"
cat > "$P/package-lock.json" <<'J'
{"name":"pi51","lockfileVersion":3,"packages":{"":{"name":"pi51"},"node_modules/react":{"version":"18.3.1"}}}
J
wcheck "$P/check.sh" "exit 0"
p_commit "pi51: a lockfile on the base"
# the shared checkout's install, stale: the tree every branch worktree borrows when it changed no lockfile
mkdir -p "$P/node_modules/react"
setinst(){ printf '{"name":"react","version":"%s"}\n' "$1" > "$P/node_modules/react/package.json"; }
setinst 18.2.0

q git -C "$P" checkout -q -b pi51-drift main
pfile "$P/bin/pi51.test.sh"
p_commit "pi51-drift"

runp pi51-drift
R51=1; [ "$RCP" -eq 2 ] && R51=0
ok "PI-51 AC3 — a branch worktree on a stale shared install exits 2, could-not-run, never a red of the branch" "[ $R51 -eq 0 ]"
R51=1; hasl "$OUTP" "FAIL  install drift — the installed tree is not the one the lockfile declares" && R51=0
ok "PI-51 AC3 — the stale install is stated as the reason, by name" "[ $R51 -eq 0 ]"
R51=1; hasl "$OUTP" "drift  react — installed 18.2.0, locked 18.3.1" && R51=0
ok "PI-51 AC3 — the package, the installed version and the locked one are all named" "[ $R51 -eq 0 ]"
R51=1; hasl "$OUTP" "install-drift.sh reinstall $P" && R51=0
ok "PI-51 AC3 — the fix names the shared checkout, the one place a reinstall can help" "[ $R51 -eq 0 ]"
R51=1; hasl "$OUTP" "node_modules is borrowed from $P/node_modules" && R51=0
ok "PI-51 AC3 — and says where the tree it measured actually came from" "[ $R51 -eq 0 ]"
R51=1; hasl "$OUTP" "verify: could not run — the installed tree disagrees with the lockfile (nothing was measured)" && R51=0
ok "PI-51 AC3 — the verdict line says nothing was measured" "[ $R51 -eq 0 ]"
R51=0; { hasl "$OUTP" "verify: GREEN" || hasl "$OUTP" "verify: RED"; } && R51=1
ok "PI-51 AC3 — no verdict of any kind is printed on a tree that was not the lockfile's" "[ $R51 -eq 0 ]"
R51=0; [ -s "$CALLLOG" ] && R51=1
ok "PI-51 AC3 — and not one check was executed against it" "[ $R51 -eq 0 ]"

# the world mutated back: the same branch, the same script, one correct version installed
setinst 18.3.1
runp pi51-drift
R51=1; [ "$RCP" -eq 0 ] && R51=0
ok "PI-51 AC4 — with the install matching the lockfile the same branch runs and exits 0" "[ $R51 -eq 0 ]"
R51=1; hasl "$OUTP" "verify: GREEN" && R51=0
ok "PI-51 AC4 — a matching install is verified as before, GREEN" "[ $R51 -eq 0 ]"
R51=1; hasl "$OUTP" "info  install matches the lockfile: 1 compared entries of package-lock.json" && R51=0
ok "PI-51 AC4 — and it says what it compared, so a green is never silent about it" "[ $R51 -eq 0 ]"
R51=1; [ -s "$CALLLOG" ] && R51=0
ok "PI-51 AC4 — the checks really did run this time" "[ $R51 -eq 0 ]"

# AC4, the two trees with nothing to compare: unchanged behaviour, no new failure mode
rm -rf "$P/node_modules"
runp pi51-drift
R51=1; [ "$RCP" -eq 0 ] && hasl "$OUTP" "verify: GREEN" && R51=0
ok "PI-51 AC4 — a lockfile with nothing installed anywhere is not drift, the run is unchanged" "[ $R51 -eq 0 ]"
mkdir -p "$P/node_modules/react"; setinst 18.2.0
q git -C "$P" checkout -q main; q git -C "$P" rm -q package-lock.json
p_commit "pi51: no lockfile at all"
q git -C "$P" checkout -q -b pi51-nolock main
pfile "$P/bin/pi51-nolock.test.sh"
p_commit "pi51-nolock"
runp pi51-nolock
R51=1; [ "$RCP" -eq 0 ] && hasl "$OUTP" "verify: GREEN" && R51=0
ok "PI-51 AC4 — a repository with no lockfile at all is untouched by the guard" "[ $R51 -eq 0 ]"
R51=0; hasl "$OUTP" "install drift" && R51=1
ok "PI-51 AC4 — and the guard says nothing about a project it has nothing to check" "[ $R51 -eq 0 ]"

# --- the other borrowing path: the base worktree the attribution runs its re-checks in (PI-41) ---------------
# The branch changes the lockfile, so verify installs the branch's own tree (a stand-in npm does it here,
# nothing is downloaded) and the branch side is clean; the BASE worktree is the one left borrowing the shared
# checkout's stale install. A base whose dependencies are not its own cannot answer "does this fail here too".
q git -C "$P" checkout -q main
cat > "$P/package-lock.json" <<'J'
{"name":"pi51","lockfileVersion":3,"packages":{"":{"name":"pi51"},"node_modules/react":{"version":"18.3.1"}}}
J
wcheck "$P/check.sh" "exit 1"      # the base is red too: without the stale install this run says "inherited"
p_commit "pi51: base lockfile back, base check red"
setinst 18.2.0                      # shared install stale against the base's lockfile

q git -C "$P" checkout -q -b pi51-baseside main
cat > "$P/package-lock.json" <<'J'
{"name":"pi51","lockfileVersion":3,"packages":{"":{"name":"pi51"},"node_modules/react":{"version":"20.0.0"}}}
J
wcheck "$P/check.sh" "exit 1"
p_commit "pi51-baseside"
PMBIN51="$S/pi51-pmbin"; mkdir -p "$PMBIN51"
printf '#!/usr/bin/env bash\nexit 1\n' > "$PMBIN51/pnpm"; chmod +x "$PMBIN51/pnpm"
cat > "$PMBIN51/npm" <<'SH'
#!/usr/bin/env bash
# stand-in npm: `npm ci` installs, into the current worktree, exactly what that worktree's lockfile declares.
[[ "$1" == ci ]] || exit 9
python3 - <<'PY'
import json, os
p = json.load(open("package-lock.json"))["packages"]["node_modules/react"]["version"]
os.makedirs("node_modules/react", exist_ok=True)
open("node_modules/react/package.json", "w").write('{"name":"react","version":"%s"}\n' % p)
PY
SH
chmod +x "$PMBIN51/npm"

runp pi51-baseside "$PMBIN51"
R51=1; [ "$RCP" -eq 1 ] && R51=0
ok "PI-51 AC3 base — a base tree on a stale shared install falls back to the branch's own red, exit 1" "[ $R51 -eq 0 ]"
R51=1; hasl "$OUTP" "attribution unknown: the installed tree at " && hasl "$OUTP" "disagrees with its lockfile" && R51=0
ok "PI-51 AC3 base — the attribution is refused, and says the base tree was not the lockfile's" "[ $R51 -eq 0 ]"
R51=1; hasl "$OUTP" "react — installed 18.2.0, locked 18.3.1" && R51=0
ok "PI-51 AC3 base — the drifted package is named on the base side too" "[ $R51 -eq 0 ]"
R51=1; hasl "$OUTP" "install-drift.sh reinstall $P" && R51=0
ok "PI-51 AC3 base — and the fix names the shared checkout the base borrowed from" "[ $R51 -eq 0 ]"
R51=0; { hasl "$OUTP" "also fails at" || hasl "$OUTP" "pre-existing"; } && R51=1
ok "PI-51 AC3 base — a re-check run against the wrong code never excuses the branch as inherited" "[ $R51 -eq 0 ]"
R51=1; hasl "$OUTP" "verify: RED" && R51=0
ok "PI-51 AC3 base — the branch's red is still reported, unqualified" "[ $R51 -eq 0 ]"

# the world mutated back, one byte again: the base install matches, the attribution can be performed, and the
# very same run reaches the opposite verdict — so the red above was the stale install and nothing else.
setinst 18.3.1
runp pi51-baseside "$PMBIN51"
R51=1; [ "$RCP" -eq 3 ] && R51=0
ok "PI-51 AC3 base — with the base install matching, the same run attributes normally again (exit 3)" "[ $R51 -eq 0 ]"
R51=1; hasl "$OUTP" "verify: RED — inherited" && R51=0
ok "PI-51 AC3 base — and reports the inherited verdict it could not reach before" "[ $R51 -eq 0 ]"
R51=0; hasl "$OUTP" "attribution unknown" && R51=1
ok "PI-51 AC3 base — nothing is unknown any more" "[ $R51 -eq 0 ]"

# ====== PI-51 round 2, F1 — "could not be compared" is a CLASS, and no member of it ever yields a verdict ==
# The members are read out of the production declaration at run time, never listed here: a comparator added
# to install-drift.sh joins this loop by itself, and a name dropped from it fails the floor assertions first.
# Every member is then asserted against the one invariant the task states — an install this pipeline could
# not compare with its lockfile makes verify refuse the verdict: never GREEN, never exit 0, and not one
# check executed against a tree nobody compared.
NPMLOCK='{"name":"pi51","lockfileVersion":3,"packages":{"":{"name":"pi51"},"node_modules/react":{"version":"18.3.1"}}}'
DECL=$(bash "$REPO_ROOT/bin/install-drift.sh" lockfiles)
DECLPAIRS=$(sed -n 's/^LOCKFILES="\(.*\)"$/\1/p' "$REPO_ROOT/bin/install-drift.sh")
SUPPPM=$(sed -n 's/^SUPPORTED_PM="\(.*\)"$/\1/p' "$REPO_ROOT/bin/install-drift.sh")
# the floor: the class may only ever grow. Without this, a shrunken declaration would make every loop below
# pass by iterating nothing at all.
for fl in package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock bun.lockb bun.lock; do
  R51=1; printf '%s\n' "$DECL" | grep -qx "$fl" && R51=0
  ok "PI-51 N1 — the lockfile names verify.sh uses come from install-drift.sh and still include $fl" "[ $R51 -eq 0 ]"
done
R51=1; [ "$(printf '%s\n' "$DECL" | grep -c .)" -eq "$(printf '%s\n' $DECLPAIRS | grep -c .)" ] && R51=0
ok "PI-51 N1 — the \`lockfiles\` subcommand prints the whole declaration, not a subset of it" "[ $R51 -eq 0 ]"

CLSN=0
cls_case(){ # cls_case <lockfile name> <content> — main carries exactly that lockfile and a green check; the
            # branch changes no lockfile at all, so its worktree borrows the shared checkout's install, which
            # is the situation the guard exists for.
  CLSN=$((CLSN+1)); local lf="$1" body="$2" br="pi51-cls-$CLSN" d
  q git -C "$P" checkout -q main
  for d in $DECL; do rm -f "$P/$d"; done
  printf '%s\n' "$body" > "$P/$lf"
  wcheck "$P/check.sh" "exit 0"
  p_commit "pi51 class: $lf"
  q git -C "$P" checkout -q -b "$br" main
  pfile "$P/bin/$br.test.sh"; p_commit "$br"
  setinst 18.2.0
  CLSBR="$br"
  runp "$br"
}
cls_invariant(){ # the same three assertions for every member of the class
  R51=1; [ "$RCP" -eq 2 ] && R51=0
  ok "PI-51 AC3 — $1: exits 2, could-not-run" "[ $R51 -eq 0 ]"
  R51=0; { hasl "$OUTP" "verify: GREEN" || hasl "$OUTP" "verify: RED"; } && R51=1
  ok "PI-51 AC3 — $1: no verdict of any kind is printed" "[ $R51 -eq 0 ]"
  R51=0; [ -s "$CALLLOG" ] && R51=1
  ok "PI-51 AC3 — $1: not one check was run against the tree nobody compared" "[ $R51 -eq 0 ]"
}
for item in $DECLPAIRS; do
  lf="${item%%:*}"; pm="${item#*:}"
  cls_case "$lf" "$NPMLOCK"
  case " $SUPPPM " in
    *" $pm "*)   # the readable half of the class: compared, and the comparison says the tree is not the lockfile's
      cls_invariant "$lf, read and disagreeing with the install"
      R51=1; hasl "$OUTP" "FAIL  install drift — the installed tree is not the one the lockfile declares" && R51=0
      ok "PI-51 AC3 — $lf: the disagreement is stated by name" "[ $R51 -eq 0 ]" ;;
    *)           # the unreadable half: no comparison happened at all, which is no better evidence
      cls_invariant "$lf ($pm), a lockfile this pipeline cannot read"
      R51=1; hasl "$OUTP" "FAIL  install drift — the installed tree could NOT be compared with the lockfile" && R51=0
      ok "PI-51 AC3 — $lf ($pm): the failure says the tree was never compared" "[ $R51 -eq 0 ]"
      R51=1; hasl "$OUTP" "verify: could not run — the installed tree was never compared with the lockfile" && R51=0
      ok "PI-51 AC3 — $lf ($pm): and the closing line refuses the verdict too" "[ $R51 -eq 0 ]"
      R51=1; hasl "$OUTP" "drift check not supported for $pm" && R51=0
      ok "PI-51 AC3 — $lf ($pm): install-drift.sh's own reason is carried through to the reader" "[ $R51 -eq 0 ]" ;;
  esac
done
# the same class from the other direction: a lockfile of a package manager it CAN read, in a shape it cannot.
# Naming the package manager is not what refuses the verdict — failing to compare is.
cls_case package-lock.json '{ "name":'
cls_invariant "a lockfile that cannot be parsed"
R51=1; hasl "$OUTP" "cannot be parsed" && R51=0
ok "PI-51 AC3 — an unparsable lockfile says so, instead of being read as an empty one" "[ $R51 -eq 0 ]"
R51=1; hasl "$OUTP" "so this branch's checks have to be run by hand until install-drift.sh can compare it" && R51=0
ok "PI-51 AC3 — the refusal tells the reader what to do instead of printing an unrunnable remedy" "[ $R51 -eq 0 ]"
R51=1; hasl "$OUTP" "SUPPORTED_PM" && R51=0
ok "PI-51 AC3 — and names the one declaration that changes when a comparator is added" "[ $R51 -eq 0 ]"
cls_case package-lock.json '[]'
cls_invariant "a lockfile that is not a JSON object"
R51=1; hasl "$OUTP" "is not a JSON object" && R51=0
ok "PI-51 AC3 — a lockfile of the wrong JSON type is named as such" "[ $R51 -eq 0 ]"
cls_case package-lock.json '{"lockfileVersion":9}'
cls_invariant "a lockfile of an unknown shape"
R51=1; hasl "$OUTP" 'declares neither "packages" nor "dependencies"' && R51=0
ok "PI-51 AC3 — a lockfile shape nothing here knows how to read is a refusal, not an empty comparison" "[ $R51 -eq 0 ]"

# AC5 at this end of the chain: what produces the refusals above is one arm of one case, and removing it is
# exactly the code that stood here before this task — install-drift's "no verdict" matched nothing, the run
# fell through, and a verdict was published about a tree nobody had compared. The mutant is the proof that
# the section above is testing that arm and not the mere absence of a check.
MUTD="$S/pi51-mutant"; mkdir -p "$MUTD"
sed 's/^  \*) echo "FAIL  install drift — the installed tree could NOT/  9) echo "FAIL  install drift — the installed tree could NOT/' "$SCRIPT" > "$MUTD/verify.sh"
cp "$REPO_ROOT/bin/install-drift.sh" "$MUTD/install-drift.sh"
R51=1; ! cmp -s "$SCRIPT" "$MUTD/verify.sh" && R51=0
ok "PI-51 AC5 — the mutation really changed the script (a sed that matched nothing would prove nothing)" "[ $R51 -eq 0 ]"
cls_case pnpm-lock.yaml "$NPMLOCK"     # the same world the real script refuses a verdict on, rebuilt
: > "$CALLLOG"
MOUT=$(cd "$P" && bash "$MUTD/verify.sh" "$CLSBR" main 2>&1); MRC=$?
R51=1; [ "$MRC" -eq 0 ] && hasl "$MOUT" "verify: GREEN" && R51=0
ok "PI-51 AC5 — without that arm the same world is declared GREEN on a tree nobody compared" "[ $R51 -eq 0 ]"
R51=1; [ -s "$CALLLOG" ] && R51=0
ok "PI-51 AC5 — and the checks do run against it, which is the damage the arm exists to prevent" "[ $R51 -eq 0 ]"

# --- N1 — the names the borrow decision reads are the same declaration, so a new lockfile is never missed ---
# The control for this loop is the class loop above: there the branch changes NO lockfile, the worktree
# borrows, and the run really does measure the shared checkout's 18.2.0. Here the branch changes one, and the
# borrow must not happen for any name in the declaration.
q git -C "$P" checkout -q main
for d in $DECL; do rm -f "$P/$d"; done
printf '%s\n' "$NPMLOCK" > "$P/package-lock.json"; wcheck "$P/check.sh" "exit 0"
p_commit "pi51 n1: one readable lockfile on the base"
N1N=0
for lf in $DECL; do
  N1N=$((N1N+1)); br="pi51-n1-$N1N"
  q git -C "$P" checkout -q -b "$br" main
  if [[ "$lf" == package-lock.json ]]; then printf '%s\n' "${NPMLOCK/18.3.1/18.4.0}" > "$P/$lf"
  else printf '%s\n' "$NPMLOCK" > "$P/$lf"; fi
  pfile "$P/bin/$br.test.sh"; p_commit "$br"
  setinst 18.2.0
  runp "$br" "$PMBIN51"
  R51=1; hasl "$OUTP" "lockfile changed on branch — installing" && R51=0
  ok "PI-51 N1 — a branch that changes $lf is treated as a lockfile change, not given a borrowed tree" "[ $R51 -eq 0 ]"
  # everything the run says about the BRANCH's own tree, i.e. before the base side is reached at all: the
  # shared checkout's 18.2.0 must not appear in it. (The base side legitimately reports that stale tree here,
  # and refuses to attribute anything to it — which is the section above, not this one.)
  BRSIDE=$(printf '%s\n' "$OUTP" | sed -n "1,/^verify: $br vs /p")
  R51=0; hasl "$BRSIDE" "18.2.0" && R51=1
  ok "PI-51 N1 — $lf: the branch is measured on its own install, not the shared checkout's stale tree" "[ $R51 -eq 0 ]"
done

# --- the base side, the other half of the same class: a base tree never COMPARED is not evidence either -----
# The branch replaces an unreadable lockfile with a readable one, so the branch worktree installs its own
# tree and passes the gate, while the BASE worktree keeps borrowing an install nothing can compare with the
# base's own lockfile. Without the refusal this run would report the branch's red as "already on main".
q git -C "$P" checkout -q main
for d in $DECL; do rm -f "$P/$d"; done
printf 'lockfileVersion: 9\n' > "$P/pnpm-lock.yaml"
wcheck "$P/check.sh" "exit 1"
p_commit "pi51: base on an unreadable lockfile, and red"
setinst 18.3.1
q git -C "$P" checkout -q -b pi51-basenc main
rm -f "$P/pnpm-lock.yaml"; printf '%s\n' "$NPMLOCK" > "$P/package-lock.json"
wcheck "$P/check.sh" "exit 1"
pfile "$P/bin/pi51-basenc.test.sh"; p_commit pi51-basenc
runp pi51-basenc "$PMBIN51"
R51=1; [ "$RCP" -eq 1 ] && R51=0
ok "PI-51 F1 base — an uncomparable base install falls back to the branch's own red, exit 1" "[ $R51 -eq 0 ]"
R51=1; hasl "$OUTP" "attribution unknown: the installed tree at " && hasl "$OUTP" "was never compared with its lockfile" && R51=0
ok "PI-51 F1 base — the attribution is refused, and says the base tree was never compared" "[ $R51 -eq 0 ]"
R51=1; hasl "$OUTP" "drift check not supported for pnpm" && R51=0
ok "PI-51 F1 base — with the reason install-drift.sh gave, carried through" "[ $R51 -eq 0 ]"
R51=0; { hasl "$OUTP" "also fails at" || hasl "$OUTP" "pre-existing"; } && R51=1
ok "PI-51 F1 base — a re-check on a tree nobody compared never excuses the branch as inherited" "[ $R51 -eq 0 ]"
R51=1; hasl "$OUTP" "verify: RED" && R51=0
ok "PI-51 F1 base — the branch's red is still reported, unqualified" "[ $R51 -eq 0 ]"
# the world mutated back: the base gets a lockfile that can be read, and the same run reaches the opposite
# verdict — so the refusal above was the uncomparable install and nothing else.
q git -C "$P" checkout -q main
rm -f "$P/pnpm-lock.yaml"; printf '%s\n' "$NPMLOCK" > "$P/package-lock.json"
p_commit "pi51: the base lockfile is readable again"
setinst 18.3.1
runp pi51-basenc "$PMBIN51"
R51=1; [ "$RCP" -eq 3 ] && R51=0
ok "PI-51 F1 base — with a base install that can be compared, the same run attributes again (exit 3)" "[ $R51 -eq 0 ]"
R51=1; hasl "$OUTP" "verify: RED — inherited" && R51=0
ok "PI-51 F1 base — and reaches the inherited verdict it refused before" "[ $R51 -eq 0 ]"
R51=0; hasl "$OUTP" "attribution unknown" && R51=1
ok "PI-51 F1 base — nothing is unknown any more" "[ $R51 -eq 0 ]"

# ====== PI-51 round 2, F2 — the remedy this script prints is run VERBATIM, from the state that printed it ===
# Not "a reinstall works somewhere": the exact command line verify.sh printed, extracted from its own output,
# executed in the world that produced it — a drifted shared checkout with the verified PR's own worktree
# registered against it. That worktree is the reason the remedy carries --except: it is registered at the
# very moment the line is printed, and a remedy blocked by the situation that produced it is not a remedy.
q git -C "$P" checkout -q main
for d in $DECL; do rm -f "$P/$d"; done
printf '%s\n' "$NPMLOCK" > "$P/package-lock.json"; wcheck "$P/check.sh" "exit 0"
p_commit "pi51 remedy: a readable lockfile and a green check on the base"
setinst 18.2.0
q git -C "$P" checkout -q -b pi51-remedy main
pfile "$P/bin/pi51-remedy.test.sh"; p_commit pi51-remedy
FIXWT="$S/pi51-remedy-wt"
q git -C "$P" worktree add "$FIXWT" pi51-remedy
runp pi51-remedy
R51=1; [ "$RCP" -eq 2 ] && R51=0
ok "PI-51 F2 — the drifted shared install is refused a verdict, as before" "[ $R51 -eq 0 ]"
FIXCMD=$(printf '%s\n' "$OUTP" | sed -n 's/^ *fix: run `\([^`]*\)`.*/\1/p' | head -1)
R51=1; [ -n "$FIXCMD" ] && R51=0
ok "PI-51 F2 — the output carries a remedy command, in backticks, on its own line" "[ $R51 -eq 0 ]"
R51=1; printf '%s' "$FIXCMD" | grep -qF -- "--except pi51-remedy" && R51=0
ok "PI-51 F2 — and it excepts the branch being verified, whose worktree is registered right now" "[ $R51 -eq 0 ]"
FIXOUT=$(cd "$P" && PATH="$PMBIN51:$PATH" bash -c "$FIXCMD" 2>&1); FIXRC=$?
R51=1; [ "$FIXRC" -eq 0 ] && R51=0
ok "PI-51 F2 — run exactly as printed, from the checkout it names, the remedy succeeds" "[ $R51 -eq 0 ]"
R51=0; hasl "$FIXOUT" "DEFERRED" && R51=1
ok "PI-51 F2 — the verified PR's own registered worktree does not hold its own remedy" "[ $R51 -eq 0 ]"
R51=1; hasl "$FIXOUT" "install-drift: running" && R51=0
ok "PI-51 F2 — the install really ran, it was not skipped as unnecessary" "[ $R51 -eq 0 ]"
R51=1; grep -qF '"version":"18.3.1"' "$P/node_modules/react/package.json" && R51=0
ok "PI-51 F2 — and the shared checkout's installed tree is the lockfile's afterwards" "[ $R51 -eq 0 ]"
runp pi51-remedy
R51=1; [ "$RCP" -eq 0 ] && hasl "$OUTP" "verify: GREEN" && R51=0
ok "PI-51 F2 — the very run that refused a verdict now reaches one: the remedy closed the drift" "[ $R51 -eq 0 ]"
q git -C "$P" worktree remove --force "$FIXWT" 2>/dev/null

# the guard cannot be lost by accident: verify.sh refuses to run at all without its checker
NODRIFT="$S/pi51-nodrift"; mkdir -p "$NODRIFT"
cp "$SCRIPT" "$NODRIFT/verify.sh"
OUTP=$(cd "$P" && bash "$NODRIFT/verify.sh" pi51-drift main 2>&1); RCP=$?
R51=1; [ "$RCP" -eq 2 ] && hasl "$OUTP" "install-drift.sh is missing next to verify.sh" && R51=0
ok "PI-51 — a verify.sh without its drift checker refuses to run, instead of skipping the guard" "[ $R51 -eq 0 ]"

R51=1; grep -qF 'install-drift.sh' "$REPO_ROOT/CLAUDE.md" && R51=0
ok "PI-51 — CLAUDE.md's script table lists the new script" "[ $R51 -eq 0 ]"
R51=1; grep -qF 'bash bin/install-drift.test.sh' "$REPO_ROOT/.pocket-it.json" && R51=0
ok "PI-51 — the new suite is in testCommand, so it runs on every branch and not just once" "[ $R51 -eq 0 ]"
# the two closing steps that merge PRs must both reinstall, and must both name the harm they wait for
for SK in .claude/skills/quickfix/SKILL.md .claude/skills/run-wave/SKILL.md; do
  R51=1; grep -qF 'install-drift.sh reinstall' "$REPO_ROOT/$SK" && R51=0
  ok "PI-51 AC1 — $(basename "$(dirname "$SK")") reinstalls the shared checkout after a merge" "[ $R51 -eq 0 ]"
  R51=1; grep -qiF 'running against' "$REPO_ROOT/$SK" && R51=0
  ok "PI-51 AC2 — $(basename "$(dirname "$SK")") states the harm the deferral avoids, not a place" "[ $R51 -eq 0 ]"
  R51=1; grep -qF 'handoff.sh log' "$REPO_ROOT/$SK" && R51=0
  ok "PI-51 AC2 — $(basename "$(dirname "$SK")") leaves the deferred reinstall in the handoff log" "[ $R51 -eq 0 ]"
done

[[ $fail -eq 0 ]] && echo "verify.test.sh: ALL PASS" || echo "verify.test.sh: FAILURES"
exit $fail
