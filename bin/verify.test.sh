#!/usr/bin/env bash
# Self-test for verify.sh — PI-11: the "test files in diff" check must recognise *.test.sh (this repo's own
# test convention, e.g. bin/*.test.sh and .claude/hooks/*.test.sh) alongside the already-supported
# JS/TS/Python/Go patterns, without widening the match to any *.sh file, and without changing the count or
# behaviour for the languages already covered.
cd "$(dirname "$0")"
SCRIPT="$PWD/verify.sh"
S=$(mktemp -d "${TMPDIR:-/tmp}/verify-test.XXXXXX")
S=$(cd "$S" && pwd -P)   # resolve any symlink (e.g. macOS /tmp) so it matches git's resolved toplevel
UNIQ=$(basename "$S")   # per-run id, also used by verify.sh to name its own worktree (basename of $ROOT)
# verify.sh drops its throwaway worktrees under a shared /tmp/pocket-it-verify — only remove the ones this
# run created ($UNIQ-prefixed), never the whole shared directory, so a parallel run isn't wiped out.
cleanup(){ rm -rf "$S" "/tmp/pocket-it-verify/${UNIQ}-"* 2>/dev/null; }
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

# AC2 — a SIGTERM sent once the worktree exists (a slow "affected tests" step gives us the window, via a
# per-branch .pocket-it.json testCommand) leaves no worktree registered and no leftover directory.
q git -C "$M" checkout -q -b pi34-ac2 main
mkdir -p "$M/bin"; echo content > "$M/bin/pi34-ac2.test.sh"
printf '{"testCommand":"sleep 2"}\n' > "$M/.pocket-it.json"
q git -C "$M" add bin/pi34-ac2.test.sh .pocket-it.json
q git -C "$M" commit -qm pi34-ac2
q git -C "$M" push -q -u origin pi34-ac2
q git -C "$M" checkout -q main

(cd "$M" && exec bash "$SCRIPT" pi34-ac2 main) >"$S/pi34-ac2.log" 2>&1 &
KPID=$!
i=0
while (( i < 100 )) && ! git -C "$M" worktree list | grep -q '.claude/worktrees/verify-'; do sleep 0.1; i=$((i+1)); done
kill -TERM "$KPID" 2>/dev/null
j=0
while (( j < 100 )) && kill -0 "$KPID" 2>/dev/null; do sleep 0.1; j=$((j+1)); done
kill -0 "$KPID" 2>/dev/null && kill -KILL "$KPID" 2>/dev/null
wait "$KPID" 2>/dev/null

R3=1; git -C "$M" worktree list | grep -q '.claude/worktrees/verify-' || R3=0
ok "PI-34 AC2 — a SIGTERM mid-run leaves no worktree registered" "[ $R3 -eq 0 ]"
R4=1; [ -z "$(find "$M/.claude/worktrees" -mindepth 1 -maxdepth 1 -name 'verify-*' 2>/dev/null)" ] && R4=0
ok "PI-34 AC2 — no leftover verify-* directory under .claude/worktrees" "[ $R4 -eq 0 ]"

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

[[ $fail -eq 0 ]] && echo "verify.test.sh: ALL PASS" || echo "verify.test.sh: FAILURES"
exit $fail
