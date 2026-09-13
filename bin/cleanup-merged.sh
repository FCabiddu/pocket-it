#!/usr/bin/env bash
# pocket-it cleanup-merged — removes the worktrees and local branches left behind by merged task PRs
# (developer/reviewer worktrees anywhere under <repo>/.claude/worktrees/* — worktree.sh names them after the
# branch slug, older ones used agent-* — or the legacy <parent>/.worktrees/<task>, hundreds of MB each with
# node_modules), so that cleanup is a step of the flow instead of a manual chore. Discovery is by
# `git worktree list`, not by directory name, so any path under .claude/worktrees/ is covered.
# Usage (from any worktree of the project): bash ~/.claude/agents/pocket-it/bin/cleanup-merged.sh [--dry-run] [--all]
#   --dry-run  print what would happen, touch nothing
#   --all      also consider worktrees on epic/*, main, master and fix-* branches (never the main checkout, never the current one)
# A worktree is removed when its branch has commits of its own and they are merged: by ancestry into origin/main,
# origin/master or any origin/epic/* (local base branches count too), or by a merged PR whose head contains the branch
# tip, as `gh` reports it (squash merge, remote branch gone or not). Whether the branch has commits of its own is read
# from its own reflog, never from topology against bases that may since have been merged and deleted: a branch whose
# reflog shows no commit made on it since `branch: Created from …` is work not started or not yet committed and is
# kept, and so is a branch whose reflog cannot tell (none, pruned, or inherited through `branch -c`/`-m`). A branch created from its own remote branch (a checkout of work
# already pushed) is removed only on a merged PR.
# Locked worktrees (PI-31) — a second protection, independent of everything above: worktree.sh creates an agent's worktree
# locked ("pocket-it: agent worktree for <branch> since <date>"), and such a worktree is never judged by its reflog or by
# ancestry. It is released and removed only when it is clean and a merged PR's head contains its tip; otherwise it is kept
# and the report line says it is locked, by what, and why it stays. A locked worktree missing on disk has its lock released
# and its entry pruned (its branch is deleted only on that same merged-PR condition). A lock with any other reason was
# placed by someone else and is never released.
# Only clean worktrees are removed; dirty ones (or ones whose `git status` fails) are kept. Detached-HEAD worktrees under /tmp
# older than 24 h (reviewer scratch, e.g. verify.sh leftovers) are removed too. The corresponding local branch is then
# deleted and `git worktree prune` runs. One line per action, a summary with the freed size at the end.
# Exit 0 always (2 on usage error). Safe to run repeatedly.
set -uo pipefail
DRY=0; ALL=0
for a in "$@"; do case "$a" in --dry-run) DRY=1;; --all) ALL=1;; *) echo "usage: cleanup-merged.sh [--dry-run] [--all]" >&2; exit 2;; esac; done
git rev-parse --git-common-dir >/dev/null 2>&1 || { echo "usage: run cleanup-merged.sh inside a git repository" >&2; exit 2; }

abs(){ (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }
CUR=$(abs "$(git rev-parse --show-toplevel)")

# Parse `git worktree list --porcelain` (bash 3.2 friendly: one "path|sha|branch|flags|lock reason" string per entry;
# the lock reason is last, so a "|" inside it stays in it).
entries=(); path=""; sha=""; branch=""; flags=""; lockr=""
flush(){ [[ -n "$path" ]] && entries+=("$path|$sha|$branch|$flags|$lockr"); path=""; sha=""; branch=""; flags=""; lockr=""; return 0; }
while IFS= read -r line; do
  case "$line" in
    "worktree "*) flush; path="${line#worktree }";;
    "HEAD "*)     sha="${line#HEAD }";;
    "branch "*)   branch="${line#branch refs/heads/}";;
    detached)     flags="$flags detached";;
    locked|"locked "*) flags="$flags locked"; lockr="${line#locked}"; lockr="${lockr# }";;
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
is_anc(){ g merge-base --is-ancestor "$1" "$2" 2>/dev/null; }
history(){ # $1 tip sha, $2 branch → reads the branch's reflog oldest first; prints own | fresh <start> | remote <start> | unknown
  local h s start="" seen=0 own=0
  while read -r h s; do
    case "$s" in
      "branch: Created from "*) start="${s#branch: Created from }";;
      # `branch -c` / `branch -m` carry another ref's reflog along: what came before was written on that ref
      "Branch: copied "*|"Branch: renamed "*) start=""; seen=0; own=0;;
      # an entry that made a commit on this branch, still in its history (a reset past it takes it away)
      commit:*|"commit ("*|cherry-pick:*|revert:*|am:*|*": Merge made by "*) seen=1; is_anc "$h" "$1" && own=1;;
      # a rebase rewrites the commits above: it carries them only if there were some to replay
      *" (finish): refs/heads/"*|"rebase finished: "*) (( seen )) && is_anc "$h" "$1" && own=1;;
    esac   # fast-forwards, resets, `branch -f`, update-ref: moves that make no commit of its own
  done < <(g reflog show --format='%H %gs' "refs/heads/$2" -- 2>/dev/null | awk '{l[NR]=$0} END{for(i=NR;i>0;i--) print l[i]}')
  if (( own )); then echo own
  elif [[ -z "$start" ]]; then echo unknown   # no reflog, pruned past the creation, or copied/renamed: cannot tell, so keep
  elif [[ "$start" == "origin/$2" || "$start" == "refs/remotes/origin/$2" ]]; then echo "remote $start"
  else echo "fresh $start"; fi; }
