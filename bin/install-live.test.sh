#!/usr/bin/env bash
# Self-test for install-live.sh on a scratch setup: a bare "published" origin, a publisher clone that pushes to
# it, and a development clone that runs the script under test (copied into the published tree, as in real use).
# Covers: usage errors; AC1 first install from the published branch only, and refusal of a checkout as remote;
# AC2 uncommitted, untracked and unpushed development changes never reach the installed copy, on first install
# and on update; AC3 fast-forward, idempotent re-run, refusal on local modifications (tracked and untracked),
# local commits, a rewritten published branch, a wrong branch, a development checkout as destination, and a
# published commit that fails validation — each refusal leaving the installed copy untouched; AC5 the
# when-to-run line on help and on every successful run.
cd "$(dirname "$0")"
SCRIPT="$PWD/install-live.sh"
S=$(mktemp -d "${TMPDIR:-/tmp}/install-live-test.XXXXXX"); S=$(cd "$S" && pwd -P)
cleanup(){ rm -rf "$S"; }
trap cleanup EXIT
fail=0
ok(){ if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
unset POCKET_IT_LIVE
q(){ "$@" >/dev/null 2>&1; }

# a guard with the real contract: exit 2 blocks a forbidden command, exit 0 allows the rest
guard_src(){ printf '%s\n' '#!/usr/bin/env bash' "# $1" 'in=$(cat)' 'case "$in" in *killall*) exit 2;; esac' 'exit 0'; }
GUARD_V1=$(guard_src guard-v1)
O="$S/origin.git"; P="$S/publisher"; D="$S/dev"; L="$S/live"
q git init -q --bare -b main "$O"
q git init -q -b main "$P"
mkdir -p "$P/.claude/hooks" "$P/.claude/agents" "$P/.claude/skills/s" "$P/bin"
printf '%s\n' "$GUARD_V1" > "$P/.claude/hooks/guard.sh"
echo "agent v1" > "$P/.claude/agents/developer.md"
echo "skill v1" > "$P/.claude/skills/s/SKILL.md"
cp "$SCRIPT" "$P/bin/install-live.sh"
q git -C "$P" add -A; q git -C "$P" commit -qm v1
q git -C "$P" remote add origin "$O"; q git -C "$P" push -q -u origin main
publish(){ # publish <file> <content> <message>
  printf '%s\n' "$2" > "$P/$1"; q git -C "$P" add -A; q git -C "$P" commit -qm "$3"; q git -C "$P" push -q origin main
}
q git clone -q "$O" "$D"
run(){ OUT=$(bash "$D/bin/install-live.sh" "$@" 2>&1); RC=$?; }
tree_of(){ git -C "$1" rev-parse HEAD 2>/dev/null; }

# 1. usage errors — nothing created
run --bogus;             ok "unknown argument exits 2" "[[ $RC -eq 2 ]]"
run --dest;              ok "--dest without a value exits 2" "[[ $RC -eq 2 && ! -e $L ]]"

# 2. AC5 — help says when to run
run --help
ok "AC5 help says to run after every merge into the base branch" "grep -q 'after every merge into the base branch' <<<\"\$OUT\""

# 3. AC1 — a checkout given as remote is refused, nothing is created
run --dest "$S/live-from-dev" --remote "$D"
ok "AC1 local checkout as remote exits 1" "[[ $RC -eq 1 ]]"
ok "AC1 local checkout as remote: says it is not a published repository" "grep -q 'not a published repository' <<<\"\$OUT\""
ok "AC1 local checkout as remote: nothing created" "[[ ! -e $S/live-from-dev && -z \$(ls -d $S/live-from-dev.installing.* 2>/dev/null) ]]"

# 4. AC2 on first install — the development checkout is dirty in every way, the published branch is not
echo "skill DEV-UNPUSHED" > "$D/.claude/skills/s/SKILL.md"; q git -C "$D" commit -qm "unpushed dev commit" -- .claude/skills/s/SKILL.md
guard_src guard-DEV-UNCOMMITTED > "$D/.claude/hooks/guard.sh"
echo "untracked dev agent" > "$D/.claude/agents/untracked-dev.md"
ok "setup: development checkout has an uncommitted hook, an untracked agent and an unpushed commit" "[[ -n \$(git -C $D diff --name-only -- .claude/hooks/guard.sh) && -n \$(git -C $D ls-files --others -- .claude/agents) && \$(git -C $D rev-list --count origin/main..main) -eq 1 ]]"
PUBLISHED_V1=$(tree_of "$P")
run --dest "$L"
ok "AC1 first install exits 0" "[[ $RC -eq 0 ]]"
ok "AC1 installed copy is at the published main commit" "[[ \$(tree_of $L) == $PUBLISHED_V1 ]]"
ok "AC1 installed copy is on main and its origin is the published repository" "[[ \$(git -C $L branch --show-current) == main && \$(git -C $L remote get-url origin) == $O ]]"
ok "AC2 first install: uncommitted development hook change did not arrive" "grep -q guard-v1 $L/.claude/hooks/guard.sh && ! grep -q DEV $L/.claude/hooks/guard.sh"
ok "AC2 first install: untracked development agent did not arrive" "[[ ! -e $L/.claude/agents/untracked-dev.md ]]"
ok "AC2 first install: unpushed development skill commit did not arrive" "grep -qx 'skill v1' $L/.claude/skills/s/SKILL.md"
ok "AC5 first install says when to run again" "grep -q 'after every merge into main' <<<\"\$OUT\""

# 5. AC3 — idempotent re-run
run --dest "$L"
ok "AC3 re-run with nothing published exits 0 and says up to date" "[[ $RC -eq 0 ]] && grep -q 'already up to date' <<<\"\$OUT\""

# 6. AC3 + AC2 on update — a published change fast-forwards; development changes still do not arrive
publish .claude/agents/developer.md "agent v2" v2
PUBLISHED_V2=$(tree_of "$P")
run --dest "$L"
ok "AC3 published update exits 0" "[[ $RC -eq 0 ]]"
ok "AC3 installed copy fast-forwarded to the published commit" "[[ \$(tree_of $L) == $PUBLISHED_V2 ]] && grep -qx 'agent v2' $L/.claude/agents/developer.md"
ok "AC3 update reports old and new commits" "grep -q \"updated .*${PUBLISHED_V1:0:7} → ${PUBLISHED_V2:0:7}\" <<<\"\$OUT\""
ok "AC2 update: development hook, agent and skill changes did not arrive" "grep -q guard-v1 $L/.claude/hooks/guard.sh && [[ ! -e $L/.claude/agents/untracked-dev.md ]] && grep -qx 'skill v1' $L/.claude/skills/s/SKILL.md"
ok "AC5 update says when to run again" "grep -q 'after every merge into main' <<<\"\$OUT\""

# 7. AC3 — local modification of a tracked file in the installed copy: refused, not overwritten
publish .claude/agents/developer.md "agent v3" v3
echo "hand edit" >> "$L/.claude/hooks/guard.sh"
run --dest "$L"
ok "AC3 tracked local modification exits 1" "[[ $RC -eq 1 ]]"
ok "AC3 tracked local modification: says so" "grep -q 'has local modifications' <<<\"\$OUT\""
ok "AC3 tracked local modification: copy not moved and edit not overwritten" "[[ \$(tree_of $L) == $PUBLISHED_V2 ]] && grep -q 'hand edit' $L/.claude/hooks/guard.sh"
q git -C "$L" checkout -- .claude/hooks/guard.sh

# 8. AC3 — an untracked file in the installed copy (e.g. a stray agent) is a local modification too
echo stray > "$L/.claude/agents/stray.md"
run --dest "$L"
ok "AC3 untracked file exits 1 and says so, copy not moved" "[[ $RC -eq 1 && \$(tree_of $L) == $PUBLISHED_V2 ]] && grep -q 'has local modifications' <<<\"\$OUT\""
rm "$L/.claude/agents/stray.md"

# 9. AC3 — a published commit that fails validation is refused; the last working copy stays
publish .claude/hooks/guard.sh 'if then' "broken guard"
BROKEN=$(tree_of "$P")
run --dest "$L"
ok "AC3 published commit with a broken hook exits 1" "[[ $RC -eq 1 ]]"
ok "AC3 broken hook: says which file fails validation" "grep -q 'syntax:.claude/hooks/guard.sh' <<<\"\$OUT\""
ok "AC3 broken hook: installed copy stays at the last working commit" "[[ \$(tree_of $L) == $PUBLISHED_V2 ]] && bash -n $L/.claude/hooks/guard.sh"
run --dest "$S/live-broken"
ok "AC3 broken hook on first install: exits 1 and creates nothing" "[[ $RC -eq 1 && ! -e $S/live-broken && -z \$(ls -d $S/live-broken.installing.* 2>/dev/null) ]]"

# 9b. a published guard that parses but answers wrongly is refused before it can go live
publish .claude/hooks/guard.sh "$(printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' 'exit 0')" "guard that lets everything through"
run --dest "$L"
ok "guard check: a published guard that does not block exits 1, says so, copy untouched" "[[ $RC -eq 1 && \$(tree_of $L) == $PUBLISHED_V2 ]] && grep -q 'guard-does-not-block' <<<\"\$OUT\""
publish .claude/hooks/guard.sh "$(printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' 'exit 2')" "guard that blocks everything"
run --dest "$L"
ok "guard check: a published guard that blocks everything (lock-out) exits 1, says so, copy untouched" "[[ $RC -eq 1 && \$(tree_of $L) == $PUBLISHED_V2 ]] && grep -q 'guard-blocks-harmless-command' <<<\"\$OUT\""
run --dest "$L" --rebuild
ok "guard check: --rebuild never skips the checks on the new copy" "[[ $RC -eq 1 && \$(tree_of $L) == $PUBLISHED_V2 ]]"
publish .claude/hooks/guard.sh "$GUARD_V1" "guard restored"

# 10. AC3 — the published branch rewritten (not a fast-forward): refused, copy untouched
q git -C "$P" reset -q --hard "$PUBLISHED_V1"
publish .claude/agents/developer.md "agent REWRITTEN" rewritten; q git -C "$P" push -q --force origin main
run --dest "$L"
ok "AC3 rewritten published branch exits 1" "[[ $RC -eq 1 ]]"
ok "AC3 rewritten published branch: says not a fast-forward" "grep -q 'not a fast-forward' <<<\"\$OUT\""
ok "AC3 rewritten published branch: copy untouched" "[[ \$(tree_of $L) == $PUBLISHED_V2 ]] && grep -qx 'agent v2' $L/.claude/agents/developer.md"

# 10b. --rebuild replaces a drifted copy through the same swap and keeps the drifted one aside
echo "hand edit" >> "$L/.claude/agents/developer.md"
run --dest "$L" --rebuild
ASIDE=$(ls -d "$L".drifted-* 2>/dev/null | head -1)
ok "--rebuild of a drifted copy exits 0 and lands on the published main" "[[ $RC -eq 0 && \$(tree_of $L) == \$(tree_of $P) && -z \$(git -C $L status --porcelain) ]]"
ok "--rebuild keeps the drifted copy aside, with its edit" "[[ -n \"$ASIDE\" ]] && grep -q 'hand edit' \"$ASIDE/.claude/agents/developer.md\""
PUBLISHED_V2=$(tree_of "$L")

# 11. AC3 — a commit made inside the installed copy: refused, not a fast-forward
L2="$S/live2"; run --dest "$L2"
echo local > "$L2/.claude/agents/local.md"; q git -C "$L2" add -A; q git -C "$L2" commit -qm "local commit"
LOCAL=$(tree_of "$L2")
publish .claude/agents/developer.md "agent v4" v4
run --dest "$L2"
ok "AC3 local commit in the installed copy exits 1, says not a fast-forward, copy untouched" "[[ $RC -eq 1 && \$(tree_of $L2) == $LOCAL ]] && grep -q 'not a fast-forward' <<<\"\$OUT\""

# 12. AC3 — wrong branch and a development checkout as destination are refused
L3="$S/live3"; run --dest "$L3"; q git -C "$L3" checkout -q -b other
run --dest "$L3"
ok "installed copy on another branch: exits 1 and says so" "[[ $RC -eq 1 ]] && grep -q 'not on main' <<<\"\$OUT\""
q git -C "$D" stash -u; q git -C "$D" reset -q --hard origin/main; q git -C "$D" worktree add -q "$S/dev-wt" -b task/x
run --dest "$D"
ok "development checkout with linked worktrees as destination: exits 1 and says so" "[[ $RC -eq 1 ]] && grep -q 'development checkout' <<<\"\$OUT\""
run --dest "$S/dev-wt"
ok "linked worktree as destination: exits 1 and says so" "[[ $RC -eq 1 ]] && grep -q 'linked worktree' <<<\"\$OUT\""
run --dest "$D" --rebuild
ok "--rebuild on a development checkout: exits 1, nothing moved" "[[ $RC -eq 1 && -d $D/.git && -z \$(ls -d $D.drifted-* 2>/dev/null) ]]"

# 13. a symlink to the installed copy as destination updates the copy it points to
L4="$S/live4"; run --dest "$L4"; ln -s "$L4" "$S/live4-link"
publish .claude/agents/developer.md "agent v5" v5
run --dest "$S/live4-link"
ok "symlink as destination: exits 0 and the target copy is updated" "[[ $RC -eq 0 && -L $S/live4-link ]] && grep -qx 'agent v5' $L4/.claude/agents/developer.md"

# 14. the hook never finds guard.sh missing while updates run: a probe calls the installed guard with a forbidden
# command in a loop across repeated updates, and every single answer must be exit 2 (a missing file gives 127,
# and 127 lets the command through). An update in place, or a remove-then-rename, turns this red.
L5="$S/live5"; run --dest "$L5"
STOP="$S/probe.stop"; BADS="$S/probe.bad"; COUNT="$S/probe.count"; : > "$BADS"; : > "$COUNT"
( while [[ ! -e "$STOP" ]]; do
    printf '%s' '{"tool_input":{"command":"killall node"}}' | bash "$L5/.claude/hooks/guard.sh" >/dev/null 2>&1
    rc=$?; echo . >> "$COUNT"; [[ $rc -eq 2 ]] || echo "$rc" >> "$BADS"
  done ) &
PROBE=$!
# the same failure seen more finely: a fork-free loop that only asks whether guard.sh is there to be read
MISS="$S/probe.miss"; : > "$MISS"
( n=0; while [[ ! -e "$STOP" ]]; do [[ -r "$L5/.claude/hooks/guard.sh" ]] || echo miss >> "$MISS"; n=$((n+1)); done; echo "$n" > "$S/probe.fast" ) &
FAST=$!
UPD_FAIL=0
for i in $(seq 1 25); do
  printf '%s\n' "$(guard_src "guard-round-$i")" "# filler $i $(head -c 20000 /dev/zero | tr '\0' x)" > "$P/.claude/hooks/guard.sh"
  q git -C "$P" commit -qam "round $i"; q git -C "$P" push -q origin main
  run --dest "$L5"; [[ $RC -eq 0 ]] || UPD_FAIL=1
done
touch "$STOP"; wait "$PROBE" "$FAST"
ok "atomic swap: 25 updates all succeeded" "[[ $UPD_FAIL -eq 0 ]] && grep -q guard-round-25 $L5/.claude/hooks/guard.sh"
ok "atomic swap: zero guard runs without exit 2 across $(wc -l < "$COUNT" | tr -d ' ') probes (got $(wc -l < "$BADS" | tr -d ' '))" "[[ \$(wc -l < $COUNT) -gt 100 && ! -s $BADS ]]"
ok "atomic swap: guard.sh never absent across $(cat "$S/probe.fast") fork-free reads (missing $(wc -l < "$MISS" | tr -d ' '))" "[[ \$(cat $S/probe.fast) -gt 1000 && ! -s $MISS ]]"
ok "atomic swap: no leftover next/old copies beside the installed one" "[[ -z \$(ls -d $L5.next.* 2>/dev/null) ]]"

exit $fail
