#!/usr/bin/env bash
# Self-test for cleanup-merged.sh against a scratch repo: a fake origin with a merged branch, a squash-merged
# branch (remote deleted, PR reported merged by a fake gh), a squash-merged branch at a worktree.sh-style path
# (<repo>/.claude/worktrees/<branch-slug>, no agent- prefix — AC6), a live branch, a dirty worktree, a locked
# worktree, a protected epic branch, an old detached scratch worktree under /tmp, and the current worktree.
cd "$(dirname "$0")"
SCRIPT="$PWD/cleanup-merged.sh"
S=$(mktemp -d "${TMPDIR:-/tmp}/cleanup-merged-test.XXXXXX")
SCRATCH_WT="/tmp/pocket-it-cleanup-test-$$"
cleanup(){ rm -rf "$S" "$SCRATCH_WT"; }
trap cleanup EXIT
fail=0
ok(){ if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
has(){ grep -qE "$1" <<<"$OUT"; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
q(){ "$@" >/dev/null 2>&1; }
# fake gh: only the squash-merged branches have a merged PR
mkdir -p "$S/bin"; cat > "$S/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$*" in
  *"--head task/squash"*)      case "$*" in *--jq*) echo 7;; *) echo '[{"number":7}]';; esac;;
  *"--head task/viaworktree"*) case "$*" in *--jq*) echo 8;; *) echo '[{"number":8}]';; esac;;
  *) case "$*" in *--jq*) echo null;; *) echo '[]';; esac;;
esac
GH
chmod +x "$S/bin/gh"; export PATH="$S/bin:$PATH"

q git init -q --bare "$S/origin.git"
q git init -q -b main "$S/main"; M="$S/main"
echo base > "$M/f"; q git -C "$M" add f; q git -C "$M" commit -qm base
q git -C "$M" remote add origin "$S/origin.git"; q git -C "$M" push -q -u origin main
mk(){ # $1 branch, $2 worktree path → branch with one pushed commit, checked out at path
  q git -C "$M" worktree add -q -b "$1" "$2" main
  echo "$1" > "$2/$(basename "$1")"; q git -C "$2" add -A; q git -C "$2" commit -qm "$1"; q git -C "$2" push -q -u origin "$1"; }
WT="$M/.claude/worktrees"; OLD="$S/.worktrees"; mkdir -p "$WT" "$OLD"
mk task/merged      "$WT/agent-merged";      q git -C "$M" merge -q --no-ff task/merged -m "merge task/merged"
mk task/squash      "$OLD/squash";           q git -C "$M" merge --squash task/squash; q git -C "$M" commit -qm "squash task/squash"; q git -C "$M" push -q origin --delete task/squash
mk task/viaworktree "$WT/task-viaworktree";  q git -C "$M" merge --squash task/viaworktree; q git -C "$M" commit -qm "squash task/viaworktree"; q git -C "$M" push -q origin --delete task/viaworktree
mk task/live    "$WT/agent-live"
mk task/dirty   "$WT/agent-dirty";   q git -C "$M" merge -q --no-ff task/dirty -m "merge task/dirty"; echo changed > "$WT/agent-dirty/dirty"
mk task/locked  "$WT/agent-locked";  q git -C "$M" merge -q --no-ff task/locked -m "merge task/locked"; q git -C "$M" worktree lock "$WT/agent-locked"
mk epic/e1      "$OLD/epic-e1";      q git -C "$M" merge -q --no-ff epic/e1 -m "merge epic/e1"
mk task/current "$WT/agent-current"; q git -C "$M" merge -q --no-ff task/current -m "merge task/current"
q git -C "$M" push -q origin main
q git -C "$M" worktree add -q --detach "$SCRATCH_WT" main; touch -t 202001010000 "$SCRATCH_WT"