merged_pr(){ # $1 sha, $2 branch → exit 0 printing "PR #n merged" when a merged PR's head contains the tip; else exit 1,
  # printing "commits not in merged PR #n" when merged PRs exist without it, nothing when there is none (or no gh)
  local n oid found=""
  command -v gh >/dev/null 2>&1 || return 1
  while read -r n oid; do
    [[ -z "$n" || "$n" == null ]] && continue
    [[ -n "$oid" ]] && is_anc "$1" "$oid" && { echo "PR #$n merged"; return 0; }
    found="$n"
  done < <(cd "$MAIN" && gh pr list --state merged --head "$2" --json number,headRefOid --jq '.[] | "\(.number) \(.headRefOid)"' 2>/dev/null)
  [[ -n "$found" ]] && echo "commits not in merged PR #$found"
  return 1; }
decide(){ # $1 sha, $2 branch → prints the reason; exit 0 = remove, 1 = keep
  local k m r
  k=$(history "$1" "$2")
  case "$k" in
    unknown) echo "reflog cannot tell whether it has commits of its own"; return 1;;
    fresh*)  echo "no commits of its own (created from ${k#fresh })"; return 1;;
    own)     m=$(merged_into "$1" "$2") && { echo "merged into $m"; return 0; };;
  esac
  # Squash-merged PRs leave no ancestry: ask gh even if the remote branch still exists, and remove only if the PR's
  # head contains the local tip — commits made after the merge are work the PR never carried.
  r=$(merged_pr "$1" "$2") && { echo "$r"; return 0; }
  [[ -n "$r" ]] && { echo "$r"; return 1; }
  [[ "$k" == remote* ]] && { echo "created from ${k#remote }, no merged PR contains it"; return 1; }
  echo "not merged"; return 1; }
