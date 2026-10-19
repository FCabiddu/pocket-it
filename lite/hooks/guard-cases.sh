#!/usr/bin/env bash
# Test cases for guard.sh: `bash lite/hooks/guard-cases.sh [guard.sh]`. Exits with 1 if a case fails.
# Works in a temporary repo: the cases' cwd is on branch main, worktree W on task/foo.
G=${1:-$(dirname "$0")/guard.sh}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
R=$tmp/repo W=$tmp/wt
git init -q -b main "$R" && git -C "$R" commit -q --allow-empty -m init && git -C "$R" worktree add -q -b task/foo "$W"
fail=0
t() {
  local exp=$1 cmd=$2 json rc got
  json=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$cmd" "$R")
  printf '%s' "$json" | bash "$G" >/dev/null 2>&1; rc=$?
  got=$([ $rc -eq 2 ] && echo BLOCK || echo ok)
  if [ "$got" = "$exp" ]; then r=PASS; else r=FAIL; fail=1; fi
  printf '%s  expected %-5s got %-5s  %s\n' "$r" "$exp" "$got" "$(printf '%s' "$cmd" | tr '\n' '⏎')"
}
# explicit refspecs
t ok    "git push origin --delete task/foo"
t ok    "git push origin -d task/foo"
t ok    "git push --delete origin task/foo"
t ok    "git push origin :task/foo"
t ok    "git push -u origin task/foo"
t ok    "git push origin task/foo"
t ok    "git push origin HEAD:task/foo"
t ok    "git push origin task/push-fix"
t ok    "git push origin --delete task/push-fix"
t BLOCK "git push origin --delete main"
t BLOCK "git push origin -d main"
t BLOCK "git push origin main"
t BLOCK "git push origin HEAD:main"
t BLOCK 'git push origin "main"'
t BLOCK "git push --force origin task/foo"
t BLOCK "git push -f origin task/foo"
t ok    "git push --force-with-lease origin task/foo"
t ok    "ALLOW_MAIN_PUSH=1 git push origin main"
# without refspec the current branch of the directory it runs in applies
t BLOCK "git push"
t BLOCK "git push origin"
t BLOCK "git push -u origin"
t ok    "cd $W && git push"
t ok    "git -C $W push -u origin"
t BLOCK "cd $W && git -C $R push"
t BLOCK "(cd $W) && git push"
t ok    "(cd $W && git push)"
# «main» or «-f» outside the push do not count
t ok    "git checkout main && rm -f x && git push origin task/foo"
# heredocs and quotes are text, not commands
t ok    "git commit -F - <<EOF
fix: never run git push origin main
EOF"
t ok    "git commit -F - <<'EOF'
git push --force origin task/foo
EOF
git push origin task/foo"
t BLOCK "git commit -F - <<EOF
text
EOF
git push origin main"
t ok    "gh pr create --title t --body \"line one
git push origin main
line three\""
t ok    "gh pr create --body \"\$(cat <<'B'
never git push origin main
B
)\""
t ok    'git commit -m "forbidden: git push -f origin main"'
t ok    "cat <<< 'git push origin main'"
# unclosed quotes: the raw text is split, in doubt it blocks
t BLOCK "echo \"x
git push origin main"
# checkout/restore of a file with uncommitted changes (it would wipe them): blocked
mkdir -p "$R/src" && echo a > "$R/src/clean.ts" && echo b > "$R/src/touched.ts" && git -C "$R" add src && git -C "$R" commit -q -m files && echo mut >> "$R/src/touched.ts"
t BLOCK "git checkout src/touched.ts"
t BLOCK "git checkout -- src/touched.ts"
t BLOCK "git checkout HEAD -- src/touched.ts"
t BLOCK "git restore src/touched.ts"
t BLOCK "git restore --worktree --staged src/touched.ts"
t BLOCK "git -C $R checkout src/touched.ts"
t BLOCK "cd $R && git checkout src/touched.ts; git status"
t ok    "git checkout src/clean.ts"
t ok    "git checkout -- src/clean.ts"
t ok    "git restore --staged src/touched.ts"
t ok    "git checkout -b task/new"
t ok    "git checkout task/foo"
t ok    "git commit -m 'never git checkout src/touched.ts'"
t BLOCK 'F=src/touched.ts; git checkout $F'
t BLOCK 'git checkout "$F"'
t BLOCK 'git restore $F'
t BLOCK 'git checkout -- $F'
t BLOCK 'git checkout src/*.ts'
t BLOCK 'git checkout -- src/*.ts'
t BLOCK 'git checkout `echo src/touched.ts`'
t BLOCK 'git restore src/touche?.ts'
t BLOCK 'git checkout -- src/[t]ouched.ts'
t ok    'git restore --staged $F'
t ok    "git commit -m 'git checkout \$F'"
# clean repo: variables and globs are free
git -C "$R" checkout -q -- src/touched.ts
t ok    'F=src/touched.ts; git checkout $F'
t ok    'git checkout -- src/*.ts'
t ok    'git restore $F'
# 15/10: agents do not run prettier --write by hand (formatting is done by the pre-commit hook)
ta() {
  local exp=$1 cmd=$2 json rc got
  json=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2],"agent_type":"developer"}))' "$cmd" "$W")
  printf '%s' "$json" | bash "$G" >/dev/null 2>&1; rc=$?
  got=$([ $rc -eq 2 ] && echo BLOCK || echo ok)
  if [ "$got" = "$exp" ]; then r=PASS; else r=FAIL; fail=1; fi
  printf '%s  expected %-5s got %-5s  agent %s\n' "$r" "$exp" "$got" "$(printf '%s' "$cmd" | tr '\n' '⏎')"
}
ta BLOCK 'npx prettier --write src/lib/a.ts'
msg=$(python3 -c 'import json; print(json.dumps({"tool_input":{"command":"npx prettier --write src/lib/a.ts"},"cwd":"/tmp","agent_type":"developer"}))' | bash "$G" 2>&1 >/dev/null)
if printf '%s' "$msg" | grep -qF '«npx prettier --write src/lib/a.ts» blocked'; then echo 'PASS  the block message reports the whole command'; else echo "FAIL  the block message reports the whole command: $msg"; fail=1; fi
ta BLOCK 'npx prettier --write src/lib/services/__tests__/'
ta BLOCK 'npx prettier -w "src/**/*.test.ts"'
ta BLOCK 'cd x && ./node_modules/.bin/prettier --log-level warn --write .'
ta BLOCK 'npm run format'
ta BLOCK 'npm run -s format -- src'
ta BLOCK 'pnpm format'
ta ok    'npx prettier --check src/lib/a.ts'
ta ok    'npx prettier -c src/lib/a.ts'
ta ok    'npm run format:check'
ta ok    'git commit -m "no prettier --write by hand"'
ta ok    'cat > /tmp/n.md <<EOF
npx prettier --write .
EOF'
t ok    'npx prettier --write src/lib/a.ts'
exit $fail
