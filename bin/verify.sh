#!/usr/bin/env bash
# pocket-it verify — mechanical checks on a PR branch, in a throwaway worktree, summarised in ≤ 40 lines.
# Usage (from the project root): bash ~/.claude/agents/pocket-it/bin/verify.sh <branch-or-PR-number> [base]
# Runs: lint, type-check, affected tests (testCommand from .pocket-it.json, else test:affected, else the
# runner's related selector). Never the full suite, never DB/browser suites.
#
# Exit codes — the verdict is readable from the code alone, no prose to parse (PI-41):
#   0  GREEN — every check passed.
#   1  RED, this branch's own — at least one failing check passes at the base tip, or its attribution could
#      not be established (an unknown is always reported as this branch's own red).
#   2  verify could not run at all — not a git repo, branch not checked out, guard tripped, or the installed
#      dependency tree disagrees with the lockfile (PI-51: a verdict about code that is not installed is not
#      a verdict at all, so it is refused before any check runs rather than reported as green or red).
#   3  RED, inherited — every failing check also fails at the base tip, and for every one of them the base
#      was positively established as able to run that check.
# 1 is the WORSE of the two reds, not 3: a branch that introduces its own defect is never excused by also
# inheriting one, so a mixed run exits 1. The 0/1/2 paths are byte-for-byte what they were before 3 existed —
# "verify: RED" with exit 1 still means, as it always did, that this branch is the one to fix.
#
# Attribution (PI-41) — twice a reviewer spent a whole needs-work round proving by hand that a red check was
# already red on the base. Only checks that actually FAILED are re-run, once each, in a SECOND throwaway
# worktree at the base tip: a green run never creates it and pays nothing at all for this feature.
# The re-run uses the SAME command string the branch's check used (the branch's notion of the check, run
# against the base's code) so the two sides are comparable.
#
# What this script says, and what it does not (round 2, F1). It reports an OBSERVATION — "the same command
# also fails there" — and never a cause. It does not know whether the base moved, whether it was always red,
# or whether the branch is simply old: it never looked at history. No output line names a cause, because no
# code here determines one; the reviewer, who can read the history, is the one who may.
#   base  = the command was re-run at the base tip and failed there too, AND nothing stood in the way of it
#           running there (see base_blockers). Both halves are required; the second half is the whole point.
#   own   = the command was re-run at the base tip and PASSED there.
#   unknown = anything else, reported as this branch's own red. A check that could not fairly run on the base
#           is never evidence of a defect on the base.
# The one-sidedness is deliberate: charging a branch for the base's red costs a needs-work round, while
# excusing a branch's own red as the base's ships a defect past a reviewer who was told not to re-derive it.
#
# Limits, stated where they cannot be missed rather than implied:
#  * attribution is per CHECK, never per assertion. A check red on both sides is reported as also-red-there
#    even if this branch added a failure of its own to that same check — the "note" line prints on every run
#    that reports one, so nobody reads more into it than it carries.
#  * a chained testCommand (this repo's own is twelve scripts joined by "&&") is ONE check: the chain stops at
#    its first failure, so "per check" there means "the whole suite, up to wherever it stopped".
#  * a flake that happens to go red on the base side lands in exactly that same blind spot.
#  * two sides failing identically because the tooling is missing from THIS ENVIRONMENT cannot be told apart
#    by an exit code alone. That is why a missing runner, module, script, selector or marker file is refused
#    before the base exit code is read, instead of being interpreted after it.
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
# resolved before the first cd, so the sibling script is found however this script was invoked
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TARGET="${1:?branch or PR number}"; BASE="${2:-}"
ROOT=$(git rev-parse --show-toplevel) || { echo "not a git repo"; exit 2; }
cd "$ROOT"
if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  BRANCH=$(gh pr view "$TARGET" --json headRefName --jq .headRefName) || exit 2
  [[ -z "$BASE" ]] && BASE=$(gh pr view "$TARGET" --json baseRefName --jq .baseRefName)
