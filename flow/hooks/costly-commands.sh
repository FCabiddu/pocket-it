#!/usr/bin/env bash
# PreToolUse(Bash): the project's «only with ok» commands are not run by an agent.
# The project's CLAUDE.md lists them on one line: `Commands only with approval: <regex>, <regex>, ...`
# (Python regexes, comma-separated, hence with no commas inside; `none` = no command).
# - Only for subagents (agent_type present): the main session passes, it is the one asking the user for the ok.
# - CLAUDE.md is looked up in the repo of the command's cwd and of the `cd <dir>` the command contains
#   (root = folder of `git rev-parse --git-common-dir`, so it works in the worktrees too).
# - Command matching a regex: exit 2 and the message to stop and ask for it in the report.
# - No line, `none`, outside a repo, own error: passes (exit 0).
input=$(cat)
out=$(printf '%s' "$input" | python3 -c '
import json, os, re, subprocess, sys
d = json.load(sys.stdin)
if d.get("tool_name", "Bash") != "Bash" or not d.get("agent_type"):
    sys.exit(0)
cmd = (d.get("tool_input") or {}).get("command") or ""
if not cmd:
    sys.exit(0)
cwd = d.get("cwd") or os.getcwd()
dirs = [cwd]
for m in re.finditer(r"(?:^|[;&|(]\s*|\s)cd\s+([^\s;&|)]+)", cmd):
    p = os.path.expanduser(m.group(1).strip("\"\x27"))
    dirs.append(p if os.path.isabs(p) else os.path.join(cwd, p))
seen = set()
for folder in dirs:
    if not os.path.isdir(folder):
        continue
    try:
        common = subprocess.run(["git", "-C", folder, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                capture_output=True, text=True, timeout=5).stdout.strip()
    except Exception:
        continue
    if not common or common in seen:
        continue
    seen.add(common)
    claude = os.path.join(os.path.dirname(common), "CLAUDE.md")
    if not os.path.isfile(claude):
        continue
    items = None
    for line in open(claude, encoding="utf-8", errors="replace"):
        m = re.match(r"^Commands only with approval:\s*(.*?)\s*$", line)
        if m:
            items = m.group(1)
            break
    if items is None or items.lower() in ("", "none", "-"):
        continue
    for rx in (x.strip() for x in items.split(",")):
        if not rx:
            continue
        try:
            if re.search(rx, cmd):
                print(rx)
                sys.exit(0)
        except re.error:
            continue
' 2>/dev/null)
[ -z "$out" ] && exit 0
echo "costly-commands: «${out}» is a command that needs the user's ok (line «Commands only with approval» in the project's CLAUDE.md): stop and ask for it in the report, do not run it" >&2
exit 2
