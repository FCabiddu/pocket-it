#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Deterministically blocks the commands the pocket-it
# agents are told never to run, so the rule no longer has to live in every prompt.
# Register in ~/.claude/settings.json → hooks.PreToolUse. Exit 2 = block, message on stderr.
set -uo pipefail
INPUT=$(cat)
# Match against the command with heredoc bodies and quoted strings removed, so a commit
# message or an echo that *mentions* a blocked command is not a false positive.
CMD=$(printf '%s' "$INPUT" | python3 -c 'import json,sys,re
try:
    d=json.load(sys.stdin); c=d.get("tool_input",{}).get("command","")
except Exception:
    c=""
c=re.sub(r"<<-?\s*[\x27\"]?(\w+)[\x27\"]?[^\n]*\n.*?\n\s*\1\s*(?=\n|$)", " HEREDOC ", c, flags=re.S)
c=re.sub(r"\"(?:[^\"\\\\]|\\\\.)*\"", " STR ", c)
c=re.sub(r"\x27[^\x27]*\x27", " STR ", c)
print(c)' 2>/dev/null)
[[ -z "$CMD" ]] && exit 0

block() { echo "BLOCKED by pocket-it guard: $1. $2" >&2; exit 2; }

# Merges are user-triggered only.
grep -qE '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+merge\b' <<<"$CMD" && block "gh pr merge" "Only the user merges. Report the PR as ready instead."
# No direct pushes to main/master (feature branches are fine).
grep -qE 'git[[:space:]]+push([[:space:]]+-[-a-zA-Z]+)*[[:space:]]+\S+[[:space:]]+(main|master)([[:space:]]|$|:)' <<<"$CMD" && block "git push to main/master" "Push a task branch and open a draft PR."
grep -qE 'git[[:space:]]+push([[:space:]]+-[-a-zA-Z]+)*[[:space:]]+(origin[[:space:]]+)?(HEAD:)?(main|master)([[:space:]]|$)' <<<"$CMD" && block "git push to main/master" "Push a task branch and open a draft PR."
# Never kill by pattern on a shared machine.
grep -qE '(^|[;&|[:space:]])(pkill|killall)\b' <<<"$CMD" && block "pkill/killall" "Kill your own process by PID or by port: lsof -nP -iTCP:PORT -sTCP:LISTEN -t | xargs -r kill."
# CI budget switch is a human decision.
grep -qE 'gh[[:space:]]+variable[[:space:]]+set[[:space:]]+APP_STATUS.*prod' <<<"$CMD" && block "APP_STATUS → prod" "Turning hosted CI on is the user's call (initialising it to dev is fine)."
# Sleep-and-poll chains are blocked by the harness anyway; fail fast with a hint.
grep -qE '^[[:space:]]*(cd [^;&]+ (&&|;) *)?sleep[[:space:]]+[0-9]+[[:space:]]*(&&|;)' <<<"$CMD" && block "sleep N && …" "Use 'gh pr checks N --watch' or a bounded until-loop (sleep inside a loop body is fine)."
# Destructive git on shared history.
grep -qE 'git[[:space:]]+push[[:space:]]+.*(--force|-f)\b.*(main|master)' <<<"$CMD" && block "force-push to main" "Never rewrite main."
exit 0
