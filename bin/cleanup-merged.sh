#!/usr/bin/env bash
# pocket-it cleanup-merged — removes the worktrees and local branches left behind by merged task PRs
# (developer/reviewer worktrees anywhere under <repo>/.claude/worktrees/* — worktree.sh names them after the
# branch slug, older ones used agent-* — or the legacy <parent>/.worktrees/<task>, hundreds of MB each with
# node_modules), so that cleanup is a step of the flow instead of a manual chore. Discovery is by
# `git worktree list`, not by directory name, so any path under .claude/worktrees/ is covered.
# Usage (from any worktree of the project): bash ~/.claude/agents/pocket-it/bin/cleanup-merged.sh [--dry-run] [--all]
#   --dry-run  print what would happen, touch nothing
#   --all      also consider worktrees on epic/*, main, master and fix-* branches (never the main checkout, never the current one)
# A worktree is removed when its branch is merged into origin/main, origin/master or any origin/epic/* (local base
# branches count too), or when its remote branch is gone and `gh` reports a merged PR for it (squash merge).
# Only clean worktrees are removed; dirty and locked ones are reported and kept. Detached-HEAD worktrees under /tmp
# older than 24 h (reviewer scratch, e.g. verify.sh leftovers) are removed too. The corresponding local branch is then
# deleted and `git worktree prune` runs. One line per action, a summary with the freed size at the end.
# Exit 0 always (2 on usage error). Safe to run repeatedly.
set -uo pipefail
DRY=0; ALL=0
for a in "$@"; do case "$a" in --dry-run) DRY=1;; --all) ALL=1;; *) echo "usage: cleanup-merged.sh [--dry-run] [--all]" >&2; exit 2;; esac; done
git rev-parse --git-common-dir >/dev/null 2>&1 || { echo "usage: run cleanup-merged.sh inside a git repository" >&2; exit 2; }

abs(){ (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }
CUR=$(abs "$(git rev-parse --show-toplevel)")

# Parse `git worktree list --porcelain` (bash 3.2 friendly: one "path|sha|branch|flags" string per entry).
entries=(); path=""; sha=""; branch=""; flags=""
flush(){ [[ -n "$path" ]] && entries+=("$path|$sha|$branch|$flags"); path=""; sha=""; branch=""; flags=""; return 0; }
while IFS= read -r line; do
  case "$line" in
    "worktree "*) flush; path="${line#worktree }";;
    "HEAD "*)     sha="${line#HEAD }";;
    "branch "*)   branch="${line#branch refs/heads/}";;
    detached)     flags="$flags detached";;
    locked*)      flags="$flags locked";;
    prunable*)    flags="$flags prunable";;
  esac
done < <(git worktree list --porcelain)
flush
MAIN="${entries[0]%%|*}"   # the first entry is always the main checkout
g(){ git -C "$MAIN" "$@"; }

g remote get-url origin >/dev/null 2>&1 && g fetch --prune -q origin 2>/dev/null

# Base branches a task branch can be merged into: remote first, then the local ones (they may be ahead after a local merge).
BASES=""; for r in refs/remotes/origin/main refs/remotes/origin/master 'refs/remotes/origin/epic/*' refs/heads/main refs/heads/master 'refs/heads/epic/*'; do
  BASES="$BASES $(g for-each-ref --format='%(refname:short)' "$r")"; done
merged_into(){ # $1 sha, $2 own branch → prints the first base that contains the sha
  local b; for b in $BASES; do
    [[ "$b" == "$2" || "$b" == "origin/$2" ]] && continue
    g merge-base --is-ancestor "$1" "$b" 2>/dev/null && { echo "$b"; return 0; }
  done; return 1; }
pr_merged(){ # $1 branch → prints the merged PR number, if gh can tell
  command -v gh >/dev/null 2>&1 || return 1
  local n; n=$(cd "$MAIN" && gh pr list --state merged --head "$1" --json number --jq '.[0].number' 2>/dev/null)
  [[ -n "$n" && "$n" != null ]] && echo "$n"; }