else BRANCH="$TARGET"; fi
[[ -z "$BASE" ]] && BASE=$(python3 -c 'import json;print(json.load(open(".pocket-it.json")).get("baseBranch","main"))' 2>/dev/null || echo main)
git fetch -q origin "$BRANCH" "$BASE" 2>/dev/null
# The base is resolved to a COMMIT, once, here — and everything downstream uses that commit (PI-41 round 2,
# F2). origin/<base> is a moving ref in a repo several agents fetch into: read twice, minutes apart, the diff
# and the attribution can be computed against two different trees, and the verdict would be about a base
# nobody can name afterwards. BASE_SHA is empty only when origin/<base> is not available locally at all; the
# diff then falls back to the ref (best effort, unchanged behaviour) and attribution reports unknown.
BASE_SHA=$(git rev-parse --verify -q "origin/$BASE^{commit}" 2>/dev/null || true)
BASE_REF="${BASE_SHA:-origin/$BASE}"
BASE_AT="origin/$BASE@${BASE_SHA:0:12}"; [[ -n "$BASE_SHA" ]] || BASE_AT="origin/$BASE (unresolved)"
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
  if git diff --quiet "$BASE_REF" -- pnpm-lock.yaml package-lock.json yarn.lock bun.lockb 2>/dev/null; then ln -s "$ROOT/node_modules" node_modules; else echo "lockfile changed on branch — installing"; (pnpm install --frozen-lockfile >/dev/null 2>&1 || npm ci >/dev/null 2>&1) || echo "install failed"; fi
fi
# --- stale install guard (PI-51) ---------------------------------------------------------------------------
# Threat model, at the top of the guard: this protects against a verdict — green or red — about code that is
# not the code the lockfile declares. The borrowed node_modules just above is how that gap opens: the main
# checkout is installed once and nothing reinstalls it when a dependency bump merges, so every later run
# measures the previous versions and stays green about a tree nobody ships. A disagreement is therefore
# refused HERE, before the first check runs, as "could not run" (exit 2) — never reported as a red of the
# branch (it is not the branch's) and never as a green (nothing valid was measured).
# Fail-closed on its own absence: a missing drift check is a broken install of pocket-it, not a clean tree.
# Not covered, deliberately: contents (a package edited in place at the version it declares), and any
# lockfile format the check cannot read — those come back "NOT SUPPORTED" on a warn line and the run goes on,
# because refusing every pnpm/yarn/bun project outright would buy nothing the operator can act on.
DRIFT_SH="$SELF_DIR/install-drift.sh"
[[ -f "$DRIFT_SH" ]] || { echo "verify: could not run — install-drift.sh is missing next to verify.sh, so the installed tree cannot be checked against the lockfile"; exit 2; }
DRIFT_OUT=$(bash "$DRIFT_SH" check . 2>&1); DRIFT_RC=$?
case $DRIFT_RC in
  0) printf '%s\n' "$DRIFT_OUT" | grep -E '^install-drift: OK' | sed 's/^install-drift: OK — /info  install matches the lockfile: /';;
  1) echo "FAIL  install drift — the installed tree is not the one the lockfile declares"
     printf '%s\n' "$DRIFT_OUT" | grep -E '^(drift |install-drift: )' | sed 's/^/      /'
     echo "verify: could not run — the installed tree disagrees with the lockfile (nothing was measured)"; exit 2;;
  *) printf '%s\n' "$DRIFT_OUT" | grep -E '^install-drift: ' | sed 's/^install-drift: /warn  /';;
