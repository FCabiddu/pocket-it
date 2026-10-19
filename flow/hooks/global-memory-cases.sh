#!/usr/bin/env bash
# Test cases for global-memory.sh: `bash flow/hooks/global-memory-cases.sh`. Exits with 1 if a case fails.
H=$(dirname "$0")/global-memory.sh
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P)
export MEMORY_HOME=$tmp/home MEMORY_CLAUDE_DIR=$tmp/home/.claude MEMORY_PROJECTS_DIR=$tmp/home/Desktop
enc() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
G=$MEMORY_CLAUDE_DIR/projects/$(enc "$MEMORY_HOME")/memory
mkdir -p "$G" "$MEMORY_PROJECTS_DIR/app-demo" "$MEMORY_PROJECTS_DIR/agents/pocket-it" "$MEMORY_PROJECTS_DIR/misc/photos"
git init -q "$MEMORY_PROJECTS_DIR/app-demo"
mkdir -p "$MEMORY_CLAUDE_DIR/projects/$(enc "$MEMORY_PROJECTS_DIR/agents/pocket-it")/memory"
P=$MEMORY_CLAUDE_DIR/projects/$(enc "$MEMORY_PROJECTS_DIR/app-demo")/memory
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
t BLOCK Write "$G/tf-costs.md"            $'---\nname: x\nmetadata:\n  type: project\n---\ncosts'
t BLOCK Write "$G/feedback-x.md"          $'---\ntype: feedback\n---\nin the App Demo tests do not change the model'
t BLOCK Write "$G/feedback-x.md"          'on app-demo (guilds) he got angry'
t BLOCK Edit  "$G/feedback-x.md"          'also applies to APP_DEMO'
t BLOCK Write "$G/app-demo-beta.md"   'things to do'
t BLOCK Write "$G/feedback-y.md"          'in the pocket it project the builds'
t BLOCK Edit  "$G/MEMORY.md"              '- [Costs](app-demo-costs.md) — credit'
t ASK   Write "$G/feedback-messages.md"   $'---\ntype: feedback\n---\nshort messages, one yes/no question'
t ASK   Write "$G/feedback-agents.md"     'agents work in worktrees'
t ASK   Write "$G/feedback-photos.md"       'photos and misc: not projects'
t ASK   Write "$G/feedback-z.md"          'appdemolition is not a project'
t ASK   Edit  "$G/feedback-names.md"       'say «E2E tests», not «real run» (real-run.sh)'
t ASK   Bash  ""                          "mv /x/a.md $G/a.md"
t ok    Bash  ""                          "ls $P"
t ok    Bash  ""                          'git status'
t ok    Write "$P/app-demo-costs.md"  $'---\ntype: project\n---\nApp Demo costs'
t ok    Write "$tmp/scratch/note.md"      'app-demo'
exit $fail