# 1. usage error
bash "$SCRIPT" --bogus >/dev/null 2>&1; ok "usage error exits 2" "[[ $? -eq 2 ]]"
# 2. dry-run touches nothing
OUT=$(cd "$M" && bash "$SCRIPT" --dry-run); rc=$?
ok "dry-run exit 0" "[[ $rc -eq 0 ]]"
ok "dry-run announces the merged worktree" "has 'would remove worktree .*agent-merged \(merged into origin/main\)'"
ok "dry-run announces the squash-merged worktree via PR" "has 'would remove worktree .*/squash \(PR #7 merged\)'"
ok "dry-run announces the worktree.sh-style squash-merged worktree via PR (AC6)" "has 'would remove worktree .*/task-viaworktree \(PR #8 merged\)'"
ok "dry-run summary" "has '^cleanup-merged \(dry-run\): 5 worktrees would be removed, 4 branches would be deleted'"
ok "dry-run leaves the directories" "[[ -d $WT/agent-merged && -d $OLD/squash && -d $WT/task-viaworktree && -d $SCRATCH_WT ]]"
ok "dry-run leaves the branches" "q git -C $M rev-parse --verify task/merged && q git -C $M rev-parse --verify task/squash && q git -C $M rev-parse --verify task/viaworktree"
# 3. real run from a non-main worktree whose own branch is merged
OUT=$(cd "$WT/agent-current" && bash "$SCRIPT"); rc=$?
echo "$OUT" | sed 's/^/      | /'
ok "exit 0" "[[ $rc -eq 0 ]]"
ok "current worktree kept" "has 'kept .*agent-current \(current worktree\)' && [[ -d $WT/agent-current ]]"
ok "merged worktree removed" "has 'removed worktree .*agent-merged \(merged into origin/main\)' && [[ ! -d $WT/agent-merged ]]"
ok "merged branch deleted" "has 'deleted branch task/merged' && ! q git -C $M rev-parse --verify task/merged"
ok "squash-merged worktree removed (old layout, remote gone, PR merged)" "has 'removed worktree .*/squash \(PR #7 merged\)' && [[ ! -d $OLD/squash ]]"
ok "squash-merged branch deleted" "has 'deleted branch task/squash' && ! q git -C $M rev-parse --verify task/squash"
ok "worktree.sh-style squash-merged worktree removed (AC6: discovery not limited to agent-*)" "has 'removed worktree .*/task-viaworktree \(PR #8 merged\)' && [[ ! -d $WT/task-viaworktree ]]"
ok "worktree.sh-style branch deleted" "has 'deleted branch task/viaworktree' && ! q git -C $M rev-parse --verify task/viaworktree"
ok "live worktree kept" "has 'kept .*agent-live \(not merged\)' && [[ -d $WT/agent-live ]] && q git -C $M rev-parse --verify task/live"
ok "dirty worktree kept" "has 'kept .*agent-dirty \(dirty\)' && [[ -f $WT/agent-dirty/dirty ]] && q git -C $M rev-parse --verify task/dirty"
ok "locked worktree kept" "has 'kept .*agent-locked \(locked\)' && [[ -d $WT/agent-locked ]] && q git -C $M rev-parse --verify task/locked"
ok "epic worktree kept without --all" "has 'kept .*epic-e1 \(protected branch epic/e1\)' && [[ -d $OLD/epic-e1 ]]"
ok "old detached scratch under /tmp removed" "has 'removed worktree .*pocket-it-cleanup-test-$$ \(detached scratch older than 24 h\)' && [[ ! -d $SCRATCH_WT ]]"
ok "summary line" "has '^cleanup-merged: 4 worktrees removed, 3 branches deleted, 5 kept, freed [0-9.]+ MB$'"
ok "main checkout untouched" "[[ -d $M && \$(git -C $M branch --show-current) == main ]]"
# 4. run again from main: the former current worktree goes, nothing else changes (idempotent)
OUT=$(cd "$M" && bash "$SCRIPT")
ok "former current worktree removed on the next run" "has 'removed worktree .*agent-current \(merged into origin/main\)' && ! q git -C $M rev-parse --verify task/current"
ok "second run summary" "has '^cleanup-merged: 1 worktrees removed, 1 branches deleted, 4 kept'"
OUT=$(cd "$M" && bash "$SCRIPT")
ok "third run is a no-op" "has '^cleanup-merged: 0 worktrees removed, 0 branches deleted, 4 kept, freed 0.0 MB$'"
# 5. --all also cleans the merged epic branch
OUT=$(cd "$M" && bash "$SCRIPT" --all)
ok "--all removes the merged epic worktree" "has 'removed worktree .*epic-e1 \(merged into origin/main\)' && [[ ! -d $OLD/epic-e1 ]] && ! q git -C $M rev-parse --verify epic/e1"
ok "--all still keeps live, dirty, locked" "has 'kept .*agent-live \(not merged\)' && has 'kept .*agent-dirty \(dirty\)' && has 'kept .*agent-locked \(locked\)'"
ok "worktree list is consistent" "[[ \$(git -C $M worktree list | wc -l | tr -d ' ') -eq 4 ]]"
exit $fail
