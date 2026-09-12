#!/usr/bin/env bash
# Self-test for cleanup-merged.sh against a scratch repo. One worktree per state a worktree can be in, each with the
# action the script must take:
#   removed  merged by a merge commit (AC2) · squash-merged, remote gone (AC3, old layout and worktree.sh layout) ·
#            squash-merged, remote still there · fast-forwarded into the base · rebased, then merged · checked out
#            from its remote branch, PR merged · old detached scratch under /tmp · missing on disk (pruned, branch deleted)
#   kept     no commits of its own, read from the branch reflog (AC1): at the base tip, behind an advanced base, off a
#            live epic, off an epic since merged and deleted everywhere, off a non-base branch since merged, off a
#            second-parent sha, reusing the name of an old merged PR, fast-forwarded to the base, reset back past its
#            own commits · reflog cannot tell: none, or inherited through branch -c / -m · checked out from its remote branch with no merged PR (empty remote, or
#            merged without a PR) · uncommitted edit, untracked file only, dirty after merge (AC4) · own commits not
#            pushed · pushed and not merged · new commits after a merge · new commits after a squash-merged PR ·
#            git status failing · locked · protected epic · detached outside /tmp · current worktree · missing on disk
#            with no commits of its own (pruned, branch kept)
cd "$(dirname "$0")" || exit 2
SCRIPT="$PWD/cleanup-merged.sh"
S=$(mktemp -d "${TMPDIR:-/tmp}/cleanup-merged-test.XXXXXX")
SCRATCH_WT="/tmp/pocket-it-cleanup-test-$$"
cleanup(){ rm -rf "$S" "$SCRATCH_WT"; }
trap cleanup EXIT
fail=0
ok(){ if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
has(){ grep -qE "$1" <<<"$OUT"; }
branch_exists(){ git -C "$M" rev-parse --verify -q "refs/heads/$1" >/dev/null 2>&1; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
q(){ "$@" >/dev/null 2>&1; }
# fake gh: `gh pr list --state merged --head <branch> …` prints the "number headRefOid" lines recorded in $PRS/<branch>
export PRS="$S/prs"; mkdir -p "$S/bin" "$PRS"; cat > "$S/bin/gh" <<'GH'
#!/usr/bin/env bash
h=""; prev=""; for a in "$@"; do [[ "$prev" == --head ]] && h="$a"; prev="$a"; done
f="$PRS/${h//\//__}"; [[ -n "$h" && -f "$f" ]] && cat "$f"; exit 0
GH
chmod +x "$S/bin/gh"; export PATH="$S/bin:$PATH"
pr(){ echo "$2 $(git -C "$M" rev-parse "${3:-$1}")" >> "$PRS/${1//\//__}"; }   # $1 branch, $2 PR number, $3 head (default: branch tip)

q git init -q --bare "$S/origin.git"
q git init -q -b main "$S/main"; M="$S/main"
echo base > "$M/f"; q git -C "$M" add f; q git -C "$M" commit -qm base
q git -C "$M" remote add origin "$S/origin.git"; q git -C "$M" push -q -u origin main
mk(){ # $1 branch, $2 worktree path, $3 "nopush" to keep it local → branch with one commit of its own, checked out at path
  q git -C "$M" worktree add -q -b "$1" "$2" main
  commit "$2" "$1"; [[ "${3:-}" == nopush ]] || q git -C "$2" push -q -u origin "$1"; }
fresh(){ q git -C "$M" worktree add -q -b "$1" "$2" "${3:-main}"; }   # $1 branch, $2 path, $3 start point → no commits of its own
commit(){ echo "$2" > "$1/$(basename "$2")-$RANDOM"; q git -C "$1" add -A; q git -C "$1" commit -qm "$2"; }
squash(){ q git -C "$M" merge --squash "$1"; q git -C "$M" commit -qm "squash $1"; }
pushed(){ # $1 branch, $2 "empty" for no commit → the branch exists on origin only, pushed from a throwaway worktree
  local t="$S/tmp-${1//\//-}"; q git -C "$M" worktree add -q -b "$1" "$t" main; [[ "${2:-}" == empty ]] || commit "$t" "$1"
  q git -C "$t" push -q -u origin "$1"; q git -C "$M" worktree remove --force "$t"; q git -C "$M" branch -D "$1"; q git -C "$M" fetch -q origin; }
checkout(){ q git -C "$M" worktree add -q --track -b "$1" "$2" "origin/$1"; }   # $1 branch, $2 path → as worktree.sh does for a pushed branch
WT="$M/.claude/worktrees"; OLD="$S/.worktrees"; mkdir -p "$WT" "$OLD"

# worktrees created before the base advances
fresh task/behind     "$WT/task-behind"                                         # AC1: base moves on under it
fresh task/freshdirty "$WT/task-freshdirty"; echo edit >> "$WT/task-freshdirty/f"  # AC4: edit, nothing committed
fresh task/untracked  "$WT/task-untracked";  echo new > "$WT/task-untracked/new"   # untracked file only
fresh task/gonefresh  "$WT/task-gonefresh"                                      # deleted from disk below
fresh task/pulled     "$WT/task-pulled"                                         # fast-forwarded to the base below
fresh task/freshrebased "$WT/task-freshrebased"                                 # rebased onto the base below, nothing to replay
mk task/rebased       "$WT/task-rebased"                                        # rebased onto the advanced base, then merged
# the base advances
mk task/merged      "$WT/agent-merged";      q git -C "$M" merge -q --no-ff task/merged -m "merge task/merged"                      # AC2
fresh task/fromsha  "$WT/task-fromsha" "$(git -C "$M" rev-parse task/merged)"   # start point on main's second-parent side
mk task/squash      "$OLD/squash";           squash task/squash;      pr task/squash 7;      q git -C "$M" push -q origin --delete task/squash   # AC3
mk task/viaworktree "$WT/task-viaworktree";  squash task/viaworktree; pr task/viaworktree 8; q git -C "$M" push -q origin --delete task/viaworktree
mk task/squashremote "$WT/task-squashremote"; squash task/squashremote; pr task/squashremote 9                                       # remote branch left
mk task/aftersquash "$WT/task-aftersquash";  squash task/aftersquash; pr task/aftersquash 10; q git -C "$M" push -q origin --delete task/aftersquash
commit "$WT/task-aftersquash" "work after the PR was merged"
mk task/live        "$WT/agent-live"
mk task/local       "$WT/task-local" nopush
mk task/ff          "$WT/task-ff" nopush;    q git -C "$M" merge -q --ff-only task/ff
mk task/aftermerge  "$WT/task-aftermerge";   q git -C "$M" merge -q --no-ff task/aftermerge -m "merge task/aftermerge"; commit "$WT/task-aftermerge" "work after the merge"
mk task/dirty       "$WT/agent-dirty";       q git -C "$M" merge -q --no-ff task/dirty -m "merge task/dirty"; echo changed > "$WT/agent-dirty/dirty"
q git -C "$WT/task-rebased" rebase -q main; q git -C "$M" merge -q --no-ff task/rebased -m "merge task/rebased"
mk task/resetback   "$WT/task-resetback";    q git -C "$WT/task-resetback" reset -q --hard HEAD~1   # its only commit reset away
mk task/noreflog    "$WT/task-noreflog";     q git -C "$M" merge -q --no-ff task/noreflog -m "merge task/noreflog"; rm -f "$M/.git/logs/refs/heads/task/noreflog"
q git -C "$M" worktree add -q -b epic/e2 "$S/tmp-e2" main; commit "$S/tmp-e2" epic-e2; q git -C "$M" worktree remove --force "$S/tmp-e2"
fresh task/fromgoneepic "$WT/task-fromgoneepic" epic/e2                         # (a) its epic is then merged and deleted everywhere
q git -C "$M" push -q origin epic/e2; q git -C "$M" merge -q --no-ff epic/e2 -m "merge epic/e2"; q git -C "$M" branch -D epic/e2; q git -C "$M" push -q origin --delete epic/e2
q git -C "$M" worktree add -q -b fix-hot "$S/tmp-fix" main; commit "$S/tmp-fix" fix-hot; q git -C "$M" worktree remove --force "$S/tmp-fix"
fresh task/fromfix  "$WT/task-fromfix" fix-hot                                  # (b) its non-base start branch is then merged
fresh task/mergeonly "$WT/task-mergeonly"; q git -C "$WT/task-mergeonly" merge -q --no-ff --no-edit fix-hot   # its only commit is a merge commit
q git -C "$M" worktree add -q -b tmp-ren "$S/tmp-ren" main; commit "$S/tmp-ren" tmp-ren; q git -C "$M" worktree remove --force "$S/tmp-ren"
q git -C "$M" merge -q --no-ff tmp-ren -m "merge tmp-ren"; q git -C "$M" branch -m tmp-ren task/renamed; q git -C "$M" worktree add -q "$WT/task-renamed" task/renamed   # reflog carried by -m
q git -C "$M" merge -q --no-ff fix-hot -m "merge fix-hot"; q git -C "$M" merge -q --no-ff task/mergeonly -m "merge task/mergeonly"
pushed task/revmerged;       checkout task/revmerged "$WT/task-revmerged";  squash task/revmerged; pr task/revmerged 12
pushed task/revnopr;         checkout task/revnopr   "$WT/task-revnopr";    q git -C "$M" merge -q --no-ff task/revnopr -m "merge task/revnopr"
pushed task/revempty empty;  checkout task/revempty  "$WT/task-revempty"
mk task/badstatus   "$WT/task-badstatus";    q git -C "$M" merge -q --no-ff task/badstatus -m "merge task/badstatus"
printf 'not an index' > "$(git -C "$WT/task-badstatus" rev-parse --git-path index)"
mk task/locked      "$WT/agent-locked";      q git -C "$M" merge -q --no-ff task/locked -m "merge task/locked"; q git -C "$M" worktree lock "$WT/agent-locked"
mk epic/e1          "$OLD/epic-e1";          q git -C "$M" merge -q --no-ff epic/e1 -m "merge epic/e1"
fresh task/fromepic "$WT/task-fromepic" epic/e1                                 # no commits of its own on an epic base
mk task/gone        "$WT/task-gone";         q git -C "$M" merge -q --no-ff task/gone -m "merge task/gone"
mk task/current     "$WT/agent-current";     q git -C "$M" merge -q --no-ff task/current -m "merge task/current"
q git -C "$M" push -q origin main
fresh task/reused   "$WT/task-reused";       pr task/reused 11 task/squash     # a fresh branch named like an old merged PR
fresh task/atbase   "$WT/task-atbase"                                           # AC1: at the base tip
q git -C "$M" branch -c main task/copied; q git -C "$M" worktree add -q "$WT/task-copied" task/copied   # inherits main's commit entries
q git -C "$WT/task-pulled" merge -q --ff-only main; q git -C "$WT/task-freshrebased" rebase -q main
q git -C "$M" worktree add -q --detach "$WT/detached" main
q git -C "$M" worktree add -q --detach "$SCRATCH_WT" main; touch -t 202001010000 "$SCRATCH_WT"
rm -rf "$WT/task-gone" "$WT/task-gonefresh"

NOOWN='no commits of its own \(created from'
# 1. usage error
bash "$SCRIPT" --bogus >/dev/null 2>&1; ok "usage error exits 2" "[[ $? -eq 2 ]]"
# 2. dry-run touches nothing
OUT=$(cd "$M" && bash "$SCRIPT" --dry-run); rc=$?
ok "dry-run exit 0" "[[ $rc -eq 0 ]]"
ok "dry-run announces the merged worktree" "has 'would remove worktree .*agent-merged \(merged into origin/main\)'"
ok "dry-run announces the squash-merged worktree via PR" "has 'would remove worktree .*/squash \(PR #7 merged\)'"
ok "dry-run announces the worktree.sh-style squash-merged worktree via PR (AC6)" "has 'would remove worktree .*/task-viaworktree \(PR #8 merged\)'"
ok "dry-run never announces a worktree with no commits of its own (AC1)" "! has 'would remove worktree .*task-(atbase|behind|fromepic|reused|fromgoneepic|fromfix|fromsha|pulled|resetback|freshrebased|noreflog|copied|renamed|revempty|revnopr)'"
ok "dry-run summary" "has '^cleanup-merged \(dry-run\): 12 worktrees would be removed, 10 branches would be deleted, 26 kept'"
ok "dry-run leaves the directories" "[[ -d $WT/agent-merged && -d $OLD/squash && -d $WT/task-viaworktree && -d $SCRATCH_WT ]]"
ok "dry-run leaves the branches" "branch_exists task/merged && branch_exists task/squash && branch_exists task/viaworktree && branch_exists task/gone"
# 3. real run from a non-main worktree whose own branch is merged
OUT=$(cd "$WT/agent-current" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "exit 0" "[[ $rc -eq 0 ]]"
ok "current worktree kept" "has 'kept .*agent-current \(current worktree\)' && [[ -d $WT/agent-current ]]"
ok "AC1 worktree at the base tip with no commits of its own kept, with the reason" "has 'kept .*task-atbase \($NOOWN main\)\)' && [[ -d $WT/task-atbase ]] && branch_exists task/atbase"
ok "AC1 worktree left behind by an advancing base kept, with the reason" "has 'kept .*task-behind \($NOOWN main\)\)' && [[ -d $WT/task-behind ]] && branch_exists task/behind"
ok "no commits of its own on a live epic base: kept" "has 'kept .*task-fromepic \($NOOWN epic/e1\)\)' && [[ -d $WT/task-fromepic ]] && branch_exists task/fromepic"
ok "no commits of its own, named like an old merged PR: kept, gh not trusted" "has 'kept .*task-reused \($NOOWN main\)\)' && [[ -d $WT/task-reused ]] && branch_exists task/reused"
ok "AC2 merged worktree removed" "has 'removed worktree .*agent-merged \(merged into origin/main\)' && [[ ! -d $WT/agent-merged ]]"
ok "AC2 merged branch deleted" "has 'deleted branch task/merged' && ! branch_exists task/merged"
ok "AC3 squash-merged worktree removed (old layout, remote gone, PR merged)" "has 'removed worktree .*/squash \(PR #7 merged\)' && [[ ! -d $OLD/squash ]]"
ok "AC3 squash-merged branch deleted" "has 'deleted branch task/squash' && ! branch_exists task/squash"
ok "worktree.sh-style squash-merged worktree removed (AC6: discovery not limited to agent-*)" "has 'removed worktree .*/task-viaworktree \(PR #8 merged\)' && [[ ! -d $WT/task-viaworktree ]]"
ok "worktree.sh-style branch deleted" "has 'deleted branch task/viaworktree' && ! branch_exists task/viaworktree"
ok "squash-merged worktree removed while its remote branch still exists" "has 'removed worktree .*task-squashremote \(PR #9 merged\)' && ! branch_exists task/squashremote"
ok "commits made after the PR was squash-merged: kept" "has 'kept .*task-aftersquash \(commits not in merged PR #10\)' && [[ -d $WT/task-aftersquash ]] && branch_exists task/aftersquash"
ok "commits made after a merge, no PR: kept" "has 'kept .*task-aftermerge \(not merged\)' && branch_exists task/aftermerge"
ok "live worktree kept" "has 'kept .*agent-live \(not merged\)' && [[ -d $WT/agent-live ]] && branch_exists task/live"
ok "own commits never pushed: kept" "has 'kept .*task-local \(not merged\)' && branch_exists task/local"
ok "fast-forwarded into the base with no PR: removed (its reflog shows its own commit)" "has 'removed worktree .*task-ff \(merged into origin/main\)' && ! branch_exists task/ff"
ok "(a) no commits of its own, its epic merged and deleted locally and on origin: kept" "has 'kept .*task-fromgoneepic \($NOOWN epic/e2\)\)' && [[ -d $WT/task-fromgoneepic ]] && branch_exists task/fromgoneepic"
ok "(b) no commits of its own, its non-base start branch merged: kept" "has 'kept .*task-fromfix \($NOOWN fix-hot\)\)' && [[ -d $WT/task-fromfix ]] && branch_exists task/fromfix"
ok "(c) no commits of its own, created from a second-parent sha: kept" "has 'kept .*task-fromsha \($NOOWN [0-9a-f]{40}\)\)' && branch_exists task/fromsha"
ok "no commits of its own, fast-forwarded to the advanced base: kept" "has 'kept .*task-pulled \($NOOWN main\)\)' && branch_exists task/pulled"
ok "no commits of its own, rebased onto the advanced base: kept" "has 'kept .*task-freshrebased \($NOOWN main\)\)' && branch_exists task/freshrebased"
ok "only a merge commit of its own, then merged: removed" "has 'removed worktree .*task-mergeonly \(merged into origin/main\)' && ! branch_exists task/mergeonly"
ok "its only commit reset away: kept" "has 'kept .*task-resetback \($NOOWN main\)\)' && branch_exists task/resetback"
ok "copied from main with branch -c (main's reflog inherited): kept" "has 'kept .*task-copied \(reflog cannot tell whether it has commits of its own\)' && [[ -d $WT/task-copied ]] && branch_exists task/copied"
ok "renamed with branch -m from a merged branch (reflog inherited): kept" "has 'kept .*task-renamed \(reflog cannot tell whether it has commits of its own\)' && branch_exists task/renamed"
ok "rebased onto the base, then merged: removed" "has 'removed worktree .*task-rebased \(merged into origin/main\)' && ! branch_exists task/rebased"
ok "no reflog, even though merged: kept" "has 'kept .*task-noreflog \(reflog cannot tell whether it has commits of its own\)' && [[ -d $WT/task-noreflog ]] && branch_exists task/noreflog"
ok "checked out from its remote branch, PR squash-merged: removed" "has 'removed worktree .*task-revmerged \(PR #12 merged\)' && ! branch_exists task/revmerged"
ok "checked out from an empty remote branch: kept" "has 'kept .*task-revempty \(created from origin/task/revempty, no merged PR contains it\)' && branch_exists task/revempty"
ok "checked out from its remote branch, merged without a PR: kept" "has 'kept .*task-revnopr \(created from origin/task/revnopr, no merged PR contains it\)' && branch_exists task/revnopr"
ok "AC4 dirty worktree kept" "has 'kept .*agent-dirty \(dirty\)' && [[ -f $WT/agent-dirty/dirty ]] && branch_exists task/dirty"
ok "AC4 uncommitted edit with no commits of its own: kept as dirty" "has 'kept .*task-freshdirty \(dirty\)' && grep -q edit $WT/task-freshdirty/f"
ok "untracked file only: kept as dirty" "has 'kept .*task-untracked \(dirty\)' && [[ -f $WT/task-untracked/new ]]"
ok "git status failing: kept, never taken as clean" "has 'kept .*task-badstatus \(git status failed\)' && [[ -d $WT/task-badstatus ]] && branch_exists task/badstatus"
ok "locked worktree kept" "has 'kept .*agent-locked \(locked\)' && [[ -d $WT/agent-locked ]] && branch_exists task/locked"
ok "epic worktree kept without --all" "has 'kept .*epic-e1 \(protected branch epic/e1\)' && [[ -d $OLD/epic-e1 ]]"
ok "detached worktree outside /tmp kept" "has 'kept .*/detached \(detached\)' && [[ -d $WT/detached ]]"
ok "old detached scratch under /tmp removed" "has 'removed worktree .*pocket-it-cleanup-test-$$ \(detached scratch older than 24 h\)' && [[ ! -d $SCRATCH_WT ]]"
ok "missing on disk, merged: pruned and branch deleted" "has 'pruned worktree .*task-gone ' && ! branch_exists task/gone"
ok "missing on disk, no commits of its own: pruned, branch kept" "has 'pruned worktree .*task-gonefresh' && branch_exists task/gonefresh"
ok "summary line" "has '^cleanup-merged: 11 worktrees removed, 9 branches deleted, 27 kept, freed [0-9.]+ MB$'"
ok "main checkout untouched" "[[ -d $M && \$(git -C $M branch --show-current) == main ]]"
# 4. run again from main: the former current worktree goes, nothing else changes (idempotent)
OUT=$(cd "$M" && bash "$SCRIPT")
ok "former current worktree removed on the next run" "has 'removed worktree .*agent-current \(merged into origin/main\)' && ! branch_exists task/current"
ok "second run summary" "has '^cleanup-merged: 1 worktrees removed, 1 branches deleted, 26 kept'"
OUT=$(cd "$M" && bash "$SCRIPT")
ok "third run is a no-op" "has '^cleanup-merged: 0 worktrees removed, 0 branches deleted, 26 kept, freed 0.0 MB$'"
# 5. --all also cleans the merged epic branch, and still keeps everything with work in it
OUT=$(cd "$M" && bash "$SCRIPT" --all)
ok "--all removes the merged epic worktree" "has 'removed worktree .*epic-e1 \(merged into origin/main\)' && [[ ! -d $OLD/epic-e1 ]] && ! branch_exists epic/e1"
ok "--all still keeps live, dirty, locked" "has 'kept .*agent-live \(not merged\)' && has 'kept .*agent-dirty \(dirty\)' && has 'kept .*agent-locked \(locked\)'"
ok "--all still keeps worktrees with no commits of its own" "has 'kept .*task-atbase \($NOOWN' && has 'kept .*task-behind \($NOOWN' && has 'kept .*task-fromepic \($NOOWN' && has 'kept .*task-fromgoneepic \($NOOWN' && has 'kept .*task-noreflog'"
ok "worktree list is consistent" "[[ \$(git -C $M worktree list | wc -l | tr -d ' ') -eq 26 ]]"
exit $fail
