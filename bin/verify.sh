#!/usr/bin/env bash
# pocket-it verify — mechanical checks on a PR branch, in a throwaway worktree, summarised in ≤ 40 lines.
# Usage (from the project root): bash ~/.claude/agents/pocket-it/bin/verify.sh <branch-or-PR-number> [base]
# Runs: lint, type-check, affected tests (testCommand from .pocket-it.json, else test:affected, else the
# runner's related selector). Never the full suite, never DB/browser suites. Exit 0 = all green.
set -uo pipefail
# Trap armed as the very first thing after `set` — before TARGET/BASE/ROOT are even read, before `gh pr view`
# or `git fetch` run. round 3 (PI-34): a signal delivered during those earlier phases (fetch was measured: SIGINT
# to the lone PID during `git fetch` gave exit 0 and "verify: GREEN", with lint/type-check/tests then run against
# the main checkout) used to slip through because the trap only existed from the worktree-creation line down —
# every phase before it ran unprotected. WT="" makes cleanup a no-op until a worktree actually exists, so the
# trap can be armed this early without anything to remove yet. INT/TERM/HUP run cleanup and then `exit`
# explicitly with the signal's own code (130/143/129): without that explicit exit, bash does NOT terminate after
# a custom trap for a non-EXIT signal — it resumes the script right where the signal landed. That is exactly how
# a killed run used to keep going: cleanup already `cd`s back to $ROOT, so whatever ran next (lint, type-check,
# the test command, or — before this fix — even the fetch/checkout itself) ran there, against the main checkout,
# and the script still reached its own "verify: GREEN" at the end, exit 0, unconnected to anything it actually
# checked.
WT=""
cleanup(){ [[ -n "$WT" ]] || return 0; cd "${ROOT:-.}" 2>/dev/null || cd / 2>/dev/null
  git worktree remove --force "$WT" >/dev/null 2>&1 || { rm -rf "$WT" 2>/dev/null; git worktree prune >/dev/null 2>&1; }; }
trap cleanup EXIT
on_signal(){ trap - EXIT INT TERM HUP; cleanup; exit "$1"; }
trap 'on_signal 130' INT
trap 'on_signal 143' TERM
trap 'on_signal 129' HUP
TARGET="${1:?branch or PR number}"; BASE="${2:-}"
ROOT=$(git rev-parse --show-toplevel) || { echo "not a git repo"; exit 2; }
cd "$ROOT"
if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  BRANCH=$(gh pr view "$TARGET" --json headRefName --jq .headRefName) || exit 2
  [[ -z "$BASE" ]] && BASE=$(gh pr view "$TARGET" --json baseRefName --jq .baseRefName)
else BRANCH="$TARGET"; fi
[[ -z "$BASE" ]] && BASE=$(python3 -c 'import json;print(json.load(open(".pocket-it.json")).get("baseBranch","main"))' 2>/dev/null || echo main)
git fetch -q origin "$BRANCH" "$BASE" 2>/dev/null
# throwaway worktree, always under <repo>/.claude/worktrees/ — never /tmp (agents there have no write
# permission for it, and cleanup-merged.sh does not know to sweep it).
# the shared .git dir, never the worktree's own — a linked worktree's ".git" is a FILE, not a directory, and
# `mkdir -p` on a path below it fails; --git-common-dir (absolute form on modern git, resolved by hand on
# older) always names the real one, whichever worktree this script is launched from.
GITCOMMON=$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || GITCOMMON=$(cd "$ROOT" && cd "$(git rev-parse --git-common-dir)" && pwd)
EXCLUDE="$GITCOMMON/info/exclude"; mkdir -p "$(dirname "$EXCLUDE")"
grep -qxF '.claude/worktrees/' "$EXCLUDE" 2>/dev/null || echo '.claude/worktrees/' >> "$EXCLUDE"
WT="$ROOT/.claude/worktrees/verify-$$-${BRANCH//\//-}"   # $$ keeps it distinct from any agent's slug (worktree.sh)
mkdir -p "$(dirname "$WT")"
git worktree add -q --detach "$WT" "origin/$BRANCH" 2>/dev/null || git worktree add -q --detach "$WT" "$BRANCH" || { echo "cannot check out $BRANCH"; exit 2; }
cd "$WT" || { echo "cannot enter the worktree $WT"; exit 2; }
WT_REAL=$(pwd -P)
guard(){ [[ "$(pwd -P)" == "$WT_REAL" ]] || { echo "not inside the throwaway worktree — aborting before running anything against the main checkout"; exit 2; }; }
guard
# reuse the main checkout's node_modules when the lockfile is unchanged
if [[ -d "$ROOT/node_modules" && ! -d node_modules ]]; then
  if git diff --quiet "origin/$BASE" -- pnpm-lock.yaml package-lock.json yarn.lock bun.lockb 2>/dev/null; then ln -s "$ROOT/node_modules" node_modules; else echo "lockfile changed on branch — installing"; (pnpm install --frozen-lockfile >/dev/null 2>&1 || npm ci >/dev/null 2>&1) || echo "install failed"; fi
