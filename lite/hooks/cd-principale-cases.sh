#!/usr/bin/env bash
# Test cases for cd-principale.sh: `bash lite/hooks/cd-principale-cases.sh [cd-principale.sh]`. Exits with 1 if a case fails.
# The cwd of the cases is a fake repo R; the worktrees live in R/.claude/worktrees/.
H=${1:-$(dirname "$0")/cd-principale.sh}
R=/repo W=/repo/.claude/worktrees/fix/foo
fail=0
t() {
  local exp=$1 agent=$2 cmd=$3 cwd=${4:-$R} json rc got
  json=$(python3 -c '
import json, sys
d = {"tool_input": {"command": sys.argv[1]}, "cwd": sys.argv[2]}
if sys.argv[3]:
    d["agent_type"] = sys.argv[3]
print(json.dumps(d))' "$cmd" "$cwd" "$agent")
  printf '%s' "$json" | bash "$H" >/dev/null 2>&1; rc=$?
  got=$([ $rc -eq 2 ] && echo BLOCK || echo ok)
  if [ "$got" = "$exp" ]; then r=PASS; else r=FAIL; fail=1; fi
  printf '%s  expected %-5s got %-5s  %-10s %s\n' "$r" "$exp" "$got" "${agent:-main}" "$(printf '%s' "$cmd" | tr '\n' '⏎')"
}
# main session: a cd into the worktree stays in the shell
t BLOCK "" "cd $W && git status"
t BLOCK "" "cd $W"
t BLOCK "" "cd .claude/worktrees/fix/foo && npx tsc --noEmit"
t BLOCK "" "git status; cd $W"
t BLOCK "" "pushd $W"
t BLOCK "" "cd /repo/.claude/worktrees/rev-1292/e2e"
t BLOCK "" "echo ok && cd \"$W\" && ls"
# 02/10: the main session's cd that moved the working directory
t BLOCK "" "cd /Users/x/progetto/.claude/worktrees/fix/e2e-dossier-chiusura-sotto-1024 && sed -n 1,5p e2e/a.ts"
# 15/10: the worktree path in a variable of the command
t BLOCK "" 'W=/repo/.claude/worktrees/fix/foo; cd $W && git add x'
t BLOCK "" 'export W=/repo/.claude/worktrees/fix/foo && cd "${W}"'
t BLOCK "" 'B=/repo/.claude/worktrees; cd $B/fix/foo'
t BLOCK "" 'cd $NON_DEFINITA_IN_NESSUN_POSTO'
t ok    "" 'W=/repo/.claude/worktrees/fix/foo; git -C $W status'
t ok    "" 'W=/repo/.claude/worktrees/fix/foo; (cd $W && ls)'
t ok    "" 'D=/repo/docs; cd $D'
t ok    "" 'cd $HOME'
t ok    agent 'W=/repo/.claude/worktrees/fix/foo; cd $W && git status' /repo/.claude/worktrees/fix/foo
# main session: ways that do not move the shell
t ok    "" "git -C $W status"
t ok    "" "(cd $W && npx tsc --noEmit)"
t ok    "" "cd /repo && /agents/bin/merge-pr.sh 1295"
t ok    "" "cd /repo"
t ok    "" "cd"
t ok    "" "ls $W/e2e"
t ok    "" "echo 'cd $W'"
t ok    "" "git commit -m \"cd $W\""
t ok    "" "cat > /tmp/x.sh <<'EOF'
cd $W
EOF"
t ok    "" "cd /repo/.claude/worktrees"
# agents work in their own worktree
t ok    developer "cd $W && git status"
t ok    reviewer  "cd /repo/.claude/worktrees/rev-1292"
t ok    tester    "pushd $W"
# agents and git in the main checkout: real directories are needed, because a cd to a directory that does not exist does not move the shell
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
P=$T/repo PW=$T/repo/.claude/worktrees/fix/foo
mkdir -p "$P/.git" "$PW/e2e"; echo "gitdir: $P/.git/worktrees/foo" > "$PW/.git"
# 05/10: the worktree was gone, the ; detached the merge from the failed cd
t BLOCK tester    "cd $P/.claude/worktrees/test/giro && S=/tmp/x; git fetch -q origin && git merge -q origin/main" "$P"
t BLOCK developer "git merge origin/main" "$P"
t BLOCK developer "git checkout -b fix/x" "$P"
t BLOCK developer "cd $PW/e2e && cd $P && git commit -m x" "$P"
t BLOCK reviewer  "git -C $P reset --hard" "$PW"
t BLOCK developer "(cd $PW && git status); git pull" "$P"
t ok    tester    "cd $PW && S=/tmp/x; git fetch -q origin && git merge -q origin/main" "$P"
t ok    developer "git -C $PW merge origin/main" "$P"
t ok    developer "git merge origin/main" "$PW/e2e"
t ok    developer "git status && git log -3 && git diff && git fetch origin" "$P"
t ok    developer "git commit -m x" "$PW"
t ok    ""        "git merge origin/main" "$P"
t ok    developer "echo 'git merge origin/main'" "$P"
exit $fail
