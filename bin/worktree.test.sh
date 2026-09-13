#!/usr/bin/env bash
# Self-test for worktree.sh against a scratch repo: a fake origin, a fresh branch created off origin/main, an
# existing remote branch checked out tracking, an existing local branch with an unpushed commit that must
# survive a re-run, idempotent re-runs, a stale non-worktree directory, the .git/info/exclude line, usage
# errors, and the lock (PI-31): created locked with a reason naming branch and date, on git with atomic --lock and on
# older git; relocked on reuse; --unlock releases only pocket-it's lock; a failed creation leaves no worktree and no lock.
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

# 5. AC2 (reviewer finding 1) — a local branch with an unpushed commit must survive a re-run, never be reset
OUT=$(bash "$SCRIPT" "$M" task/wip); WTWIP="$M/.claude/worktrees/task-wip"
q git -C "$M" push -q origin task/wip                                    # origin/task/wip now exists, at the base tip
echo wip > "$WTWIP/wip"; q git -C "$WTWIP" add wip; q git -C "$WTWIP" commit -qm "UNPUSHED WIP"
WIP_SHA=$(git -C "$WTWIP" rev-parse HEAD)
q bash "$SCRIPT" --unlock "$M" task/wip                                    # created locked: release it, as for abandoned work
q git -C "$M" worktree remove "$WTWIP"                                    # branch task/wip stays, worktree gone
ok "local branch with unpushed commit: worktree really removed before the re-run" "[[ ! -d $WTWIP ]]"
OUT2=$(bash "$SCRIPT" "$M" task/wip); rc=$?
ok "local branch with unpushed commit: exit 0" "[[ $rc -eq 0 ]]"
ok "local branch with unpushed commit: worktree recreated" "[[ \"$OUT2\" == \"$WTWIP\" ]] && [[ -d $WTWIP ]]"
ok "local branch with unpushed commit: NOT reset to origin — WIP survives" "[[ \$(git -C $WTWIP rev-parse HEAD) == $WIP_SHA ]]"

# 6. AC3 (reviewer finding 3) — a stale directory that is not a registered worktree is rejected, not reused
STALE_WT="$M/.claude/worktrees/task-stale"
mkdir -p "$STALE_WT"; echo leftover > "$STALE_WT/leftover"
ERR=$(bash "$SCRIPT" "$M" task/stale 2>&1 >/dev/null); rc=$?
ok "stale non-worktree directory exits 2" "[[ $rc -eq 2 ]]"
ok "stale non-worktree directory: error says why" "grep -q 'not a registered git worktree' <<<\"$ERR\""
ok "stale non-worktree directory: left untouched" "[[ -f $STALE_WT/leftover ]]"

# 7. AC4 — .git/info/exclude has the line once, not duplicated across branches
ok "AC4 exclude has the line" "grep -qxF '.claude/worktrees/' $M/.git/info/exclude"
ok "AC4 exclude has it exactly once" "[[ \$(grep -cxF '.claude/worktrees/' $M/.git/info/exclude) -eq 1 ]]"

# 8. PI-31 AC1 — every worktree it creates is locked, reason naming the branch and the date
lockof(){ git -C "$M" worktree list --porcelain | awk -v w="worktree $1" '/^worktree /{f=($0==w)} f && /^locked/{print}'; }
DATE_RE='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z'
ok "PI-31 AC1 new branch: locked, reason names branch and date" "[[ \"\$(lockof $WT1)\" =~ ^locked\ pocket-it:\ agent\ worktree\ for\ task/new1\ since\ $DATE_RE\$ ]]"
ok "PI-31 AC1 remote branch checked out: locked" "[[ \"\$(lockof $WT2)\" =~ ^locked\ pocket-it:\ agent\ worktree\ for\ task/existing\ since\ $DATE_RE\$ ]]"
ok "PI-31 AC1 existing local branch checked out: locked" "[[ \"\$(lockof $WTWIP)\" =~ ^locked\ pocket-it:\ agent\ worktree\ for\ task/wip\ since\ $DATE_RE\$ ]]"

