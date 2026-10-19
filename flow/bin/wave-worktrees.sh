#!/usr/bin/env bash
# Removes the worktrees and the branches (local and remote) left over from a finished wave: sec/, test/,
# tasks/ (security, tester and task-writer do not all go through merge-pr.sh) and rev-<PR> of the given PRs.
#   wave-worktrees.sh [--dry-run] <slug> <wave> [<PR>...]   sec|test|tasks/<slug>-<wave>, also with
#                                                           a letter after it (-1a)
#   wave-worktrees.sh [--dry-run] <slug> all [<PR>...]      those of every wave, and -plan
# After the slug it accepts only the wave number (and a letter) or «plan»: any other dash would
# take another feature whose slug starts with this one (auth against auth-v2).
#   --dry-run: prints what it would remove, touches nothing.
# Skips, without stopping, a worktree with uncommitted changes or the branch of the main checkout.
# clean-wave.sh runs it after checking that the slug's PRs are closed.
set -euo pipefail

bin=$(cd "$(dirname "$0")" && pwd)
die() { echo "wave-worktrees: $1" >&2; exit "${2:-1}"; }

dry_run=
if [ "${1:-}" = "--dry-run" ]; then dry_run=1; shift; fi
slug="${1:-}"; wave="${2:-}"
[ -n "$slug" ] && [ -n "$wave" ] || die "usage: wave-worktrees.sh [--dry-run] <slug> <wave|all> [<PR>...]"
shift 2
case "$slug" in *[!a-zA-Z0-9._-]*|.*) die "invalid slug: $slug" ;; esac
case "$wave" in all) ;; *[!0-9]*|"") die "invalid wave: $wave (a number or «all»)" ;; esac

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "not inside a git repo"
repo=$(dirname "$common")
root="$repo/.claude/worktrees"
cd "$repo"

re_slug=$(printf '%s' "$slug" | sed 's/\./\\./g')
if [ "$wave" = all ]; then tail='-([0-9]+[a-z]?|plan)'; else tail="-$wave[a-z]?"; fi
branches=$( { git for-each-ref --format='%(refname:lstrip=2)' refs/heads
              git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin; } \
  | grep -E "^(sec|test|tasks)/$re_slug$tail\$" | sort -u || true)

worktree_of() { git worktree list --porcelain | awk -v b="refs/heads/$1" '/^worktree /{p=substr($0,10)} $0=="branch " b {print p}'; }
to_remove= skipped=
for b in $branches; do
  w=$(worktree_of "$b")
  if [ "$w" = "$repo" ]; then
    skipped="$skipped $b(main checkout)"
  elif [ -n "$w" ] && [ -n "$(git -C "$w" status --porcelain --untracked-files=no)" ]; then
    skipped="$skipped $b(uncommitted changes)"
  else
    to_remove="$to_remove $b"
  fi
done
rev=
for pr in "$@"; do
  if [ -e "$root/rev-$pr" ]; then rev="$rev rev-$pr"; fi
done

echo "wave-worktrees: to remove:${to_remove:- no branch}${rev}"
[ -z "$skipped" ] || echo "wave-worktrees: skipped:$skipped"
[ -z "$dry_run" ] || exit 0

# Removes the directories left empty between the removed worktree and .claude/worktrees.
prune_parents() { local d; d=$(dirname "$1"); while [ "$d" != "$root" ] && [ "${d#"$root"/}" != "$d" ] && rmdir "$d" 2>/dev/null; do d=$(dirname "$d"); done; }
remove_worktree() {
  bash "$bin/stop-worktree-procs.sh" "$1"
  git worktree remove --force "$1"   # --force removes only untracked files (test-results, links)
  prune_parents "$1"
}
for r in $rev; do remove_worktree "$root/$r"; done
for b in $to_remove; do
  w=$(worktree_of "$b")
  if [ -n "$w" ]; then remove_worktree "$w"; fi
  if git show-ref -q --verify "refs/heads/$b"; then git branch -q -D "$b"; fi
  if git show-ref -q --verify "refs/remotes/origin/$b"; then git push -q origin --delete "$b"; fi
done
git worktree prune
