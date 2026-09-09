#!/usr/bin/env bash
# pocket-it worktree — creates or reuses an isolated git worktree for an agent, deterministically, from any cwd.
# Usage: bash ~/.claude/agents/pocket-it/bin/worktree.sh <repo-path> <branch> [base]
#   Worktree lands at <repo>/.claude/worktrees/<branch-with-slashes-replaced-by-dashes>. A local branch
#   <branch>, if one already exists, is checked out as-is (never reset — an unpushed commit must survive);
#   otherwise, if origin/<branch> exists, a local branch is created tracking it; otherwise a new branch is
#   created off origin/<base> (base defaults to .pocket-it.json's baseBranch, else main) after a git fetch.
#   A second run for the same branch reuses the existing, registered worktree (idempotent). Adds
#   ".claude/worktrees/" to <repo>/.git/info/exclude once, so the directory never shows as untracked in the
#   main checkout.
# Prints only the absolute worktree path on stdout; every other message is on stderr. Exit 2 on usage error
# (bad repo path, branch name with spaces) — nothing is created.
set -uo pipefail
REPO_ARG="${1:-}"; BRANCH="${2:-}"; BASE="${3:-}"
usage(){ echo "usage: worktree.sh <repo-path> <branch> [base]" >&2; exit 2; }
[[ -z "$REPO_ARG" || -z "$BRANCH" ]] && usage
[[ "$BRANCH" == *' '* ]] && { echo "worktree.sh: branch name must not contain spaces: $BRANCH" >&2; exit 2; }
REPO=$(cd "$REPO_ARG" 2>/dev/null && pwd -P) || { echo "worktree.sh: not a directory: $REPO_ARG" >&2; exit 2; }
g(){ git -C "$REPO" "$@"; }
g rev-parse --git-dir >/dev/null 2>&1 || { echo "worktree.sh: not a git repository: $REPO_ARG" >&2; exit 2; }

SLUG="${BRANCH//\//-}"
WT="$REPO/.claude/worktrees/$SLUG"
if g worktree list --porcelain | grep -qxF "worktree $WT"; then
  echo "worktree.sh: reusing existing worktree for $BRANCH" >&2
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
if g show-ref --verify --quiet "refs/heads/$BRANCH"; then
  # local branch already exists (e.g. a resumed agent's unpushed WIP) — check it out as-is, never reset it
  g worktree add -q "$WT" "$BRANCH" >/dev/null 2>&1 \
    || { echo "worktree.sh: cannot check out $BRANCH" >&2; exit 2; }
elif g show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  g worktree add -q --track -b "$BRANCH" "$WT" "origin/$BRANCH" >/dev/null 2>&1 \
    || { echo "worktree.sh: cannot check out $BRANCH" >&2; exit 2; }
else
  g worktree add -q -b "$BRANCH" "$WT" "origin/$BASE" >/dev/null 2>&1 \
    || { echo "worktree.sh: cannot create $BRANCH from origin/$BASE" >&2; exit 2; }
fi
echo "$WT"
