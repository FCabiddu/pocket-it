#!/usr/bin/env bash
# Removes from main the files of a finished wave, with a PR merged by merge-pr.sh.
#   clean-wave.sh <slug> <wave> <PR>...   the wave's tasks (from the plan in tasks/<slug>/INDEX.md);
#                                           if it is the last wave, all of tasks/<slug> and docs/features/<slug>
#   clean-wave.sh <slug> all [<PR>...]  all of tasks/<slug> and docs/features/<slug> (feature closed)
#   --dry-run as the first argument: prints the checks and the files, writes nothing.
# It stops, touching nothing, if a given PR is not MERGED, if the PRs are fewer than the wave's
# tasks, if there is an open PR with the slug in the branch, or if a task has no file of its own.
# Run it from the main checkout (merge-pr.sh uses it). The project's checks
# (scripts/pre-merge.sh) are run by merge-pr.sh: if they are red the PR stays open.
set -euo pipefail

bin=$(cd "$(dirname "$0")" && pwd)
. "$bin/plan.sh"

die() { echo "clean-wave: $1" >&2; exit "${2:-1}"; }

prova=
if [ "${1:-}" = "--dry-run" ]; then prova=1; shift; fi
slug="${1:-}"; onda="${2:-}"
[ -n "$slug" ] && [ -n "$onda" ] || die "usage: clean-wave.sh [--dry-run] <slug> <wave|all> <PR>..."
shift 2
case "$slug" in *[!a-zA-Z0-9._-]*|.*) die "invalid slug: $slug" ;; esac
case "$onda" in all) ;; *[!0-9]*|"") die "invalid wave: $onda (a number or «all»)" ;; esac
[ "$onda" = all ] || [ $# -gt 0 ] || die "the PRs of wave $onda are needed"

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "you are not in a git repo"
repo=$(dirname "$common")
cd "$repo"
git fetch -q --prune origin

# 1. The given PRs are merged; no open PR has the slug in the branch.
for pr in "$@"; do
  state=$(gh pr view "$pr" --json state -q .state) || die "PR $pr not found"
  [ "$state" = MERGED ] || die "PR $pr is $state, not MERGED"
done
aperte=$(gh pr list --state open --limit 200 --json number,headRefName \
  -q ".[] | select(.headRefName | contains(\"$slug\")) | \"#\(.number) \(.headRefName)\"")
[ -z "$aperte" ] || die "open PRs on $slug: $(echo "$aperte" | tr '\n' ' ')"

# 2. The files to remove, read from origin/main.
esiste() { git cat-file -e "origin/main:$1" 2>/dev/null; }
all() { for p in "tasks/$slug" "docs/features/$slug"; do if esiste "$p"; then echo "$p"; fi; done; }
if [ "$onda" = all ]; then
  paths=$(all)
else
  index="tasks/$slug/INDEX.md"
  esiste "$index" || die "$index is missing on main: without the plan I cannot tell which tasks belong to the wave"
  piano=$(git show "origin/main:$index" | plan_rows)
  ultima=$(echo "$piano" | awk '{print $1}' | sort -n | tail -1)
  ids=$(echo "$piano" | awk -v o="$onda" '$1 == o {print $2}')
  [ -n "$ids" ] || die "wave $onda is not in the plan of $index"
  n=$(echo "$ids" | wc -l | tr -d ' ')
  [ $# -ge "$n" ] || die "wave $onda has $n tasks ($(echo $ids)) but the given PRs are $#"
  if [ "$onda" = "$ultima" ]; then
    paths=$(all)
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
[ -n "$paths" ] || die "nothing to remove for $slug wave $onda: already removed?"

echo "clean-wave: $slug wave $onda, PRs checked: ${*:-none}"
echo "$paths" | sed 's/^/  - /'
[ -z "$prova" ] || exit 0

# 3. Branch, commit, PR, merge with the project's checks.
branch="docs/cleanup-$slug-wave-$onda"
wt=$("$bin/worktree-new.sh" "$branch" | tail -1)
echo "$paths" | while IFS= read -r p; do git -C "$wt" rm -r -q -- "$p"; done
msg="docs(cleanup): removed the files of $slug, wave $onda"
body="Wave $onda of \`$slug\` merged (PR: ${*:-none}). Removed:
$(echo "$paths" | sed 's/^/- `/; s/$/`/')

They stay in the git history."
git -C "$wt" commit -q -m "$msg" -m "$body"
git -C "$wt" push -q -u origin "$branch"
pr=$(gh pr create --head "$branch" --base main --title "$msg" --body "$body" | grep -o '[0-9]*$')
echo "clean-wave: PR $pr opened, merging…"
"$bin/merge-pr.sh" "$pr"
