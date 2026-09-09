#!/usr/bin/env bash
# Self-test for worktree.sh against a scratch repo: a fake origin, a fresh branch created off origin/main, an
# existing remote branch checked out tracking, idempotent re-runs, the .git/info/exclude line, and usage errors.
cd "$(dirname "$0")"
SCRIPT="$PWD/worktree.sh"
S=$(mktemp -d "${TMPDIR:-/tmp}/worktree-test.XXXXXX")
cleanup(){ rm -rf "$S"; }
trap cleanup EXIT
fail=0
ok(){ if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
q(){ "$@" >/dev/null 2>&1; }

q git init -q --bare "$S/origin.git"
q git init -q -b main "$S/main"; M=$(cd "$S/main" && pwd -P)   # resolved: worktree.sh also resolves symlinks (e.g. /tmp on macOS)
echo base > "$M/f"; q git -C "$M" add f; q git -C "$M" commit -qm base
q git -C "$M" remote add origin "$S/origin.git"; q git -C "$M" push -q -u origin main
echo '{"baseBranch":"main"}' > "$M/.pocket-it.json"
q git -C "$M" add .pocket-it.json; q git -C "$M" commit -qm cfg; q git -C "$M" push -q origin main
# an existing remote branch, pushed from a throwaway clone (never checked out in $M)
q git clone -q "$S/origin.git" "$S/tmpclone"
q git -C "$S/tmpclone" checkout -q -b task/existing
echo x > "$S/tmpclone/x"; q git -C "$S/tmpclone" add x; q git -C "$S/tmpclone" commit -qm x
q git -C "$S/tmpclone" push -q -u origin task/existing

# 1. usage errors — nothing created
OUT=$(bash "$SCRIPT" 2>&1 >/dev/null); rc=$?
ok "no args exits 2" "[[ $rc -eq 2 ]]"
ERR=$(bash "$SCRIPT" "$S/not-a-repo" task/x 2>&1 >/dev/null); rc=$?
ok "non-repo path exits 2 with a one-line error" "[[ $rc -eq 2 && $(echo \"$ERR\" | wc -l | tr -d ' ') -eq 1 ]]"
ok "non-repo path created nothing" "[[ ! -e $S/not-a-repo/.claude ]]"
ERR=$(bash "$SCRIPT" "$M" "task with space" 2>&1 >/dev/null); rc=$?
ok "branch with spaces exits 2 with a one-line error" "[[ $rc -eq 2 && $(echo \"$ERR\" | wc -l | tr -d ' ') -eq 1 ]]"
ok "branch with spaces created nothing" "[[ ! -d $M/.claude/worktrees ]]"

# 2. AC1 — new branch, base omitted, from a cwd outside the repo
OUT=$(cd /tmp && bash "$SCRIPT" "$M" task/new1); rc=$?
WT1="$M/.claude/worktrees/task-new1"
ok "AC1 exit 0" "[[ $rc -eq 0 ]]"
ok "AC1 stdout is only the path" "[[ \"$OUT\" == \"$WT1\" ]]"
ok "AC1 worktree exists on new branch off main" "[[ -d $WT1 ]] && q git -C $WT1 rev-parse --verify task/new1 && [[ \$(git -C $WT1 branch --show-current) == task/new1 ]]"
ok "AC1 new branch content matches base" "[[ -f $WT1/f ]]"

# 3. AC2 — existing remote branch, checked out tracking origin
OUT=$(bash "$SCRIPT" "$M" task/existing); rc=$?
WT2="$M/.claude/worktrees/task-existing"
ok "AC2 exit 0" "[[ $rc -eq 0 ]]"
ok "AC2 prints the path" "[[ \"$OUT\" == \"$WT2\" ]]"
ok "AC2 checks out the existing branch" "[[ -f $WT2/x ]] && [[ \$(git -C $WT2 branch --show-current) == task/existing ]]"
ok "AC2 tracks origin" "[[ \$(git -C $WT2 rev-parse --abbrev-ref --symbolic-full-name @{u}) == origin/task/existing ]]"

# 4. AC3 — idempotent
OUT2=$(bash "$SCRIPT" "$M" task/new1 2>/dev/null); rc=$?
ok "AC3 second run exit 0" "[[ $rc -eq 0 ]]"
ok "AC3 second run prints the same path" "[[ \"$OUT2\" == \"$WT1\" ]]"

# 5. AC4 — .git/info/exclude has the line once, not duplicated across branches
ok "AC4 exclude has the line" "grep -qxF '.claude/worktrees/' $M/.git/info/exclude"
ok "AC4 exclude has it exactly once" "[[ \$(grep -cxF '.claude/worktrees/' $M/.git/info/exclude) -eq 1 ]]"

exit $fail
