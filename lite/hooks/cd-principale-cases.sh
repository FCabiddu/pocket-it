#!/usr/bin/env bash
# Casi di prova di cd-principale.sh: `bash lite/hooks/cd-principale-cases.sh [cd-principale.sh]`. Esce con 1 se un caso fallisce.
# La cwd dei casi è un repo finto R; i worktree stanno in R/.claude/worktrees/.
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
  printf '%s  atteso %-5s ottenuto %-5s  %-10s %s\n' "$r" "$exp" "$got" "${agent:-principale}" "$(printf '%s' "$cmd" | tr '\n' '⏎')"
}
# sessione principale: un cd nel worktree resta nella shell
t BLOCK "" "cd $W && git status"
t BLOCK "" "cd $W"
t BLOCK "" "cd .claude/worktrees/fix/foo && npx tsc --noEmit"
t BLOCK "" "git status; cd $W"
t BLOCK "" "pushd $W"
t BLOCK "" "cd /repo/.claude/worktrees/rev-1292/e2e"
t BLOCK "" "echo ok && cd \"$W\" && ls"
# 02/10: il cd del principale che ha spostato la cartella di lavoro
t BLOCK "" "cd /Users/x/progetto/.claude/worktrees/fix/e2e-dossier-chiusura-sotto-1024 && sed -n 1,5p e2e/a.ts"
# 15/10: il percorso del worktree in una variabile del comando
t BLOCK "" 'W=/repo/.claude/worktrees/fix/foo; cd $W && git add x'
t BLOCK "" 'export W=/repo/.claude/worktrees/fix/foo && cd "${W}"'
t BLOCK "" 'B=/repo/.claude/worktrees; cd $B/fix/foo'
t BLOCK "" 'cd $NON_DEFINITA_IN_NESSUN_POSTO'
t ok    "" 'W=/repo/.claude/worktrees/fix/foo; git -C $W status'
t ok    "" 'W=/repo/.claude/worktrees/fix/foo; (cd $W && ls)'
t ok    "" 'D=/repo/docs; cd $D'
t ok    "" 'cd $HOME'
t ok    agent 'W=/repo/.claude/worktrees/fix/foo; cd $W && git status' /repo/.claude/worktrees/fix/foo
# sessione principale: modi che non spostano la shell
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
# gli agenti lavorano nel loro worktree
t ok    developer "cd $W && git status"
t ok    reviewer  "cd /repo/.claude/worktrees/rev-1292"
t ok    tester    "pushd $W"
# agenti e git nel checkout principale: servono cartelle vere, perché un cd verso una cartella che non c'è non sposta la shell
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
P=$T/repo PW=$T/repo/.claude/worktrees/fix/foo
mkdir -p "$P/.git" "$PW/e2e"; echo "gitdir: $P/.git/worktrees/foo" > "$PW/.git"
# 05/10: il worktree non c'era più, il ; ha staccato il merge dal cd fallito
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
