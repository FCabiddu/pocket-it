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

# gh pr merge requires the POCKET_IT_USER_MERGE=1 prefix: the audit trail that the merge is covered by the
# standing default (automerge: true) or by an explicit user instruction. The orchestrator uses it by default
# after an approved review; it is never used when the user asked for draft PRs, nor on the epic→main PR of
# a deployed project without an instruction (that merge is a deploy).
if ! grep -qE '(^|[;&|[:space:]])POCKET_IT_USER_MERGE=1[[:space:]]' <<<"$CMD"; then
  grep -qE '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+merge\b' <<<"$CMD" && block "gh pr merge" "Prefix the command with POCKET_IT_USER_MERGE=1 — the audit trail that this merge is covered by the automerge default or by an explicit instruction. Never merge when the user asked for draft PRs, nor the epic→main PR of a deployed project without an instruction: report the PR as ready instead."
fi
# No direct pushes to main/master (feature branches are fine).
grep -qE 'git[[:space:]]+push([[:space:]]+-[-a-zA-Z]+)*[[:space:]]+\S+[[:space:]]+(main|master)([[:space:]]|$|:)' <<<"$CMD" && block "git push to main/master" "Push a task branch and open a draft PR."
grep -qE 'git[[:space:]]+push([[:space:]]+-[-a-zA-Z]+)*[[:space:]]+(origin[[:space:]]+)?(HEAD:)?(main|master)([[:space:]]|$)' <<<"$CMD" && block "git push to main/master" "Push a task branch and open a draft PR."
# A bare `git push`, `git push origin HEAD`/`-u origin HEAD` or a refspec whose destination is
# main/master (even under a refs/heads/ prefix) is only safe when the branch it resolves to isn't
# main/master. Resolve the repo (a `-C <path>` on the same `git` invocation, else the nearest
# preceding `cd <path>` in the command, else the hook's own cwd) and its current branch cheaply.
if grep -qE 'git[[:space:]]+(-C[[:space:]]+\S+[[:space:]]+)?push\b' <<<"$CMD"; then
  PUSH_VERDICT=$(python3 - "$CMD" "$PWD" <<'PYEOF'
import sys, re, os, subprocess, shlex

cmd, hook_cwd = sys.argv[1], sys.argv[2]

def branch_of(path):
    try:
        r = subprocess.run(["git", "-C", path, "symbolic-ref", "--short", "-q", "HEAD"],
                            capture_output=True, text=True, timeout=3)
        return r.stdout.strip() if r.returncode == 0 else None
    except Exception:
        return None

def resolve_dir(path):
    if path is None:
        return hook_cwd
    p = path if path.startswith("/") else hook_cwd.rstrip("/") + "/" + path
    return p if os.path.isdir(p) else hook_cwd

def norm(ref):
    return re.sub(r'^refs/heads/', '', ref)

verdict = ""
tracked_cd = None
for seg in re.split(r'(?:&&|\|\||;|\|)', cmd):
    seg = seg.strip()
    m = re.match(r'^cd\s+(\S+)', seg)
    if m:
        tracked_cd = m.group(1)
        continue
    m = re.match(r'^git\s+(?:-C\s+(\S+)\s+)?push\b(.*)$', seg)
    if not m:
        continue
    c_path, rest = m.group(1), m.group(2)
    try:
        tokens = shlex.split(rest)
    except ValueError:
        tokens = rest.split()
    positional = [t for t in tokens if not t.startswith('-')]

    implicit, explicit_main = False, False
    if len(positional) == 0:
        implicit = True
    elif len(positional) == 1:
        if ':' in positional[0]:
            _, dst = positional[0].split(':', 1)
            if dst and norm(dst) in ('main', 'master'):
                explicit_main = True
        else:
            implicit = True
    else:
        ref = positional[1]
        if ':' in ref:
            _, dst = ref.split(':', 1)
            if dst and norm(dst) in ('main', 'master'):
                explicit_main = True
        elif ref == 'HEAD':
            implicit = True
        elif norm(ref) in ('main', 'master'):
            explicit_main = True

    if explicit_main:
        verdict = "EXPLICIT"
        break
    if implicit:
        b = branch_of(resolve_dir(c_path or tracked_cd))
        if b in ('main', 'master'):
            verdict = "IMPLICIT"
            break

print(verdict)
PYEOF
)
  case "$PUSH_VERDICT" in
    IMPLICIT) block "git push to main/master" "Push a task branch and open a draft PR. Current branch is main — use a branch and a PR." ;;
    EXPLICIT) block "git push to main/master" "Push a task branch and open a draft PR." ;;
  esac
fi
# Never kill by pattern on a shared machine.
grep -qE '(^|[;&|[:space:]])(pkill|killall)\b' <<<"$CMD" && block "pkill/killall" "Kill your own process by PID or by port: lsof -nP -iTCP:PORT -sTCP:LISTEN -t | xargs -r kill."
# CI budget switch is a human decision.
grep -qE 'gh[[:space:]]+variable[[:space:]]+set[[:space:]]+APP_STATUS.*prod' <<<"$CMD" && block "APP_STATUS → prod" "Turning hosted CI on is the user's call (initialising it to dev is fine)."
# Sleep-and-poll chains are blocked by the harness anyway; fail fast with a hint.
grep -qE '^[[:space:]]*(cd [^;&]+ (&&|;) *)?sleep[[:space:]]+[0-9]+[[:space:]]*(&&|;)' <<<"$CMD" && block "sleep N && …" "Use 'gh pr checks N --watch' or a bounded until-loop (sleep inside a loop body is fine)."
# Destructive git on shared history.
grep -qE 'git[[:space:]]+push[[:space:]]+.*(--force|-f)\b.*(main|master)' <<<"$CMD" && block "force-push to main" "Never rewrite main."
exit 0