protected(){ case "$1" in epic/*|main|master|fix-*) return 0;; esac; return 1; }
is_scratch(){ case "$1" in /tmp/*|/private/tmp/*) return 0;; esac; return 1; }
older_24h(){ [[ -n "$(find "$1" -maxdepth 0 -mmin +1440 2>/dev/null)" ]]; }
kb(){ du -sk "$1" 2>/dev/null | cut -f1; }

removed=0; deleted=0; kept=0; before=0; after=0
keep(){ echo "kept $1 ($2)"; kept=$((kept+1)); }
drop_branch(){ # $1 branch
  [[ -z "$1" ]] && return 0
  if (( DRY )); then echo "would delete branch $1"; deleted=$((deleted+1)); return 0; fi
  if g branch -D "$1" >/dev/null 2>&1; then echo "deleted branch $1"; deleted=$((deleted+1)); else echo "kept branch $1 (delete failed)"; fi; }
remove(){ # $1 path, $2 reason, $3 branch to delete afterwards ("" for none), $4 lock reason to release first ("" for none)
  local p="$1" why="$2" b="$3" lr="${4:-}" k; k=$(kb "$p"); before=$((before+${k:-0}))
  if (( DRY )); then [[ -n "$lr" ]] && echo "would unlock worktree $p"; echo "would remove worktree $p ($why)"; removed=$((removed+1)); drop_branch "$b"; return 0; fi
  if [[ -n "$lr" ]]; then
    g worktree unlock "$p" >/dev/null 2>&1 || { keep "$p" "locked: $lr; unlock failed"; k=$(kb "$p"); after=$((after+${k:-0})); return 0; }
    echo "unlocked worktree $p"
  fi
  if g worktree remove --force "$p" >/dev/null 2>&1; then
    echo "removed worktree $p ($why)"; removed=$((removed+1))
    [[ -d "$p" ]] && { k=$(kb "$p"); after=$((after+${k:-0})); }
    drop_branch "$b"
  else
    [[ -n "$lr" ]] && g worktree lock --reason "$lr" "$p" >/dev/null 2>&1   # not removed: it stays protected as it was
    keep "$p" "git worktree remove failed"; k=$(kb "$p"); after=$((after+${k:-0})); fi; }
locked_entry(){ # $1 path, $2 sha, $3 branch, $4 lock reason → the only way out of a lock is a merged PR containing the tip
  local p="$1" sha="$2" b="$3" lr="$4" shown st why
  shown="locked: ${lr:-no reason given}"
  case "$lr" in "pocket-it: "*) ;; *) keep "$p" "$shown; not a pocket-it lock, never released"; return 0;; esac
  if [[ ! -d "$p" ]]; then   # deleted from disk: the lock protects nothing any more, only the branch is left to judge
    if (( DRY )); then echo "would unlock and prune worktree $p (missing on disk)"
    else g worktree unlock "$p" >/dev/null 2>&1; g worktree prune >/dev/null 2>&1; echo "unlocked and pruned worktree $p (missing on disk)"; fi
    removed=$((removed+1))
    [[ -n "$b" ]] && ! { protected "$b" && (( ! ALL )); } && merged_pr "$sha" "$b" >/dev/null && drop_branch "$b"
    return 0; fi
  [[ -z "$b" ]] && { keep "$p" "$shown; no branch"; return 0; }
  protected "$b" && (( ! ALL )) && { keep "$p" "$shown; protected branch $b"; return 0; }
  st=$(git -C "$p" status --porcelain 2>/dev/null) || { keep "$p" "$shown; git status failed"; return 0; }
  [[ -n "$st" ]] && { keep "$p" "$shown; dirty"; return 0; }
  why=$(merged_pr "$sha" "$b") || { keep "$p" "$shown; ${why:-no merged PR contains its tip}"; return 0; }
  remove "$p" "$why, lock released" "$b" "$lr"; }

i=0
for e in "${entries[@]}"; do
  i=$((i+1)); (( i == 1 )) && continue
  IFS='|' read -r p sha branch flags lockr <<<"$e"
  [[ "$(abs "$p")" == "$CUR" ]] && { keep "$p" "current worktree"; continue; }
  case " $flags " in *" locked "*) locked_entry "$p" "$sha" "$branch" "$lockr"; continue;; esac
  case " $flags " in *" prunable "*)
    echo "pruned worktree $p (missing on disk)"; removed=$((removed+1)); (( DRY )) || g worktree prune >/dev/null 2>&1
    [[ -n "$branch" ]] && ( protected "$branch" && (( ! ALL )) ) && continue
    [[ -n "$branch" ]] && decide "$sha" "$branch" >/dev/null && drop_branch "$branch"; continue;; esac
  case " $flags " in *" detached "*)
    if is_scratch "$(abs "$p")" && older_24h "$p"; then remove "$p" "detached scratch older than 24 h" ""; else keep "$p" "detached"; fi; continue;; esac
  [[ -z "$branch" ]] && { keep "$p" "no branch"; continue; }
  protected "$branch" && (( ! ALL )) && { keep "$p" "protected branch $branch"; continue; }
  st=$(git -C "$p" status --porcelain 2>/dev/null) || { keep "$p" "git status failed"; continue; }   # unreadable is never clean
  [[ -n "$st" ]] && { keep "$p" "dirty"; continue; }
  why=$(decide "$sha" "$branch") || { keep "$p" "$why"; continue; }
  remove "$p" "$why" "$branch"
done
(( DRY )) || g worktree prune >/dev/null 2>&1

mb=$(awk -v k=$((before-after)) 'BEGIN{printf "%.1f", k/1024}')
if (( DRY )); then echo "cleanup-merged (dry-run): $removed worktrees would be removed, $deleted branches would be deleted, $kept kept, would free $mb MB"
else echo "cleanup-merged: $removed worktrees removed, $deleted branches deleted, $kept kept, freed $mb MB"; fi
exit 0
