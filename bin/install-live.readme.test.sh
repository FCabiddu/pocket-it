#!/usr/bin/env bash
# Executes the README "Switching an existing setup" blocks verbatim against a scratch HOME, so the procedure is
# proven by running it, not by reading it. Fixture: ~/.claude/agents is a link to a folder that contains the
# development checkout (parent-link) and a .git of its own; the guard hook is spelled with $HOME; an end-of-turn
# hook runs a script outside the checkout that checks the checkout for uncommitted work; another hook names the
# checkout inside bash -c; a re-linker script in that folder names the checkout with ~/.
# Covers: step 3 rewrites a $HOME-spelled path and makes the guard fail-closed; step 5 does not link .git; steps
# 5b/6 list the names that step 3 cannot rewrite and step 6 does not end in a plain ALL OK while they remain;
# step 6 fails on a guard without "|| exit 2"; a missing guard file blocks; Rollback works with the installed
# copy deleted. README path overridable with README=… (used by mutation runs).
cd "$(dirname "$0")"
ROOT=$(cd .. && pwd -P)
README="${README:-$ROOT/README.md}"
S=$(mktemp -d "${TMPDIR:-/tmp}/install-live-readme-test.XXXXXX"); S=$(cd "$S" && pwd -P)
cleanup(){ [[ -n "${KEEP:-}" ]] || rm -rf "$S"; }
trap cleanup EXIT
fail=0
ok(){ if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
q(){ "$@" >/dev/null 2>&1; }

H="$S/home"; HUB="$H/work/agents"; DEV="$HUB/pocket-it"; LIVE="$H/.claude/pocket-it-live"
mkdir -p "$H/.claude" "$HUB/jarvis" "$HUB/bin" "$S/pub"
# the published repository: a snapshot of this repo's tracked files as they are now
( cd "$ROOT" && git ls-files -z | xargs -0 tar -cf - ) | tar -xf - -C "$S/pub"
q git init -q -b main "$S/pub"; q git -C "$S/pub" add -A; q git -C "$S/pub" commit -qm published
q git init -q --bare -b main "$S/origin.git"; q git -C "$S/pub" push -q "$S/origin.git" main
q git clone -q "$S/origin.git" "$DEV"; q git -C "$DEV" worktree add -q "$DEV/.claude/worktrees/task-x" -b task/x
q git init -q "$HUB"; echo jarvis > "$HUB/jarvis/SKILL.md"
printf '%s\n' '#!/usr/bin/env bash' "git -C $DEV status --porcelain" > "$HUB/bin/stop-check.sh"
printf '%s\n' '#!/usr/bin/env bash' 'for s in ~/work/agents/pocket-it/.claude/skills/*/; do ln -sfn "$s" ~/.claude/skills/; done' > "$HUB/relink.sh"
ln -s "$HUB" "$H/.claude/agents"
mkdir -p "$H/.claude/skills"; for s in "$DEV"/.claude/skills/*/; do ln -s "${s%/}" "$H/.claude/skills/$(basename "$s")"; done
ln -s "$HUB/jarvis" "$H/.claude/skills/jarvis"
cat > "$H/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "bash $HOME/work/agents/pocket-it/.claude/hooks/guard.sh" } ] } ],
    "Stop": [ { "hooks": [ { "type": "command", "command": "bash ~/work/agents/bin/stop-check.sh" } ] } ],
    "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "bash -c 'test -d $HOME/work/agents/pocket-it/.git'" } ] } ]
  }
}
JSON

mkdir -p "$S/blocks"
python3 - "$README" "$S/blocks" "$DEV" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
for m in re.finditer(r"^\*\*(Step \w+|Rollback)\b[^\n]*\n\n```bash\n(.*?)```", s, re.S | re.M):
    body = m.group(2).replace("/ABS/PATH/OF/THE/DEVELOPMENT/CHECKOUT", sys.argv[3])
    open(sys.argv[2] + "/" + m.group(1).replace(" ", "_") + ".sh", "w").write(body)
PY
step(){ OUT=$(HOME="$H" bash "$S/blocks/$1.sh" 2>&1); RC=$?; }
hookcmd(){ HOME="$H" python3 -c 'import json,os,sys; s=json.load(open(os.path.expanduser("~/.claude/settings.json"))); print(s["hooks"][sys.argv[1]][0]["hooks"][0]["command"])' "$1"; }
KILL='{"tool_name":"Bash","tool_input":{"command":"killall node"}}'

ok "blocks extracted from the README" "[[ -f $S/blocks/Step_0.sh && -f $S/blocks/Step_5b.sh && -f $S/blocks/Step_6.sh && -f $S/blocks/Rollback.sh ]]"
for st in Step_0 Step_1 Step_2 Step_3; do step $st; ok "$st exits 0" "[[ $RC -eq 0 ]]"; done
S3="$OUT"
G=$(hookcmd PreToolUse)
ok "step 3: a \$HOME-spelled guard path is rewritten into the installed copy" "[[ \"\$G\" == \"bash $LIVE/.claude/hooks/guard.sh || exit 2\" ]]"
ok "step 3: a path inside bash -c is flagged, not silently skipped" "grep -q '^FLAG' <<<\"\$S3\""
for st in Step_4 Step_5 Step_5b; do step $st; ok "$st exits 0" "[[ $RC -eq 0 ]]"; done
S5B="$OUT"
ok "step 5: ~/.claude/agents is not a git checkout (no linked .git)" "! HOME=$H git -C $H/.claude/agents rev-parse --git-dir >/dev/null 2>&1 && [[ ! -e $H/.claude/agents/.git ]]"
ok "step 5: the other entries of the folder are still reachable" "[[ -f $H/.claude/agents/jarvis/SKILL.md && -f $H/.claude/agents/relink.sh ]]"
ok "step 5b: lists a hook script outside the checkout that reads the checkout" "grep -q 'stop-check.sh' <<<\"\$S5B\""
ok "step 5b: lists the checkout named inside bash -c in settings" "grep -q 'settings.json.*bash -c' <<<\"\$S5B\""
ok "step 5b: lists a skill re-linker that names the checkout with ~/" "grep -q 'relink.sh' <<<\"\$S5B\""

step Step_6; S6="$OUT"
ok "step 6: no FAIL" "! grep -q '^FAIL' <<<\"\$S6\""
ok "step 6: does not say a plain ALL OK while names of the checkout remain" "! grep -q '^ALL OK' <<<\"\$S6\" && grep -q '^ALL CHECKS OK — and 3 line(s)' <<<\"\$S6\""
ok "step 6: checks the guard is fail-closed and that a missing guard blocks" "grep -q '^OK    guard hook is fail-closed' <<<\"\$S6\" && grep -q '^OK    a missing guard file blocks' <<<\"\$S6\""

# the fail-closed hook, measured: with the installed copy gone, the configured command blocks
mv "$LIVE" "$LIVE.away"
printf '%s' "$KILL" | HOME="$H" bash -c "$(hookcmd PreToolUse)" >/dev/null 2>&1; rc=$?
ok "hook with the installed copy missing blocks (exit 2, got $rc)" "[[ $rc -eq 2 ]]"
mv "$LIVE.away" "$LIVE"

# step 6 must catch a guard hook that is not fail-closed
cp "$H/.claude/settings.json" "$S/settings.keep"
HOME="$H" python3 -c 'import json,os; p=os.path.expanduser("~/.claude/settings.json"); s=json.load(open(p)); h=s["hooks"]["PreToolUse"][0]["hooks"][0]; h["command"]=h["command"].replace(" || exit 2",""); json.dump(s,open(p,"w"))'
step Step_6
ok "step 6: FAILs on a guard hook without || exit 2" "grep -q '^FAIL  guard hook is fail-closed' <<<\"\$OUT\" && grep -q '^FAIL  a missing guard file blocks' <<<\"\$OUT\""
cp "$S/settings.keep" "$H/.claude/settings.json"

# Rollback with the installed copy deleted: the hook must still go back to the checkout, fail-closed
rm -rf "$LIVE"
step Rollback
G=$(hookcmd PreToolUse)
ok "rollback with the installed copy deleted exits 0" "[[ $RC -eq 0 ]]"
ok "rollback with the installed copy deleted: guard hook back on the checkout" "[[ \"\$G\" == \"bash $DEV/.claude/hooks/guard.sh || exit 2\" ]]"
printf '%s' "$KILL" | HOME="$H" bash -c "$G" >/dev/null 2>&1; rc=$?
ok "rollback with the installed copy deleted: the guard blocks (exit 2, got $rc)" "[[ $rc -eq 2 ]]"
ok "rollback: ~/.claude/agents is the link to the folder again, skills on the checkout" "[[ -L $H/.claude/agents && \$(readlink $H/.claude/agents) == $HUB && \$(readlink $H/.claude/skills/developer) == $DEV/.claude/skills/developer ]]"

exit $fail