fi
PM=pnpm; [[ -f package-lock.json ]] && PM=npm; [[ -f yarn.lock ]] && PM=yarn; [[ -f bun.lockb ]] && PM=bun
has(){ python3 -c "import json,sys;print('$1' in json.load(open('package.json')).get('scripts',{}))" 2>/dev/null | grep -q True; }
CHANGED=$(git diff --name-only "origin/$BASE...HEAD" | grep -vE '^(tasks|docs|implementation-plans|tech-analysis|business-analysis|design-specs)/' || true)
QUOTED=$(printf "'%s' " $CHANGED)   # paths like src/app/(app)/page.tsx must reach the runner quoted
PYQUOTED=$(printf "'%s' " $(echo "$CHANGED" | grep -E '\.py$'))
TESTCMD=$(python3 -c 'import json;print(json.load(open(".pocket-it.json")).get("testCommand",""))' 2>/dev/null)
[[ -z "$TESTCMD" ]] && has test:affected && TESTCMD="$PM run test:affected --base origin/$BASE"
if [[ -z "$TESTCMD" ]]; then
  if [[ -f vitest.config.ts || -f vitest.config.mts || -f vitest.config.js ]]; then TESTCMD="npx vitest related --run --reporter=dot --silent=passed-only $QUOTED";
  elif grep -q '"jest"' package.json 2>/dev/null; then TESTCMD="npx jest --findRelatedTests --reporters=summary $QUOTED";
  elif [[ -f pyproject.toml || -f pytest.ini ]]; then TESTCMD="python3 -m pytest -q $PYQUOTED";
  elif [[ -f go.mod ]]; then TESTCMD="go test ./..."; fi
fi
run(){ # run <label> <cmd>
  guard   # never run a check unless we are still, actually, inside the throwaway worktree
  local label="$1"; shift; local out rc
  out=$(bash -c "$*" 2>&1); rc=$?
  if [[ $rc -eq 0 ]]; then echo "PASS  $label"; else echo "FAIL  $label (exit $rc)"; echo "$out" | grep -vE '^\s*$' | tail -12 | sed 's/^/      /'; FAILED=1; fi
}
FAILED=0
guard
echo "verify: $BRANCH vs $BASE — $(echo "$CHANGED" | grep -c . ) source files changed"
[[ -n "$CHANGED" ]] && echo "$CHANGED" | head -15 | sed 's/^/  /'
has lint && run "lint" "$PM run lint" || echo "skip  lint (no script)"
if has type-check; then run "type-check" "$PM run type-check"; elif has typecheck; then run "type-check" "$PM run typecheck"; elif [[ -f tsconfig.json ]]; then run "type-check" "npx tsc --noEmit"; else echo "skip  type-check"; fi
if [[ -n "$TESTCMD" && -n "$CHANGED" ]]; then run "affected tests" "$TESTCMD"; else echo "skip  tests (nothing to scope or no runner detected)"; fi
# tests added?
if echo "$CHANGED" | grep -qE '\.(test|spec)\.[cm]?[jt]sx?$|_test\.(py|go)$|\.test\.sh$'; then echo "info  test files in diff: $(echo "$CHANGED" | grep -cE '\.(test|spec)\.|_test\.|\.test\.sh$')"; else echo "warn  no test files in the diff"; fi
guard
[[ $FAILED -eq 0 ]] && { echo "verify: GREEN"; exit 0; } || { echo "verify: RED"; exit 1; }