esac
PM=pnpm; [[ -f package-lock.json ]] && PM=npm; [[ -f yarn.lock ]] && PM=yarn; [[ -f bun.lockb ]] && PM=bun
# --- base-runnability helpers (PI-41 round 2) — verify.test.sh extracts THIS BLOCK verbatim and calls
# the functions in it directly, so what the suite exercises is the production code, not a copy. ------
# has <script> — true when package.json in the CURRENT directory declares that script. Used on the branch to
# pick the checks, and on the base to answer "could this check even exist there?".
has(){ python3 -c 'import json,sys
try: s = json.load(open("package.json")).get("scripts", {})
except Exception: sys.exit(1)
sys.exit(0 if sys.argv[1] in s else 1)' "$1" 2>/dev/null; }
# shlex <command> — the command's words, one per line, with the runner's own quoting rules (the selectors are
# single-quoted paths that may contain spaces or parentheses). Never eval'd: the string is parsed, not run.
shlex(){ python3 - "$1" <<'PY' 2>/dev/null
import shlex, sys
try: print("\n".join(shlex.split(sys.argv[1])))
except Exception: sys.exit(9)
PY
}
# base_blockers <command> <files the base must have too> — run with the base worktree as the current directory.
# Prints the reason this command cannot be re-run FAIRLY here, or nothing at all when it can.
#
# Threat model, at the top of the guard because it is the whole reason it exists: this protects against ONE
# direction — a red belonging to this branch being certified as the base's, in front of a reviewer who is
# told not to re-derive that verdict by hand. It deliberately does not protect against the opposite slip (a
# genuine base red called the branch's own): that outcome is exit 1, today's plain red, which costs a round
# and never excuses a defect. So every rule is one-sided: a doubt produces "unknown", never "base".
# Not covered, deliberately: whether the two failures are the SAME failure (see the per-check note above);
# a tool that is missing from this environment on both sides in a way that still exits like a test failure
# after all four rules below have passed; and the branch and base worktrees' shared node_modules — the main
# checkout's own copy, symlinked into both trees rather than installed fresh in each — so a branch check
# that writes into it (a generated client, a cache, a compiled artifact) changes what the base re-run reads,
# and the base can then answer red for a reason that is not its own. Nothing in an exit code can settle any
# of these three.
# Four rules, in order of cost: (1) the marker file that made this script choose the command must exist here;
# (2) every package script the command names must be declared here — a package manager exits 1 for a missing
# script, indistinguishable from a real failure; (3) the runner must resolve here — an absent module or
# binary exits 1 too, not only 127; (4) every path the command names that exists on the branch must exist
# here — a selector pointing at a file the base does not have tests nothing that belongs to the base.
base_blockers(){
  local cmd="$1" needs="${2:-}" toks tok n seg=1 pend=""
  local pmsub=" install ci add remove rm uninstall link unlink exec dlx why audit publish pack init create update outdated list ls info view config cache dedupe prune store rebuild version "
  for n in $needs; do
    [[ -e "$n" ]] || { printf '%s' "origin/$BASE has no $n, so this is not the same check there"; return 0; }
  done
  toks=$(shlex "$cmd") || { printf '%s' "the command could not be parsed, so a failure of it here proves nothing"; return 0; }
  while IFS= read -r tok; do
    [[ -n "$tok" ]] || continue
    case "$tok" in '&&'|'||'|';'|'|'|'&') seg=1; pend=""; continue;; esac
    if [[ $seg -eq 1 ]]; then
      pend=""
      case "$tok" in env|bash|sh|zsh|command|nice|time|xargs) continue;; esac   # a wrapper: the head is next
      seg=0
      case "$tok" in
        npm|pnpm|yarn|bun) pend=pm;;
        npx|pnpx)          pend=npx;;
        python|python3|python3.*) pend=py;;
      esac
      case "$tok" in
        */*) [[ -e "$tok" ]] || { printf '%s' "origin/$BASE has no $tok to run"; return 0; };;
        *)   command -v "$tok" >/dev/null 2>&1 || { printf '%s' "\"$tok\" does not resolve here, so \"could not run\" and \"already red\" look alike"; return 0; };;
      esac
      continue
    fi
    case "$pend" in
      pm)
        case "$tok" in -*) continue;; run|run-script) pend=pmrun; continue;; esac
        pend=""
        case "$pmsub" in *" $tok "*) continue;; esac
        has "$tok" || { printf '%s' "origin/$BASE has no \"$tok\" script to re-run"; return 0; }
        continue;;
      pmrun)
        case "$tok" in -*) continue;; esac
        pend=""
        has "$tok" || { printf '%s' "origin/$BASE has no \"$tok\" script to re-run"; return 0; }
        continue;;
      npx)
        case "$tok" in -*) continue;; esac
        pend=""
        [[ -x "node_modules/.bin/$tok" ]] || command -v "$tok" >/dev/null 2>&1 \
          || { printf '%s' "origin/$BASE cannot resolve the \"$tok\" runner"; return 0; }
        continue;;
      py)
        if [[ "$tok" == "-m" ]]; then pend=pymod; continue; fi
        case "$tok" in -*) continue;; esac
        pend="";;
      pymod)
        pend=""
        python3 -c 'import importlib.util,sys
try: sys.exit(0 if importlib.util.find_spec(sys.argv[1]) else 1)
except Exception: sys.exit(1)' "$tok" 2>/dev/null \
          || { printf '%s' "the \"$tok\" module is not importable here, so \"could not run\" and \"already red\" look alike"; return 0; }
        continue;;
    esac
    case "$tok" in -*|/*) continue;; esac
    case "$tok" in */*|*.*) ;; *) continue;; esac
    [[ -n "${WT_REAL:-}" && -e "$WT_REAL/$tok" && ! -e "$tok" ]] \
      && { printf '%s' "origin/$BASE does not have $tok, which this check names"; return 0; }
  done <<< "$toks"
  return 0
}
# --- end base-runnability helpers ------------------------------------------------------------------
CHANGED=$(git diff --name-only "$BASE_REF...HEAD" | grep -vE '^(tasks|docs|implementation-plans|tech-analysis|business-analysis|design-specs)/' || true)
QUOTED=$(printf "'%s' " $CHANGED)   # paths like src/app/(app)/page.tsx must reach the runner quoted
PYQUOTED=$(printf "'%s' " $(echo "$CHANGED" | grep -E '\.py$'))
# --- command producers (PI-41 round 2, F1) -------------------------------------------------------------------
# EVERY command string this script can run is built between these two markers, and every one of them is
# re-run on the base ONLY through base_blockers below. Each producer line also declares, on the same line,
# CMD_*_NEEDS: the file whose presence made this script pick that command — the base has to have it too, or
# the "same" check is not the same check there (a `go test ./...` in a tree with no go.mod fails for lack of
# a module, not for a defect). verify.test.sh enumerates this block mechanically: a producer added later
# without its _NEEDS, or one that no longer refuses an empty base tree, turns the suite red on its own.
CMD_LINT=""; CMD_LINT_NEEDS=""
has lint && { CMD_LINT="$PM run lint"; CMD_LINT_NEEDS="package.json"; }
CMD_TYPE=""; CMD_TYPE_NEEDS=""
if   has type-check;         then CMD_TYPE="$PM run type-check"; CMD_TYPE_NEEDS="package.json"
elif has typecheck;          then CMD_TYPE="$PM run typecheck";  CMD_TYPE_NEEDS="package.json"
elif [[ -f tsconfig.json ]]; then CMD_TYPE="npx tsc --noEmit";   CMD_TYPE_NEEDS="tsconfig.json"
fi
CMD_TEST=$(python3 -c 'import json;print(json.load(open(".pocket-it.json")).get("testCommand",""))' 2>/dev/null); CMD_TEST_NEEDS=".pocket-it.json"
[[ -z "$CMD_TEST" ]] && has test:affected && { CMD_TEST="$PM run test:affected --base $BASE_REF"; CMD_TEST_NEEDS="package.json"; }
if [[ -z "$CMD_TEST" ]]; then
  VITCFG=$(ls vitest.config.ts vitest.config.mts vitest.config.js 2>/dev/null | head -1)
  PYCFG=$(ls pyproject.toml pytest.ini 2>/dev/null | head -1)
  if   [[ -n "$VITCFG" ]];                       then CMD_TEST="npx vitest related --run --reporter=dot --silent=passed-only $QUOTED"; CMD_TEST_NEEDS="$VITCFG"
  elif grep -q '"jest"' package.json 2>/dev/null; then CMD_TEST="npx jest --findRelatedTests --reporters=summary $QUOTED"; CMD_TEST_NEEDS="package.json"
  elif [[ -n "$PYCFG" ]];                        then CMD_TEST="python3 -m pytest -q $PYQUOTED"; CMD_TEST_NEEDS="$PYCFG"
  elif [[ -f go.mod ]];                          then CMD_TEST="go test ./..."; CMD_TEST_NEEDS="go.mod"
  fi
