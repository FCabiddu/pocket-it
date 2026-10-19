#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit|Bash): nothing about a project goes into the global memory (the one of the
# sessions opened from the home, ~/.claude/projects/<home>/memory/). A project's memories go into the project's
# memory, which loads only when Claude is opened from its directory.
# - Blocks a `type: project` memory or one that names a project (in the file name or in the text).
# - Every other write there, and every Bash command that touches it, asks the user for confirmation: a project
#   memory that does not name the project can be recognised only by reading it.
# Projects: the git repos under ~/Desktop and the directories that have a memory in ~/.claude/projects/.
# For the tests: MEMORY_HOME, MEMORY_CLAUDE_DIR, MEMORY_PROJECTS_DIR.
input=$(cat)
out=$(printf '%s' "$input" | python3 -c '
import json, os, re, subprocess, sys
home = os.environ.get("MEMORY_HOME") or os.path.expanduser("~")
claude = os.environ.get("MEMORY_CLAUDE_DIR") or os.path.join(home, ".claude")
desk = os.environ.get("MEMORY_PROJECTS_DIR") or os.path.join(home, "Desktop")
enc = lambda p: re.sub(r"[^A-Za-z0-9]", "-", p)
mem = os.path.join(os.path.realpath(claude), "projects", enc(home), "memory") + "/"
d = json.load(sys.stdin)
ti = d.get("tool_input", {})
def ask(reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask",
        "permissionDecisionReason": "global-memory: " + reason}}))
    sys.exit(0)
if d.get("tool_name") == "Bash":
    cmd = ti.get("command") or ""
    if enc(home) + "/memory" in cmd:
        ask("the command touches the global memory: only what applies to every project belongs there")
    sys.exit(0)
p = ti.get("file_path") or ti.get("notebook_path") or ""
p = os.path.realpath(os.path.join(d.get("cwd") or "", os.path.expanduser(p)))
if not p.startswith(mem):
    sys.exit(0)
text = "\n".join(str(ti.get(k) or "") for k in ("content", "new_string", "new_source"))
if re.search(r"^\s*type:\s*project\s*$", text, re.M):
    print("a type: project memory goes into the project memory, not into the global one")
    sys.exit(0)
# Project names: git repos up to 3 levels under ~/Desktop, plus the directories with a memory of their own.
folders = set()
for root, dirs, files in os.walk(desk):
    level = root[len(desk):].count(os.sep)
    dirs[:] = [x for x in dirs if x not in ("node_modules", ".git", ".claude")] if level < 3 else []
    if level >= 1:
        folders.add(root)
encoded = set(os.listdir(os.path.join(claude, "projects"))) if os.path.isdir(os.path.join(claude, "projects")) else set()
names = set()
for c in folders:
    if os.path.exists(os.path.join(c, ".git")) or enc(c) in encoded:
        names.add(os.path.basename(c))
for n in sorted(names, key=len, reverse=True):
    parts = [re.escape(x) for x in re.split(r"[^A-Za-z0-9]+", n) if x]
    if not parts:
        continue
    rx = r"(?<![A-Za-z0-9])" + r"[-_ ]?".join(parts) + r"(?![A-Za-z0-9])"
    if re.search(rx, os.path.basename(p) + "\n" + text, re.I):
        print("names the project " + n + ": it goes into the project memory (~/.claude/projects/<project directory>/memory/), not into the global one")
        sys.exit(0)
ask("write into the global memory: is it a preference valid for every project?")
' 2>/dev/null)
[ -z "$out" ] && exit 0
case $out in '{'*) printf '%s\n' "$out"; exit 0;; esac
echo "global-memory: $out" >&2
exit 2
