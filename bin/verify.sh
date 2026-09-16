#!/usr/bin/env bash
# pocket-it verify — mechanical checks on a PR branch, in a throwaway worktree, summarised in ≤ 40 lines.
# Usage (from the project root): bash ~/.claude/agents/pocket-it/bin/verify.sh <branch-or-PR-number> [base]
# Runs: lint, type-check, affected tests (testCommand from .pocket-it.json, else test:affected, else the
# runner's related selector). Never the full suite, never DB/browser suites.
#
# Exit codes — the verdict is readable from the code alone, no prose to parse (PI-41):
#   0  GREEN — every check passed.
#   1  RED, this branch's own — at least one failing check passes at the tip of origin/<base>, or its
#      attribution could not be established (an unknown is always reported as this branch's own red).
#   2  verify could not run at all — not a git repo, branch not checked out, guard tripped.
#   3  RED, inherited — every failing check already fails at the tip of origin/<base> (cause: base-moved).
# 1 is the WORSE of the two reds, not 3: a branch that introduces its own defect is never excused by also
# inheriting one, so a mixed run exits 1. The 0/1/2 paths are byte-for-byte what they were before 3 existed —
# "verify: RED" with exit 1 still means, as it always did, that this branch is the one to fix.
#
# Attribution (PI-41) — twice a reviewer spent a whole needs-work round proving by hand that a red check was
# already red on the base. Only checks that actually FAILED are re-run, once each, in a SECOND throwaway
# worktree at origin/<base>'s tip: a green run never creates it and pays nothing at all for this feature.
# The re-run uses the SAME command string the branch's check used (the branch's notion of the check, run
# against the base's code) so the two sides are comparable. When that command is a package script, the base
# must declare a script by that name or the attribution is "unknown": a package manager exits 1 for a missing
# script, indistinguishable from a real failure, and a missing script is no evidence of a pre-existing defect.
# "own" means red on this branch's tree and green at the base tip — which includes a branch simply left behind
# by a base that has since been fixed; whether the fix is a rebase or code is the reviewer's call, not this
# script's, and either way the branch as it stands carries the defect.
# Granularity, stated where it cannot be missed: attribution is per CHECK, never per assertion. A check red on
# both sides is reported pre-existing even if this branch also added a failure of its own to that same check —
# the "note" line prints on every run that reports one, so nobody reads more into the word than it carries.
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
# checked. PI-41: the attribution worktree ($WT_BASE) is swept by the same cleanup, from the same traps — one
# more name in the same list, never a second mechanism, and each name is cleared as soon as it is removed so a
# later signal cannot try to remove it twice.
WT=""; WT_BASE=""
cleanup(){ [[ -n "$WT$WT_BASE" ]] || return 0; cd "${ROOT:-.}" 2>/dev/null || cd / 2>/dev/null
  local w
  for w in "$WT" "$WT_BASE"; do
    [[ -n "$w" ]] || continue
    git worktree remove --force "$w" >/dev/null 2>&1 || { rm -rf "$w" 2>/dev/null; git worktree prune >/dev/null 2>&1; }
  done; }
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
# EXPECT_WT names the ONE throwaway worktree we are allowed to be inside right now: the branch's while the
# checks run, the base's while the attribution re-runs them (PI-41). Anything else — including the main
# checkout, and including "no worktree entered yet" — aborts before a single command is executed.
EXPECT_WT="$WT_REAL"
guard(){ [[ -n "$EXPECT_WT" && "$(pwd -P)" == "$EXPECT_WT" ]] || { echo "not inside the throwaway worktree — aborting before running anything against the main checkout"; exit 2; }; }
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
TESTSCRIPT=""   # the package script name behind TESTCMD, when there is one — see the attribution note above
[[ -z "$TESTCMD" ]] && has test:affected && { TESTCMD="$PM run test:affected --base origin/$BASE"; TESTSCRIPT="test:affected"; }
if [[ -z "$TESTCMD" ]]; then
  if [[ -f vitest.config.ts || -f vitest.config.mts || -f vitest.config.js ]]; then TESTCMD="npx vitest related --run --reporter=dot --silent=passed-only $QUOTED";
  elif grep -q '"jest"' package.json 2>/dev/null; then TESTCMD="npx jest --findRelatedTests --reporters=summary $QUOTED";
  elif [[ -f pyproject.toml || -f pytest.ini ]]; then TESTCMD="python3 -m pytest -q $PYQUOTED";
  elif [[ -f go.mod ]]; then TESTCMD="go test ./..."; fi
