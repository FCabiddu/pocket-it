#!/usr/bin/env bash
# Test cases of reviewer-edit.sh: `bash lite/hooks/reviewer-edit-cases.sh`. Exits with 1 if a case fails.
H=$(dirname "$0")/reviewer-edit.sh
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
R=$tmp/repo; mkdir -p "$R/.claude/worktrees/rev-808/src" "$R/.claude/worktrees/task/foo" "$R/src" "$tmp/scratch"
git init -q "$R"
fail=0
t() {
  local exp=$1 agent=$2 path=$3 rc got
  printf '%s' "$(python3 -c 'import json,sys; print(json.dumps({"agent_type":sys.argv[1] or None,"tool_input":{"file_path":sys.argv[2]},"cwd":sys.argv[3]}))' "$agent" "$path" "$R")" | bash "$H" >/dev/null 2>&1; rc=$?
  got=$([ $rc -eq 2 ] && echo BLOCK || echo ok)
  if [ "$got" = "$exp" ]; then r=PASS; else r=FAIL; fail=1; fi
  printf '%s  expected %-5s got %-5s  %-10s %s\n' "$r" "$exp" "$got" "${agent:-main}" "$path"
}
t ok    reviewer  "$R/.claude/worktrees/rev-808/src/a.tsx"
t ok    reviewer  ".claude/worktrees/rev-808/src/a.tsx"
t BLOCK reviewer  "$R/src/a.tsx"
t BLOCK reviewer  "$R/.claude/worktrees/task/foo/a.tsx"
t BLOCK reviewer  "$R/.claude/worktrees/rev-808/../../../src/a.tsx"
t BLOCK reviewer  "$HOME/.claude/agents/lite/.claude/agents/reviewer.md"
t BLOCK developer "$R/src/a.tsx"
t BLOCK developer "$R/README.md"
t BLOCK developer "$R/docs/nuova/cartella/a.md"
t BLOCK task-writer "$R/.claude/worktrees/task/foo/../../../src/a.tsx"
t ok    developer "$R/.claude/worktrees/task/foo/a.tsx"
t ok    analyst   "$R/.claude/worktrees/task/foo/docs/nuovo/a.md"
t ok    developer "$tmp/scratch/a.txt"
t ok    ""        "$R/src/a.tsx"
exit $fail
