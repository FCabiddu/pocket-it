#!/usr/bin/env bash
# Test cases of wave-worktrees.sh: `bash flow/bin/wave-worktrees-cases.sh`. Exits with 1 if a case fails.
bin=$(cd "$(dirname "$0")" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P); fail=0
c() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (expected $2, got $3)"; fail=1; fi; }
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
wt() { (cd "$tmp/repo" && bash "$bin/worktree-new.sh" "$@" 2>/dev/null | tail -1); }
local_branches() { g -C "$tmp/repo" for-each-ref --format='%(refname:lstrip=2)' refs/heads | grep -v '^main$' | paste -sd, -; }
remote_branches() { g -C "$tmp/repo" ls-remote --heads origin | sed 's#.*refs/heads/##' | grep -v '^main$' | paste -sd, -; }
folders() { (cd "$tmp/repo/.claude/worktrees" && find . -mindepth 1 -maxdepth 2 -type d | sed 's#^\./##' | sort | paste -sd, -); }

g init -q --bare "$tmp/origin.git"
g init -q "$tmp/repo"
echo x > "$tmp/repo/a"; g -C "$tmp/repo" add a; g -C "$tmp/repo" commit -q -m a
g -C "$tmp/repo" remote add origin "$tmp/origin.git"; g -C "$tmp/repo" push -q origin main

# Waves 1 and 2 of «fe.a» (a dot in the slug), plus similar slugs that must not be touched: feXa, fe.a-b
# (starts like fe.a) and fe.a-1-x (starts like its wave 1).
for b in sec/fe.a-1 test/fe.a-1 tasks/fe.a-1a tasks/fe.a-plan sec/fe.a-2 sec/feXa-1 sec/fe.a-10 sec/fe.a-b-1 sec/fe.a-1-x; do wt "$b" >/dev/null; done
g -C "$tmp/repo" push -q origin tasks/fe.a-1a sec/fe.a-2
g -C "$tmp/repo" worktree add -q --detach "$tmp/repo/.claude/worktrees/rev-7" main
echo y > "$tmp/repo/.claude/worktrees/test/fe.a-1/a"   # uncommitted change
echo n > "$tmp/repo/.claude/worktrees/sec/fe.a-1/new"  # only an untracked file

out=$(cd "$tmp/repo" && bash "$bin/wave-worktrees.sh" --dry-run fe.a 1 7)
c "--dry-run: list of wave 1"             "wave-worktrees: to remove: sec/fe.a-1 tasks/fe.a-1a rev-7" "$(echo "$out" | head -1)"
c "--dry-run: dirty worktree skipped"     "wave-worktrees: skipped: test/fe.a-1(uncommitted changes)" "$(echo "$out" | sed -n 2p)"
c "--dry-run touches nothing"             "sec/fe.a-1,sec/fe.a-1-x,sec/fe.a-10,sec/fe.a-2,sec/fe.a-b-1,sec/feXa-1,tasks/fe.a-1a,tasks/fe.a-plan,test/fe.a-1" "$(local_branches)"

(cd "$tmp/repo" && bash "$bin/wave-worktrees.sh" fe.a 1 7 >/dev/null)
c "wave 1: local branches left"           "sec/fe.a-1-x,sec/fe.a-10,sec/fe.a-2,sec/fe.a-b-1,sec/feXa-1,tasks/fe.a-plan,test/fe.a-1" "$(local_branches)"
c "wave 1: remote branch removed"         "sec/fe.a-2" "$(remote_branches)"
c "wave 1: folders left"                  "sec,sec/fe.a-1-x,sec/fe.a-10,sec/fe.a-2,sec/fe.a-b-1,sec/feXa-1,tasks,tasks/fe.a-plan,test,test/fe.a-1" "$(folders)"

g -C "$tmp/repo" -C .claude/worktrees/test/fe.a-1 checkout -q -- a
(cd "$tmp/repo" && bash "$bin/wave-worktrees.sh" fe.a all >/dev/null)
c "all: only the similar slugs remain"    "sec/fe.a-1-x,sec/fe.a-b-1,sec/feXa-1" "$(local_branches)"
c "all: no remote branch"                 "" "$(remote_branches)"
c "all: folders left"                     "sec,sec/fe.a-1-x,sec/fe.a-b-1,sec/feXa-1" "$(folders)"

rm -rf "$tmp"
exit $fail
