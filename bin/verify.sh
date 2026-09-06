#!/usr/bin/env bash
# pocket-it verify — mechanical checks on a PR branch, in a throwaway worktree, summarised in ≤ 40 lines.
# Usage (from the project root): bash ~/.claude/agents/pocket-it/bin/verify.sh <branch-or-PR-number> [base]
# Runs: lint, type-check, affected tests (testCommand from .pocket-it.json, else test:affected, else the
# runner's related selector). Never the full suite, never DB/browser suites. Exit 0 = all green.
set -uo pipefail
TARGET="${1:?branch or PR number}"; BASE="${2:-}"
ROOT=$(git rev-parse --show-toplevel) || { echo "not a git repo"; exit 2; }
cd "$ROOT"
if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  BRANCH=$(gh pr view "$TARGET" --json headRefName --jq .headRefName) || exit 2
  [[ -z "$BASE" ]] && BASE=$(gh pr view "$TARGET" --json baseRefName --jq .baseRefName)
else BRANCH="$TARGET"; fi
[[ -z "$BASE" ]] && BASE=$(python3 -c 'import json;print(json.load(open(".pocket-it.json")).get("baseBranch","main"))' 2>/dev/null || echo main)
git fetch -q origin "$BRANCH" "$BASE" 2>/dev/null
WT="/tmp/pocket-it-verify/$(basename "$ROOT")-${BRANCH//\//-}"
rm -rf "$WT"; mkdir -p "$(dirname "$WT")"
git worktree add -q --detach "$WT" "origin/$BRANCH" 2>/dev/null || git worktree add -q --detach "$WT" "$BRANCH" || { echo "cannot check out $BRANCH"; exit 2; }
cleanup(){ git worktree remove --force "$WT" >/dev/null 2>&1; }
trap cleanup EXIT
cd "$WT"
# reuse the main checkout's node_modules when the lockfile is unchanged
if [[ -d "$ROOT/node_modules" && ! -d node_modules ]]; then
  if git diff --quiet "origin/$BASE" -- pnpm-lock.yaml package-lock.json yarn.lock bun.lockb 2>/dev/null; then ln -s "$ROOT/node_modules" node_modules; else echo "lockfile changed on branch — installing"; (pnpm install --frozen-lockfile >/dev/null 2>&1 || npm ci >/dev/null 2>&1) || echo "install failed"; fi
fi
PM=pnpm; [[ -f package-lock.json ]] && PM=npm; [[ -f yarn.lock ]] && PM=yarn; [[ -f bun.lockb ]] && PM=bun
has(){ python3 -c "import json,sys;print('$1' in json.load(open('package.json')).get('scripts',{}))" 2>/dev/null | grep -q True; }
CHANGED=$(git diff --name-only "origin/$BASE...HEAD" | grep -vE '^(tasks|docs|implementation-plans|tech-analysis|business-analysis|design-specs)/' || true)
TESTCMD=$(python3 -c 'import json;print(json.load(open(".pocket-it.json")).get("testCommand",""))' 2>/dev/null)
[[ -z "$TESTCMD" ]] && has test:affected && TESTCMD="$PM run test:affected --base origin/$BASE"
if [[ -z "$TESTCMD" ]]; then
  if [[ -f vitest.config.ts || -f vitest.config.mts || -f vitest.config.js ]]; then TESTCMD="npx vitest related --run --reporter=dot --silent=passed-only $CHANGED";
  elif grep -q '"jest"' package.json 2>/dev/null; then TESTCMD="npx jest --findRelatedTests --reporters=summary $CHANGED";
  elif [[ -f pyproject.toml || -f pytest.ini ]]; then TESTCMD="python3 -m pytest -q $(echo "$CHANGED" | grep -E '\.py$' | tr '\n' ' ')";
  elif [[ -f go.mod ]]; then TESTCMD="go test ./..."; fi
fi
run(){ # run <label> <cmd>
  local label="$1"; shift; local out rc
  out=$(bash -c "$*" 2>&1); rc=$?
  if [[ $rc -eq 0 ]]; then echo "PASS  $label"; else echo "FAIL  $label (exit $rc)"; echo "$out" | grep -vE '^\s*$' | tail -12 | sed 's/^/      /'; FAILED=1; fi
}
FAILED=0
echo "verify: $BRANCH vs $BASE — $(echo "$CHANGED" | grep -c . ) source files changed"
[[ -n "$CHANGED" ]] && echo "$CHANGED" | head -15 | sed 's/^/  /'
has lint && run "lint" "$PM run lint" || echo "skip  lint (no script)"
if has type-check; then run "type-check" "$PM run type-check"; elif has typecheck; then run "type-check" "$PM run typecheck"; elif [[ -f tsconfig.json ]]; then run "type-check" "npx tsc --noEmit"; else echo "skip  type-check"; fi
if [[ -n "$TESTCMD" && -n "$CHANGED" ]]; then run "affected tests" "$TESTCMD"; else echo "skip  tests (nothing to scope or no runner detected)"; fi
# tests added?
if echo "$CHANGED" | grep -qE '\.(test|spec)\.[cm]?[jt]sx?$|_test\.(py|go)$'; then echo "info  test files in diff: $(echo "$CHANGED" | grep -cE '\.(test|spec)\.|_test\.')"; else echo "warn  no test files in the diff"; fi
[[ $FAILED -eq 0 ]] && { echo "verify: GREEN"; exit 0; } || { echo "verify: RED"; exit 1; }
