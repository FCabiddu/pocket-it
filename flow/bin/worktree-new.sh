#!/usr/bin/env bash
# Creates (or resumes) an agent's worktree and prints its path on the last line.
#   worktree-new.sh <branch> [base]   worktree of the branch in <repo>/.claude/worktrees/<branch>.
#                                     If the branch exists (local or remote) it resumes it,
#                                     otherwise it creates it from origin/<base> (default main).
#   worktree-new.sh --review <PR>     the reviewer's worktree in <repo>/.claude/worktrees/rev-<PR>:
#                                     the PR's branch with the base already merged in.
#                                     Run again, it recreates it from scratch (to re-check after a fix).
# Run it from inside the repo (main checkout or one of its worktrees).
set -euo pipefail

die() { echo "worktree-new: $1" >&2; exit "${2:-1}"; }

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "you are not in a git repo"
repo=$(dirname "$common")
root="$repo/.claude/worktrees"

# One worktree at a time: two «git worktree add» together fight over .git/config.
lock="$common/worktree-new.lock"
got=
for _ in $(seq 60); do if mkdir "$lock" 2>/dev/null; then got=1; break; fi; sleep 1; done
[ -n "$got" ] || die "lock $lock held for more than 60s"
trap 'rmdir "$lock" 2>/dev/null || true' EXIT

grep -qxF ".claude/worktrees/" "$common/info/exclude" 2>/dev/null || echo ".claude/worktrees/" >> "$common/info/exclude"
# NOTE.md: the progress notes that developer, tester and task-writer keep in the worktree, never committed.
grep -qxF "NOTE.md" "$common/info/exclude" 2>/dev/null || echo "NOTE.md" >> "$common/info/exclude"

git -C "$repo" fetch -q --prune origin

if [ "${1:-}" = "--review" ]; then
  pr="${2:-}"; [ -n "$pr" ] || die "usage: worktree-new.sh --review <PR>"
  info=$(cd "$repo" && gh pr view "$pr" --json headRefName,baseRefName -q '.headRefName + " " + .baseRefName' 2>/dev/null) \
    || die "PR $pr not found in the repo $repo: run the script from inside the project's repo, for example (cd <Worktree> && worktree-new.sh --review $pr)" 2
  read -r branch base <<< "$info"
  path="$root/rev-$pr"
  if [ -e "$path" ]; then git -C "$repo" worktree remove --force "$path"; fi
  git -C "$repo" worktree add -q --detach "$path" "origin/$branch"
  if ! git -C "$path" merge -q --no-edit "origin/$base" >/dev/null 2>&1; then
    git -C "$path" merge --abort 2>/dev/null || true
    die "PR $pr has conflicts with $base: the developer must update it" 3
  fi
else
  branch="${1:-}"; [ -n "$branch" ] || die "usage: worktree-new.sh <branch> [base]"
  base="${2:-main}"
  path="$root/$branch"
  if [ ! -e "$path" ]; then
    if git -C "$repo" show-ref -q --verify "refs/heads/$branch"; then
      git -C "$repo" worktree add -q "$path" "$branch"
    elif git -C "$repo" show-ref -q --verify "refs/remotes/origin/$branch"; then
      git -C "$repo" worktree add -q --track -b "$branch" "$path" "origin/$branch"
    else
      git -C "$repo" worktree add -q --no-track -b "$branch" "$path" "origin/$base"
    fi
  fi
fi

# Dependencies and secrets of the main checkout, with an absolute path
# (a branch with «/» adds folders: a relative path lands on the wrong level).
for f in node_modules .env.local; do
  if [ -e "$repo/$f" ] && [ ! -e "$path/$f" ]; then
    ln -s "$repo/$f" "$path/$f"
    git -C "$path" check-ignore -q "$f" || echo "/$f" >> "$common/info/exclude"
  fi
done

# Git hooks with a relative path (husky: .husky/_, an ignored folder that exists only
# in the main checkout): without it, the pre-commit does not run in the worktree.
hooks=$(git -C "$repo" config --get core.hooksPath || true)
case "$hooks" in
  ""|/*) ;;
  *)
    hooks=${hooks%/}
    if [ -d "$repo/$hooks" ] && [ ! -e "$path/$hooks" ]; then
      mkdir -p "$(dirname "$path/$hooks")"
      ln -s "$repo/$hooks" "$path/$hooks"
      git -C "$path" check-ignore -q "$hooks" || echo "/$hooks" >> "$common/info/exclude"
    fi
    ;;
esac

echo "$path"