fi
FAILED=0; NFAIL=0
FAIL_LABEL=(); FAIL_CMD=(); FAIL_SCRIPT=(); ATTR=(); AREASON=()
run(){ # run <label> <cmd> [package-script-name]
  guard   # never run a check unless we are still, actually, inside the throwaway worktree
  local label="$1" cmd="$2" script="${3:-}" out rc
  out=$(bash -c "$cmd" 2>&1); rc=$?
  if [[ $rc -eq 0 ]]; then echo "PASS  $label"; else
    echo "FAIL  $label (exit $rc)"; echo "$out" | grep -vE '^\s*$' | tail -12 | sed 's/^/      /'
    FAILED=1
    FAIL_LABEL[$NFAIL]="$label"; FAIL_CMD[$NFAIL]="$cmd"; FAIL_SCRIPT[$NFAIL]="$script"
    ATTR[$NFAIL]=unknown; AREASON[$NFAIL]="no re-check has run"
    NFAIL=$((NFAIL+1))
  fi
}
guard
echo "verify: $BRANCH vs $BASE — $(echo "$CHANGED" | grep -c . ) source files changed"
[[ -n "$CHANGED" ]] && echo "$CHANGED" | head -15 | sed 's/^/  /'
has lint && run "lint" "$PM run lint" "lint" || echo "skip  lint (no script)"
if has type-check; then run "type-check" "$PM run type-check" "type-check"; elif has typecheck; then run "type-check" "$PM run typecheck" "typecheck"; elif [[ -f tsconfig.json ]]; then run "type-check" "npx tsc --noEmit"; else echo "skip  type-check"; fi
if [[ -n "$TESTCMD" && -n "$CHANGED" ]]; then run "affected tests" "$TESTCMD" "$TESTSCRIPT"; else echo "skip  tests (nothing to scope or no runner detected)"; fi
# --- who broke it? (PI-41) — nothing below runs at all while NFAIL is 0 ---
ATTR_BASE=0; ATTR_OWN=0; ATTR_UNK=0
unattributable(){ # unattributable <reason> — the re-check never happened: every failing check stays unknown
  local i
  for ((i=0; i<NFAIL; i++)); do ATTR[$i]=unknown; AREASON[$i]="$1"; done
  ATTR_UNK=$NFAIL; ATTR_BASE=0; ATTR_OWN=0; }
if [[ $NFAIL -gt 0 ]]; then
  if ! git -C "$ROOT" rev-parse --verify -q "origin/$BASE^{commit}" >/dev/null 2>&1; then
    unattributable "origin/$BASE is not available locally (fetch failed?)"
  else
    WT_BASE="$ROOT/.claude/worktrees/verify-base-$$-${BASE//\//-}"
    if ! git -C "$ROOT" worktree add -q --detach "$WT_BASE" "origin/$BASE" >/dev/null 2>&1; then
      WT_BASE=""; unattributable "a throwaway worktree for origin/$BASE could not be created"
    elif ! cd "$WT_BASE" 2>/dev/null; then
      unattributable "the throwaway worktree for origin/$BASE could not be entered"
    else
      EXPECT_WT=$(pwd -P); guard
      # the base tip's own dependencies: the main checkout's node_modules is the only copy we may borrow, and
      # only when the base worktree has none of its own. No install is ever attempted here — a check that
      # cannot run on the base comes back 126/127 and is reported unknown, never as a pre-existing defect.
      [[ -d "$ROOT/node_modules" && ! -d node_modules ]] && ln -s "$ROOT/node_modules" node_modules 2>/dev/null
      for ((i=0; i<NFAIL; i++)); do
        if [[ -n "${FAIL_SCRIPT[$i]}" ]] && ! has "${FAIL_SCRIPT[$i]}"; then
          ATTR[$i]=unknown; AREASON[$i]="origin/$BASE has no \"${FAIL_SCRIPT[$i]}\" script to re-run"; ATTR_UNK=$((ATTR_UNK+1)); continue
        fi
        guard   # same rule as the branch's own checks: nothing runs outside the throwaway worktree
        bash -c "${FAIL_CMD[$i]}" >/dev/null 2>&1; BRC=$?
        case $BRC in
          0)       ATTR[$i]=own;  ATTR_OWN=$((ATTR_OWN+1));;
          126|127) ATTR[$i]=unknown; AREASON[$i]="the check itself could not run on origin/$BASE (exit $BRC)"; ATTR_UNK=$((ATTR_UNK+1));;
          *)       ATTR[$i]=base; ATTR_BASE=$((ATTR_BASE+1));;
        esac
      done
      cd "$WT_REAL" || { echo "cannot return to the worktree $WT_REAL"; exit 2; }
      EXPECT_WT="$WT_REAL"; guard
      git -C "$ROOT" worktree remove --force "$WT_BASE" >/dev/null 2>&1 || { rm -rf "$WT_BASE" 2>/dev/null; git -C "$ROOT" worktree prune >/dev/null 2>&1; }
      WT_BASE=""
    fi
  fi
  for ((i=0; i<NFAIL; i++)); do
    case "${ATTR[$i]}" in
      base) echo "base  ${FAIL_LABEL[$i]} — already fails at the tip of origin/$BASE (pre-existing, cause: base-moved)";;
      own)  echo "own   ${FAIL_LABEL[$i]} — passes at the tip of origin/$BASE (this branch's own)";;
      *)    echo "warn  ${FAIL_LABEL[$i]} — attribution unknown: ${AREASON[$i]} — reported as this branch's own red";;
    esac
  done
  [[ $ATTR_BASE -gt 0 ]] && echo "note  attribution is per check, not per assertion: a check red on both sides can still hide a failure this branch added to it"
fi
# tests added?
if echo "$CHANGED" | grep -qE '\.(test|spec)\.[cm]?[jt]sx?$|_test\.(py|go)$|\.test\.sh$'; then echo "info  test files in diff: $(echo "$CHANGED" | grep -cE '\.(test|spec)\.|_test\.|\.test\.sh$')"; else echo "warn  no test files in the diff"; fi
guard
[[ $FAILED -eq 0 ]] && { echo "verify: GREEN"; exit 0; }
[[ $ATTR_BASE -eq $NFAIL ]] && { echo "verify: RED — pre-existing on base (cause: base-moved)"; exit 3; }
echo "verify: RED"; exit 1