fi
# --- end command producers -----------------------------------------------------------------------------------
FAILED=0; NFAIL=0
FAIL_LABEL=(); FAIL_CMD=(); FAIL_NEEDS=(); ATTR=(); AREASON=(); BEXIT=()
run(){ # run <label> <cmd> <files the base needs for this check to be the same check>
  guard   # never run a check unless we are still, actually, inside the throwaway worktree
  local label="$1" cmd="$2" needs="${3:-}" out rc
  out=$(bash -c "$cmd" 2>&1); rc=$?
  if [[ $rc -eq 0 ]]; then echo "PASS  $label"; else
    echo "FAIL  $label (exit $rc)"; echo "$out" | grep -vE '^\s*$' | tail -12 | sed 's/^/      /'
    FAILED=1
    FAIL_LABEL[$NFAIL]="$label"; FAIL_CMD[$NFAIL]="$cmd"; FAIL_NEEDS[$NFAIL]="$needs"
    ATTR[$NFAIL]=unknown; AREASON[$NFAIL]="no re-check has run"; BEXIT[$NFAIL]=""
    NFAIL=$((NFAIL+1))
  fi
}
guard
echo "verify: $BRANCH vs $BASE_AT — $(echo "$CHANGED" | grep -c . ) source files changed"
[[ -n "$CHANGED" ]] && echo "$CHANGED" | head -15 | sed 's/^/  /'
[[ -n "$CMD_LINT" ]] && run "lint" "$CMD_LINT" "$CMD_LINT_NEEDS" || echo "skip  lint (no script)"
[[ -n "$CMD_TYPE" ]] && run "type-check" "$CMD_TYPE" "$CMD_TYPE_NEEDS" || echo "skip  type-check"
if [[ -n "$CMD_TEST" && -n "$CHANGED" ]]; then run "affected tests" "$CMD_TEST" "$CMD_TEST_NEEDS"; else echo "skip  tests (nothing to scope or no runner detected)"; fi
# --- who broke it? (PI-41) — nothing below runs at all while NFAIL is 0 ---
ATTR_BASE=0; ATTR_OWN=0; ATTR_UNK=0
unattributable(){ # unattributable <reason> — the re-check never happened: every failing check stays unknown
  local i
  for ((i=0; i<NFAIL; i++)); do ATTR[$i]=unknown; AREASON[$i]="$1"; done
  ATTR_UNK=$NFAIL; ATTR_BASE=0; ATTR_OWN=0; }
