#!/usr/bin/env bash
# Records that the security agent answered `SICUREZZA OK` on the PR of a wave towards main.
#   sicurezza-ok.sh <PR>     (from inside the repo)
# Sets the «security» = success status on the PR's head commit. merge-pr.sh does not bring
# a wave to main without that status on the commit it merges: a commit added after the sign-off
# (a fix, a merge of main) requires a new security check.
set -euo pipefail
die() { echo "sicurezza-ok: $1" >&2; exit "${2:-1}"; }
pr="${1:-}"; [ -n "$pr" ] || die "usage: sicurezza-ok.sh <PR>" 2
read -r state branch base head < <(gh pr view "$pr" --json state,headRefName,baseRefName,headRefOid -q '.state + " " + .headRefName + " " + .baseRefName + " " + .headRefOid')
[ "$state" = OPEN ] || die "PR $pr is $state, not OPEN"
case "$branch" in onda/*) ;; *) die "PR $pr is not a wave PR ($branch)";; esac
[ "$base" = main ] || die "PR $pr targets $base, not main"
gh api -X POST "repos/{owner}/{repo}/statuses/$head" -f state=success -f context=security \
  -f description="SICUREZZA OK from the security agent" >/dev/null
echo "sicurezza-ok: PR $pr, commit ${head:0:8} marked"
