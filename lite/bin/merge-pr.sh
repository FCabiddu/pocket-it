#!/usr/bin/env bash
# Merges an approved PR and cleans everything up, in the right order:
#   -. stops if the branch carries a task ID (T10, E2E-3, R19) and the PR body does not name it;
#   -. stops if the PR brings a wave (wave/*) to main without the «security» = success status
#      on the head commit (security-ok.sh, after the security agent's SECURITY OK);
#   -. stops if the PR adds or changes files in tasks/<slug>/ and the plan tasks/<slug>/INDEX.md
#      is missing or has no rows that clean-wave.sh can read (plan.sh);
#   0. runs the project's scripts/pre-merge.sh on the PR merged with the base, with
#      PRE_MERGE_BASE=<base>, and stops if it is red, if the PR conflicts or if the
#      script is missing (template: lite/templates/pre-merge.sh);
#   1. removes the worktrees of the branch and rev-<PR> (stops if the worktree has uncommitted changes),
#      after stopping the processes still running inside (stop-worktree-procs.sh);
#   2. merge and deletion of the remote branch: squash, but a true merge if the base is wave/*
#      (a squash would flatten the merge of main done in the branch, and the wave would
#      conflict with main);
#   3. checks that the remote branch is gone;
#   4. deletes the local branch;
#   5. fetch, local main up to date (--ff-only), worktree prune.
#   Commands towards GitHub (gh, git fetch/push/ls-remote) are retried if the network drops (network.sh).
#   merge-pr.sh <PR>     (from inside the repo)
set -euo pipefail

bin=$(cd "$(dirname "$0")" && pwd)   # before the cd into the repo: $0 may be relative
. "$bin/plan.sh"
. "$bin/network.sh"

die() { echo "merge-pr: $1" >&2; exit "${2:-1}"; }

pr="${1:-}"; [ -n "$pr" ] || die "usage: merge-pr.sh <PR>"
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "not inside a git repo"
repo=$(dirname "$common")
root="$repo/.claude/worktrees"
cd "$repo"

read -r state branch base head < <(rete gh pr view "$pr" --json state,headRefName,baseRefName,headRefOid -q '.state + " " + .headRefName + " " + .baseRefName + " " + .headRefOid')
[ "$state" = "OPEN" ] || die "PR $pr is $state, not OPEN"

# The body belongs to the right PR: if the branch carries a task ID (feat/<x>-T10-…,
# test/<x>-E2E-3, fix/<x>-R19-…), the body must name it. A body copied from another
# task makes the reviewer decide on the wrong results.
task=$(sed -nE 's#^.*[/-](E2E-[0-9]+|[TR][0-9]+[a-z]?)(-.*)?$#\1#p' <<< "$branch")
if [ -n "$task" ]; then
  body=$(rete gh pr view "$pr" --json body -q .body)
  grep -qwF -- "$task" <<< "$body" \
    || die "the body of PR $pr does not name task $task of branch $branch: is it the body of another PR? Fix it (gh pr edit $pr --body-file …) and rerun"
fi

# A wave reaches main only with the security agent's sign-off on the commit being merged
# («security» status set by security-ok.sh): a commit added after the sign-off requires a new check.
if [ "$base" = main ] && [ "${branch#wave/}" != "$branch" ]; then
  sec=$(rete gh api "repos/{owner}/{repo}/commits/$head/statuses" -q '[.[] | select(.context == "security")][0].state // ""')
  [ "$sec" = success ] || die "wave $branch has no sign-off from the security agent on commit ${head:0:8}: run security (Wave job), then security-ok.sh $pr"
fi

# Removes the directories left empty between the removed worktree and .claude/worktrees.
prune_parents() { local d; d=$(dirname "$1"); while [ "$d" != "$root" ] && [ "${d#"$root"/}" != "$d" ] && rmdir "$d" 2>/dev/null; do d=$(dirname "$d"); done; }