decide(){ # $1 sha, $2 branch → prints the reason to remove, or nothing
  local m n; m=$(merged_into "$1" "$2") && { echo "merged into $m"; return 0; }
  n=$(pr_merged "$2") && { echo "PR #$n merged"; return 0; }   # squash-merged PRs leave no ancestry: ask gh even if the remote branch still exists
  return 1; }
protected(){ case "$1" in epic/*|main|master|fix-*) return 0;; esac; return 1; }
is_scratch(){ case "$1" in /tmp/*|/private/tmp/*) return 0;; esac; return 1; }
older_24h(){ [[ -n "$(find "$1" -maxdepth 0 -mmin +1440 2>/dev/null)" ]]; }
clean(){ [[ -z "$(git -C "$1" status --porcelain 2>/dev/null)" ]]; }
kb(){ du -sk "$1" 2>/dev/null | cut -f1; }

removed=0; deleted=0; kept=0; before=0; after=0
keep(){ echo "kept $1 ($2)"; kept=$((kept+1)); }
drop_branch(){ # $1 branch
  [[ -z "$1" ]] && return 0
  if (( DRY )); then echo "would delete branch $1"; deleted=$((deleted+1)); return 0; fi
  if g branch -D "$1" >/dev/null 2>&1; then echo "deleted branch $1"; deleted=$((deleted+1)); else echo "kept branch $1 (delete failed)"; fi; }
remove(){ # $1 path, $2 reason, $3 branch to delete afterwards ("" for none)
  local p="$1" why="$2" b="$3" k; k=$(kb "$p"); before=$((before+${k:-0}))
  if (( DRY )); then echo "would remove worktree $p ($why)"; removed=$((removed+1)); drop_branch "$b"; return 0; fi
  if g worktree remove --force "$p" >/dev/null 2>&1; then
    echo "removed worktree $p ($why)"; removed=$((removed+1))
    [[ -d "$p" ]] && { k=$(kb "$p"); after=$((after+${k:-0})); }
    drop_branch "$b"
  else keep "$p" "git worktree remove failed"; k=$(kb "$p"); after=$((after+${k:-0})); fi; }

i=0
for e in "${entries[@]}"; do
  i=$((i+1)); (( i == 1 )) && continue
  IFS='|' read -r p sha branch flags <<<"$e"
  [[ "$(abs "$p")" == "$CUR" ]] && { keep "$p" "current worktree"; continue; }
  case " $flags " in *" locked "*) keep "$p" "locked"; continue;; esac
  case " $flags " in *" prunable "*)
    echo "pruned worktree $p (missing on disk)"; removed=$((removed+1)); (( DRY )) || g worktree prune >/dev/null 2>&1
    [[ -n "$branch" ]] && ( protected "$branch" && (( ! ALL )) ) && continue
    [[ -n "$branch" ]] && decide "$sha" "$branch" >/dev/null && drop_branch "$branch"; continue;; esac
  case " $flags " in *" detached "*)
    if is_scratch "$(abs "$p")" && older_24h "$p"; then remove "$p" "detached scratch older than 24 h" ""; else keep "$p" "detached"; fi; continue;; esac
  [[ -z "$branch" ]] && { keep "$p" "no branch"; continue; }
  protected "$branch" && (( ! ALL )) && { keep "$p" "protected branch $branch"; continue; }
  why=$(decide "$sha" "$branch") || { keep "$p" "not merged"; continue; }
  clean "$p" || { keep "$p" "dirty"; continue; }
  remove "$p" "$why" "$branch"
done
(( DRY )) || g worktree prune >/dev/null 2>&1

mb=$(awk -v k=$((before-after)) 'BEGIN{printf "%.1f", k/1024}')
if (( DRY )); then echo "cleanup-merged (dry-run): $removed worktrees would be removed, $deleted branches would be deleted, $kept kept, would free $mb MB"
else echo "cleanup-merged: $removed worktrees removed, $deleted branches deleted, $kept kept, freed $mb MB"; fi
exit 0
