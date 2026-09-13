#!/usr/bin/env bash
# pocket-it worktree — creates or reuses an isolated git worktree for an agent, deterministically, from any cwd.
# Usage: bash ~/.claude/agents/pocket-it/bin/worktree.sh <repo-path> <branch> [base]
#        bash ~/.claude/agents/pocket-it/bin/worktree.sh --unlock <repo-path> <branch>
#   Worktree lands at <repo>/.claude/worktrees/<branch-with-slashes-replaced-by-dashes>. A local branch
#   <branch>, if one already exists, is checked out as-is (never reset — an unpushed commit must survive);
#   otherwise, if origin/<branch> exists, a local branch is created tracking it; otherwise a new branch is
#   created off origin/<base> (base defaults to .pocket-it.json's baseBranch, else main) after a git fetch.
#   A second run for the same branch reuses the existing, registered worktree (idempotent). Adds
#   ".claude/worktrees/" to <repo>/.git/info/exclude once, so the directory never shows as untracked in the
#   main checkout.
# Lock: the worktree is created locked (`git worktree add --lock`, atomic: no instant where it exists unlocked),
#   reason "pocket-it: agent worktree for <branch> since <UTC date>". A reused worktree that is not locked is locked
#   again (a resumed agent is back at work). The lock is a second protection, independent of cleanup-merged.sh's
#   judgement on commits: cleanup keeps a locked worktree until a merged PR contains its tip, then releases the lock
#   and removes it — that is the normal end of the lock, whatever way the agent ended (done, blocked, killed). A
#   failed creation leaves no worktree and so no lock. A lock someone else placed (another reason) is never touched.
#   --unlock releases the pocket-it lock of the worktree that has <branch> checked out, for work that is abandoned
#   or merged without a PR: exit 0 when released or already unlocked, 1 when the lock is not pocket-it's, 2 when no
#   worktree has the branch.
# Prints only the absolute worktree path on stdout; every other message is on stderr. Exit 2 on usage error
# (bad repo path, branch name with spaces) — nothing is created.
set -uo pipefail
LOCK_TAG="pocket-it: agent worktree for"
UNLOCK=0; [[ "${1:-}" == --unlock ]] && { UNLOCK=1; shift; }
REPO_ARG="${1:-}"; BRANCH="${2:-}"; BASE="${3:-}"
usage(){ echo "usage: worktree.sh <repo-path> <branch> [base] | worktree.sh --unlock <repo-path> <branch>" >&2; exit 2; }
[[ -z "$REPO_ARG" || -z "$BRANCH" ]] && usage
(( UNLOCK )) && [[ -n "$BASE" ]] && usage
[[ "$BRANCH" == *' '* ]] && { echo "worktree.sh: branch name must not contain spaces: $BRANCH" >&2; exit 2; }
REPO=$(cd "$REPO_ARG" 2>/dev/null && pwd -P) || { echo "worktree.sh: not a directory: $REPO_ARG" >&2; exit 2; }
g(){ git -C "$REPO" "$@"; }
g rev-parse --git-dir >/dev/null 2>&1 || { echo "worktree.sh: not a git repository: $REPO_ARG" >&2; exit 2; }

# lock_of <path> → prints "none", or "locked <reason>" (reason may be empty) for the registered worktree at <path>
lock_of(){ g worktree list --porcelain | awk -v w="worktree $1" '
  /^worktree /{f=($0==w)} f && /^locked( |$)/{r=$0; sub(/^locked ?/,"",r); s="locked " r}
  END{print (s==""?"none":s)}'; }
lock(){ # $1 path → locks it with the pocket-it reason; a failure is reported, the worktree stays usable
  g worktree lock --reason "$LOCK_TAG $BRANCH since $(date -u +%Y-%m-%dT%H:%MZ)" "$1" >/dev/null 2>&1 \
    || echo "worktree.sh: WARNING could not lock $1 — cleanup-merged.sh protects it only by its commit criteria" >&2; }

if (( UNLOCK )); then
  P=$(g worktree list --porcelain | awk -v b="branch refs/heads/$BRANCH" '/^worktree /{p=substr($0,10)} $0==b{print p}')
  [[ -z "$P" ]] && { echo "worktree.sh: no worktree has $BRANCH checked out" >&2; exit 2; }
  L=$(lock_of "$P")
  case "$L" in
    none) echo "worktree.sh: $P is not locked" >&2;;
    "locked $LOCK_TAG "*) g worktree unlock "$P" >/dev/null 2>&1 || { echo "worktree.sh: cannot unlock $P" >&2; exit 2; }
                          echo "worktree.sh: unlocked $P" >&2;;
    *) echo "worktree.sh: $P is locked by someone else (${L#locked }), left locked" >&2; exit 1;;
  esac
  echo "$P"; exit 0
fi

SLUG="${BRANCH//\//-}"
WT="$REPO/.claude/worktrees/$SLUG"
if g worktree list --porcelain | grep -xF "worktree $WT" >/dev/null; then
  echo "worktree.sh: reusing existing worktree for $BRANCH" >&2
  L=$(lock_of "$WT")
  case "$L" in
    none) lock "$WT";;
    "locked $LOCK_TAG "*) ;;
    *) echo "worktree.sh: $WT is locked by someone else (${L#locked }), left as it is" >&2;;
  esac
  echo "$WT"
  exit 0
elif [[ -d "$WT" ]]; then
  echo "worktree.sh: $WT exists but is not a registered git worktree" >&2
  exit 2
fi

[[ -z "$BASE" ]] && BASE=$(python3 -c 'import json;print(json.load(open("'"$REPO"'/.pocket-it.json")).get("baseBranch","main"))' 2>/dev/null || echo main)

EXCLUDE="$REPO/.git/info/exclude"
mkdir -p "$(dirname "$EXCLUDE")"
grep -qxF '.claude/worktrees/' "$EXCLUDE" 2>/dev/null || echo '.claude/worktrees/' >> "$EXCLUDE"

g fetch -q origin >/dev/null 2>&1
mkdir -p "$(dirname "$WT")"
# git >= 2.36 locks atomically at creation; older git gets the lock right after
ATOMIC=0; [[ "$(g worktree add -h 2>&1)" == *--reason* ]] && ATOMIC=1
LOCKARGS=(); (( ATOMIC )) && LOCKARGS=(--lock --reason "$LOCK_TAG $BRANCH since $(date -u +%Y-%m-%dT%H:%MZ)")
if g show-ref --verify --quiet "refs/heads/$BRANCH"; then
  # local branch already exists (e.g. a resumed agent's unpushed WIP) — check it out as-is, never reset it
  g worktree add -q ${LOCKARGS[@]+"${LOCKARGS[@]}"} "$WT" "$BRANCH" >/dev/null 2>&1 \
    || { echo "worktree.sh: cannot check out $BRANCH" >&2; exit 2; }
elif g show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  g worktree add -q ${LOCKARGS[@]+"${LOCKARGS[@]}"} --track -b "$BRANCH" "$WT" "origin/$BRANCH" >/dev/null 2>&1 \
    || { echo "worktree.sh: cannot check out $BRANCH" >&2; exit 2; }
else
  g worktree add -q ${LOCKARGS[@]+"${LOCKARGS[@]}"} -b "$BRANCH" "$WT" "origin/$BASE" >/dev/null 2>&1 \
    || { echo "worktree.sh: cannot create $BRANCH from origin/$BASE" >&2; exit 2; }
fi
(( ATOMIC )) || lock "$WT"
echo "$WT"
