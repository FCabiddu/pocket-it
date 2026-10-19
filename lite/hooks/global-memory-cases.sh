#!/usr/bin/env bash
# Test cases for global-memory.sh: `bash lite/hooks/global-memory-cases.sh`. Exits with 1 if a case fails.
H=$(dirname "$0")/global-memory.sh
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P)
export MEMORY_HOME=$tmp/home MEMORY_CLAUDE_DIR=$tmp/home/.claude MEMORY_PROGETTI_DIR=$tmp/home/Desktop
enc() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
G=$MEMORY_CLAUDE_DIR/projects/$(enc "$MEMORY_HOME")/memory
mkdir -p "$G" "$MEMORY_PROGETTI_DIR/app-demo" "$MEMORY_PROGETTI_DIR/agents/pocket-it" "$MEMORY_PROGETTI_DIR/varie/foto"
git init -q "$MEMORY_PROGETTI_DIR/app-demo"
mkdir -p "$MEMORY_CLAUDE_DIR/projects/$(enc "$MEMORY_PROGETTI_DIR/agents/pocket-it")/memory"
P=$MEMORY_CLAUDE_DIR/projects/$(enc "$MEMORY_PROGETTI_DIR/app-demo")/memory
fail=0
t() {
  local exp=$1 tool=$2 path=$3 text=$4 rc got
  printf '%s' "$(python3 -c '
import json,sys
k = "content" if sys.argv[1] == "Write" else "new_string"
ti = {"command": sys.argv[3]} if sys.argv[1] == "Bash" else {"file_path": sys.argv[2], k: sys.argv[3]}
print(json.dumps({"tool_name":sys.argv[1],"tool_input":ti,"cwd":"/"}))' "$tool" "$path" "$text")" | bash "$H" 2>/dev/null > "$tmp/out"; rc=$?
  if [ $rc -eq 2 ]; then got=BLOCK; elif grep -q '"permissionDecision": "ask"' "$tmp/out"; then got=ASK; else got=ok; fi
  if [ "$got" = "$exp" ]; then r=PASS; else r=FAIL; fail=1; fi
  printf '%s  expected %-5s got %-5s  %-5s %s | %s\n' "$r" "$exp" "$got" "$tool" "${path#$tmp/}" "$(printf '%s' "$text" | head -c 50 | tr '\n' ' ')"
}
t BLOCK Write "$G/tf-costi.md"            $'---\nname: x\nmetadata:\n  type: project\n---\ncosti'
t BLOCK Write "$G/feedback-x.md"          $'---\ntype: feedback\n---\nnei test di App Demo non cambiare modello'
t BLOCK Write "$G/feedback-x.md"          'su app-demo (gilde) si è arrabbiato'
t BLOCK Edit  "$G/feedback-x.md"          'vale anche per APP_DEMO'
t BLOCK Write "$G/app-demo-beta.md"   'cose da fare'
t BLOCK Write "$G/feedback-y.md"          'nel progetto pocket it le build'
t BLOCK Edit  "$G/MEMORY.md"              '- [Costi](app-demo-costi.md) — credito'
t ASK   Write "$G/feedback-messaggi.md"   $'---\ntype: feedback\n---\nmessaggi corti, una domanda sì/no'
t ASK   Write "$G/feedback-agenti.md"     'gli agenti lavorano nei worktree'
t ASK   Write "$G/feedback-foto.md"       'foto e varie: non sono progetti'
t ASK   Write "$G/feedback-z.md"          'appdemolizione non è un progetto'
t ASK   Edit  "$G/feedback-nomi.md"       'dire «test E2E», non «giro vero» (giro-vero.sh)'
t ASK   Bash  ""                          "mv /x/a.md $G/a.md"
t ok    Bash  ""                          "ls $P"
t ok    Bash  ""                          'git status'
t ok    Write "$P/app-demo-costi.md"  $'---\ntype: project\n---\nApp Demo costi'
t ok    Write "$tmp/scratch/nota.md"      'app-demo'
exit $fail
