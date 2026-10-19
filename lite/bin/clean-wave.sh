#!/usr/bin/env bash
# Removes from main the files of a finished wave, with a PR merged by merge-pr.sh.
#   clean-wave.sh <slug> <wave> <PR>...   the wave's tasks (from the plan in tasks/<slug>/INDEX.md);
#                                           if it is the last wave, all of tasks/<slug> and docs/features/<slug>
#   clean-wave.sh <slug> all [<PR>...]  all of tasks/<slug> and docs/features/<slug> (feature closed)
#   --dry-run as the first argument: prints the checks and the files, writes nothing.
# It stops, touching nothing, if a given PR is not MERGED, if the PRs are fewer than the wave's
# tasks, if there is an open PR with the slug in the branch, or if a task has no file of its own.
# Then it removes the worktrees and branches left over from the wave (sec/, test/, tasks/, rev-<PR>)
# with wave-worktrees.sh, which skips a worktree with uncommitted changes.
# Run it from the main checkout (merge-pr.sh uses it). The project's checks
# (scripts/pre-merge.sh) are run by merge-pr.sh: if they are red the PR stays open.
set -euo pipefail

bin=$(cd "$(dirname "$0")" && pwd)
. "$bin/plan.sh"

die() { echo "clean-wave: $1" >&2; exit "${2:-1}"; }

dry_run=
if [ "${1:-}" = "--dry-run" ]; then dry_run=1; shift; fi
slug="${1:-}"; wave="${2:-}"
[ -n "$slug" ] && [ -n "$wave" ] || die "usage: clean-wave.sh [--dry-run] <slug> <wave|all> <PR>..."
shift 2
case "$slug" in *[!a-zA-Z0-9._-]*|.*) die "invalid slug: $slug" ;; esac
case "$wave" in all) ;; *[!0-9]*|"") die "invalid wave: $wave (a number or «all»)" ;; esac
[ "$wave" = all ] || [ $# -gt 0 ] || die "the PRs of wave $wave are needed"

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "you are not in a git repo"
repo=$(dirname "$common")
cd "$repo"
git fetch -q --prune origin

# 1. The given PRs are merged; no open PR has the slug in the branch.
for pr in "$@"; do
  state=$(gh pr view "$pr" --json state -q .state) || die "PR $pr not found"
  [ "$state" = MERGED ] || die "PR $pr is $state, not MERGED"
done
open_prs=$(gh pr list --state open --limit 200 --json number,headRefName \
  -q ".[] | select(.headRefName | contains(\"$slug\")) | \"#\(.number) \(.headRefName)\"")
[ -z "$open_prs" ] || die "open PRs on $slug: $(echo "$open_prs" | tr '\n' ' ')"

# 2. The files to remove, read from origin/main.
exists() { git cat-file -e "origin/main:$1" 2>/dev/null; }
all_feature_paths() { for p in "tasks/$slug" "docs/features/$slug"; do if exists "$p"; then echo "$p"; fi; done; }
last=
if [ "$wave" = all ]; then
  paths=$(all_feature_paths)
else
  index="tasks/$slug/INDEX.md"
  exists "$index" || die "$index is missing on main: without the plan I cannot tell which tasks belong to the wave"
  plan=$(git show "origin/main:$index" | plan_rows)
  last=$(echo "$plan" | awk '{print $1}' | sort -n | tail -1)
  ids=$(echo "$plan" | awk -v w="$wave" '$1 == w {print $2}')
  [ -n "$ids" ] || die "wave $wave is not in the plan of $index"
  n=$(echo "$ids" | wc -l | tr -d ' ')
  [ $# -ge "$n" ] || die "wave $wave has $n tasks ($(echo $ids)) but the given PRs are $#"
  if [ "$wave" = "$last" ]; then
    paths=$(all_feature_paths)
  else
    files=$(git ls-tree --name-only "origin/main" "tasks/$slug/")
    paths=
    for id in $ids; do
      f=$(echo "$files" | awk -v a="tasks/$slug/$id.md" -v b="tasks/$slug/$id-" '$0 == a || (index($0, b) == 1 && /\.md$/)')
      [ "$(echo "$f" | grep -c .)" = 1 ] || die "task $id does not have exactly one file in tasks/$slug/: '$(echo $f)'"
      paths=$(printf '%s\n%s' "$paths" "$f")
    done
  fi
fi
paths=$(echo "$paths" | grep . || true)
[ -n "$paths" ] || die "nothing to remove for $slug wave $wave: already removed?"

echo "clean-wave: $slug wave $wave, PRs checked: ${*:-none}"
echo "$paths" | sed 's/^/  - /'
wt_wave=$wave; [ "$wave" != "$last" ] || wt_wave=all   # last wave: every worktree of the feature
if [ -n "$dry_run" ]; then bash "$bin/wave-worktrees.sh" --dry-run "$slug" "$wt_wave" "$@"; exit 0; fi

# 3. Worktrees and branches left over from the wave.
bash "$bin/wave-worktrees.sh" "$slug" "$wt_wave" "$@"

# 4. Branch, commit, PR, merge with the project's checks.
branch="docs/cleanup-$slug-wave-$wave"
wt=$("$bin/worktree-new.sh" "$branch" | tail -1)
echo "$paths" | while IFS= read -r p; do git -C "$wt" rm -r -q -- "$p"; done
msg="docs(cleanup): removed the files of $slug, wave $wave"
body="Wave $wave of \`$slug\` merged (PR: ${*:-none}). Removed:
$(echo "$paths" | sed 's/^/- `/; s/$/`/')

They stay in the git history."
git -C "$wt" commit -q -m "$msg" -m "$body"
git -C "$wt" push -q -u origin "$branch"
pr=$(gh pr create --head "$branch" --base main --title "$msg" --body "$body" | grep -o '[0-9]*$')
echo "clean-wave: PR $pr opened, merging…"
"$bin/merge-pr.sh" "$pr"