# 0. Project checks: scripts/pre-merge.sh runs on the PR code merged with the
#    base, in a temporary worktree. Red, conflict or missing script: no merge.
ref="refs/merge-pr/$pr"
check="$root/pre-merge-$pr"
remove_check() { if [ -e "$check" ]; then git worktree remove --force "$check"; prune_parents "$check"; fi; }
cleanup_check() { remove_check; git update-ref -d "$ref" 2>/dev/null || true; }
rete git fetch -q origin "$base" "+refs/pull/$pr/head:$ref"
if git cat-file -e "$ref:scripts/pre-merge.sh" 2>/dev/null || git cat-file -e "origin/$base:scripts/pre-merge.sh" 2>/dev/null; then
  trap 'rc=$?; cleanup_check; exit $rc' EXIT
  remove_check
  git worktree add -q --detach "$check" "$ref"
  git -C "$check" -c user.name=merge-pr -c user.email=merge-pr@localhost merge -q --no-edit "origin/$base" \
    || die "PR $pr conflicts with $base: merge $base into the branch"
  # The task plan is checked when it comes in, not at the end of the wave in clean-wave.sh.
  for slug in $(git -C "$check" diff --name-only --diff-filter=d "origin/$base" HEAD -- tasks/ | awk -F/ 'NF > 2 { print $2 }' | sort -u); do
    errore=$(plan_check "$check" "$slug")
    [ -z "$errore" ] || die "PR $pr: $errore. The task-writer fixes it on the branch, then rerun"
  done
  # A PR that changes the dependencies is not checked with the node_modules of the main
  # checkout (they are the base's): npm ci installs the PR's.
  links="node_modules .env.local"
  if [ -e "$check/package-lock.json" ] && ! git diff --quiet "origin/$base" "$ref" -- package.json package-lock.json; then
    echo "merge-pr: PR $pr changes the dependencies, npm ci in the check worktree…"
    (cd "$check" && npm ci --no-audit --no-fund --loglevel=error >/dev/null) || die "npm ci failed on PR $pr"
    links=".env.local"
  fi
  for f in $links; do
    if [ -e "$repo/$f" ] && [ ! -e "$check/$f" ]; then ln -s "$repo/$f" "$check/$f"; fi
  done
  echo "merge-pr: scripts/pre-merge.sh on PR $pr merged with ${base}…"
  (cd "$check" && PRE_MERGE_BASE="$base" bash scripts/pre-merge.sh) || die "scripts/pre-merge.sh is red on PR $pr: merge stopped"
  cleanup_check
  trap - EXIT
else
  git update-ref -d "$ref"
  die "the project has no scripts/pre-merge.sh: no merge without checks. The architect creates it from $bin/../templates/pre-merge.sh (project-ready.sh says what is missing)"
fi

# 1. Worktrees: those on the PR branch, plus rev-<PR>.
paths=$(git worktree list --porcelain | awk -v b="refs/heads/$branch" '/^worktree /{p=substr($0,10)} $0=="branch " b {print p}')
[ -e "$root/rev-$pr" ] && paths=$(printf '%s\n%s' "$paths" "$root/rev-$pr")
while IFS= read -r p; do
  [ -n "$p" ] || continue
  [ "$p" != "$repo" ] || die "branch $branch is in use in the main checkout"
  if [ "$p" != "$root/rev-$pr" ] && [ -n "$(git -C "$p" status --porcelain --untracked-files=no)" ]; then
    die "$p has uncommitted changes: stop and report"
  fi
  bash "$bin/stop-worktree-procs.sh" "$p"
  git worktree remove --force "$p"   # --force removes only untracked files (test-results, links)
  prune_parents "$p"
done <<< "$paths"

# 2. Merge.
case "$base" in wave/*) how=--merge ;; *) how=--squash ;; esac
# If the network drops after the merge, the retry says «already merged»: the state decides.
rete gh pr merge "$pr" "$how" --delete-branch >/dev/null || true
merged=$(rete gh pr view "$pr" --json state -q .state)
[ "$merged" = "MERGED" ] || die "PR $pr does not show as merged"
if [ "$how" = --merge ]; then
  rete git fetch -q origin "$base"
  git merge-base --is-ancestor "$head" "origin/$base" || die "true merge expected: $head is not an ancestor of origin/$base"
fi

# 3. Remote branch.
remoto=$(rete git ls-remote --heads origin "$branch")
if [ -n "$remoto" ]; then
  rete git push -q origin --delete "$branch"
fi
remoto=$(rete git ls-remote --heads origin "$branch")
[ -z "$remoto" ] || die "remote branch $branch is still there"

# 4. Local branch.
if git show-ref -q --verify "refs/heads/$branch"; then git branch -q -D "$branch"; fi

# 5. Local base up to date.
rete git fetch -q --prune origin
if [ "$(git branch --show-current)" = "$base" ]; then git merge -q --ff-only "origin/$base"; fi
git worktree prune

echo "PR $pr merged; $base at $(git rev-parse --short "origin/$base")"