if [[ $NFAIL -gt 0 ]]; then
  if [[ -z "$BASE_SHA" ]]; then
    unattributable "origin/$BASE is not available locally (fetch failed?)"
  else
    WT_BASE="$ROOT/.claude/worktrees/verify-base-$$-${BASE//\//-}"
    if ! git -C "$ROOT" worktree add -q --detach "$WT_BASE" "$BASE_SHA" >/dev/null 2>&1; then
      WT_BASE=""; unattributable "a throwaway worktree for origin/$BASE could not be created"
    elif ! cd "$WT_BASE" 2>/dev/null; then
      unattributable "the throwaway worktree for origin/$BASE could not be entered"
    else
      EXPECT_WT=$(pwd -P); guard
      # the base tip's own dependencies: the main checkout's node_modules is the only copy we may borrow, and
      # only when the base worktree has none of its own. No install is ever attempted here — a check that
      # cannot run on the base is refused by base_blockers, never reported as a defect of the base.
      [[ -d "$ROOT/node_modules" && ! -d node_modules ]] && ln -s "$ROOT/node_modules" node_modules 2>/dev/null
      # PI-51, the same stale-install rule on this side: a base tree whose installed dependencies are not its
      # own lockfile's cannot answer "does this check fail here too" — whatever it answers is about other
      # code. That doubt goes to unknown, never to "base", like every other rule in base_blockers. It is
      # reachable although the branch tree passed the same gate: the branch's own lockfile change makes
      # verify install that tree fresh, while the base keeps borrowing the main checkout's stale one.
      BD_OUT=$(bash "$DRIFT_SH" check . 2>&1); BD_RC=$?
      if [[ $BD_RC -eq 1 ]]; then
        unattributable "the installed tree at $BASE_AT disagrees with its lockfile — $(printf '%s\n' "$BD_OUT" | grep -m1 '^drift ' | sed 's/^drift  *//')"
      else
      for ((i=0; i<NFAIL; i++)); do
        BLOCK=$(base_blockers "${FAIL_CMD[$i]}" "${FAIL_NEEDS[$i]}")
        if [[ -n "$BLOCK" ]]; then
          ATTR[$i]=unknown; AREASON[$i]="$BLOCK"; ATTR_UNK=$((ATTR_UNK+1)); continue
        fi
        guard   # same rule as the branch's own checks: nothing runs outside the throwaway worktree
        bash -c "${FAIL_CMD[$i]}" >/dev/null 2>&1; BRC=$?
        BEXIT[$i]=$BRC
        case $BRC in
          0)       ATTR[$i]=own;  ATTR_OWN=$((ATTR_OWN+1));;
          126|127) ATTR[$i]=unknown; AREASON[$i]="the check itself could not run at the base tip (exit $BRC)"; ATTR_UNK=$((ATTR_UNK+1));;
          *)       ATTR[$i]=base; ATTR_BASE=$((ATTR_BASE+1));;
        esac
      done
      fi
      cd "$WT_REAL" || { echo "cannot return to the worktree $WT_REAL"; exit 2; }
      EXPECT_WT="$WT_REAL"; guard
      git -C "$ROOT" worktree remove --force "$WT_BASE" >/dev/null 2>&1 || { rm -rf "$WT_BASE" 2>/dev/null; git -C "$ROOT" worktree prune >/dev/null 2>&1; }
      WT_BASE=""
    fi
  fi
  for ((i=0; i<NFAIL; i++)); do
    case "${ATTR[$i]}" in
      base) echo "base  ${FAIL_LABEL[$i]} — the same command also fails at $BASE_AT (exit ${BEXIT[$i]} there; observed, no cause established)";;
      own)  echo "own   ${FAIL_LABEL[$i]} — passes at $BASE_AT (this branch's own)";;
      *)    echo "warn  ${FAIL_LABEL[$i]} — attribution unknown: ${AREASON[$i]} — reported as this branch's own red";;
    esac
  done
  [[ $ATTR_BASE -gt 0 ]] && echo "note  attribution is per check, not per assertion: a check red on both sides can still hide a failure this branch added to it"
fi
# tests added?
if echo "$CHANGED" | grep -qE '\.(test|spec)\.[cm]?[jt]sx?$|_test\.(py|go)$|\.test\.sh$'; then echo "info  test files in diff: $(echo "$CHANGED" | grep -cE '\.(test|spec)\.|_test\.|\.test\.sh$')"; else echo "warn  no test files in the diff"; fi
guard
[[ $FAILED -eq 0 ]] && { echo "verify: GREEN"; exit 0; }
[[ $ATTR_BASE -eq $NFAIL ]] && { echo "verify: RED — inherited: every failing check also fails at $BASE_AT"; exit 3; }
echo "verify: RED"; exit 1