# 9. PI-31 reuse keeps a lock as it is, and locks again a worktree that was released
BEFORE=$(lockof "$WT1"); OUT=$(bash "$SCRIPT" "$M" task/new1 2>/dev/null); rc=$?
ok "PI-31 reuse of a locked worktree: exit 0, same path, lock unchanged" "[[ $rc -eq 0 && \"$OUT\" == \"$WT1\" && \"\$(lockof $WT1)\" == \"$BEFORE\" ]]"
OUT=$(bash "$SCRIPT" --unlock "$M" task/new1 2>/dev/null); rc=$?
ok "PI-31 --unlock: exit 0, prints the path, lock released" "[[ $rc -eq 0 && \"$OUT\" == \"$WT1\" && -z \"\$(lockof $WT1)\" ]]"
ERR=$(bash "$SCRIPT" --unlock "$M" task/new1 2>&1 >/dev/null); rc=$?
ok "PI-31 --unlock twice: exit 0, says it is not locked" "[[ $rc -eq 0 ]] && grep -q 'is not locked' <<<\"$ERR\""
OUT=$(bash "$SCRIPT" "$M" task/new1 2>/dev/null); rc=$?
ok "PI-31 reuse of a released worktree: locked again" "[[ $rc -eq 0 && \"\$(lockof $WT1)\" =~ ^locked\ pocket-it:\ agent\ worktree\ for\ task/new1 ]]"

# 10. PI-31 a lock someone else placed is never released nor replaced
q git -C "$M" worktree unlock "$WT2"; q git -C "$M" worktree lock --reason "manual hold" "$WT2"
ERR=$(bash "$SCRIPT" --unlock "$M" task/existing 2>&1 >/dev/null); rc=$?
ok "PI-31 --unlock on a foreign lock: exit 1, says so, lock kept" "[[ $rc -eq 1 && \"\$(lockof $WT2)\" == 'locked manual hold' ]] && grep -q 'locked by someone else (manual hold)' <<<\"$ERR\""
q bash "$SCRIPT" "$M" task/existing
ok "PI-31 reuse of a foreign-locked worktree: foreign reason left as it is" "[[ \"\$(lockof $WT2)\" == 'locked manual hold' ]]"
ERR=$(bash "$SCRIPT" --unlock "$M" task/nowhere 2>&1 >/dev/null); rc=$?
ok "PI-31 --unlock of a branch with no worktree: exit 2" "[[ $rc -eq 2 ]] && grep -q 'no worktree has task/nowhere' <<<\"$ERR\""
bash "$SCRIPT" --unlock "$M" task/new1 extra >/dev/null 2>&1; rc=$?
ok "PI-31 --unlock with a base argument: usage error" "[[ $rc -eq 2 ]]"

# 11. PI-31 error paths leave no worktree and so no lock behind
COUNT=$(git -C "$M" worktree list --porcelain | grep -c '^worktree ')
bash "$SCRIPT" "$M" task/badbase nosuchbase >/dev/null 2>&1; rc=$?
ok "PI-31 missing base: exit 2, no worktree registered, no lock" "[[ $rc -eq 2 && ! -d $M/.claude/worktrees/task-badbase ]] && [[ \$(git -C $M worktree list --porcelain | grep -c '^worktree ') -eq $COUNT ]]"
bash "$SCRIPT" "$M" main >/dev/null 2>&1; rc=$?
ok "PI-31 branch already checked out elsewhere: exit 2, no worktree registered, no lock" "[[ $rc -eq 2 && ! -d $M/.claude/worktrees/main ]] && [[ \$(git -C $M worktree list --porcelain | grep -c '^worktree ') -eq $COUNT ]]"

# 12. PI-31 git without `worktree add --reason` (< 2.36): the worktree is locked right after creation
REALGIT=$(command -v git); mkdir -p "$S/oldgit"
cat > "$S/oldgit/git" <<SHIM
#!/usr/bin/env bash
for a in "\$@"; do [[ "\$a" == --reason || "\$a" == --lock ]] && [[ " \$* " == *" add "* ]] && { echo "error: unknown option" >&2; exit 129; }; done
[[ " \$* " == *" worktree add -h "* ]] && { echo "usage: git worktree add [-f] [--detach] [--checkout] [--lock] [-b <new-branch>] <path> [<commit-ish>]"; exit 129; }
exec "$REALGIT" "\$@"
SHIM
chmod +x "$S/oldgit/git"
OUT=$(PATH="$S/oldgit:$PATH" bash "$SCRIPT" "$M" task/oldgit 2>/dev/null); rc=$?
WTOLD="$M/.claude/worktrees/task-oldgit"
ok "PI-31 older git: worktree created" "[[ $rc -eq 0 && \"$OUT\" == \"$WTOLD\" && -d $WTOLD ]]"
ok "PI-31 older git: locked, reason names branch and date" "[[ \"\$(lockof $WTOLD)\" =~ ^locked\ pocket-it:\ agent\ worktree\ for\ task/oldgit\ since\ $DATE_RE\$ ]]"

exit $fail
