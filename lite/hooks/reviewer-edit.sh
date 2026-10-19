#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit): un subagente (agent_type presente) non scrive in un repo git fuori
# da <repo>/.claude/worktrees/; il reviewer scrive solo dentro il suo worktree rev-<PR>/, per la prova
# «rompi, esegui, ripristina». Fuori dai repo (scratchpad, /tmp) e la sessione principale passano.
input=$(cat)
out=$(printf '%s' "$input" | python3 -c '
import json, os, re, subprocess, sys
d = json.load(sys.stdin)
agent = d.get("agent_type")
if not agent:
    sys.exit(0)
ti = d.get("tool_input", {})
p = ti.get("file_path") or ti.get("notebook_path") or ""
p = os.path.realpath(os.path.join(d.get("cwd") or "", os.path.expanduser(p)))
if agent == "reviewer":
    if not re.search(r"/\.claude/worktrees/rev-[0-9]+/", p):
        print("il reviewer modifica solo file dentro .claude/worktrees/rev-<PR>/ (" + p + ")")
    sys.exit(0)
if "/.claude/worktrees/" in p:
    sys.exit(0)
dir = os.path.dirname(p)
while dir != "/" and not os.path.isdir(dir):
    dir = os.path.dirname(dir)
r = subprocess.run(["git", "-C", dir, "rev-parse", "--show-toplevel"], capture_output=True)
if r.returncode == 0:
    print("un subagente scrive solo nel suo worktree .claude/worktrees/<branch>/, non nel checkout " + r.stdout.decode().strip() + " (" + p + ")")
' 2>/dev/null)
[ -z "$out" ] && exit 0
echo "reviewer-edit: $out" >&2
exit 2
