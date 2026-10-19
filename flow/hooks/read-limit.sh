#!/usr/bin/env bash
# PreToolUse(Read|Bash): developer, reviewer and tester read no more than 300 lines of a file at a time.
# Read without limit (or with limit > 300) on a file of more than 300 lines is denied; so are `cat <file>` and
# `sed -n 'a,bp' <file>` with more than 300 lines. Look the symbol up with grep and read only that part.
# The other agents and the main session pass.
input=$(cat)
out=$(printf '%s' "$input" | python3 -c '
import json, os, re, shlex, sys
MAX = 300
d = json.load(sys.stdin)
if d.get("agent_type") not in ("developer", "reviewer", "tester"):
    sys.exit(0)
cwd = d.get("cwd") or os.getcwd()
ti = d.get("tool_input", {})

def lines(p, base):
    p = os.path.realpath(os.path.join(base, os.path.expanduser(p)))
    try:
        with open(p, "rb") as f:
            return p, sum(1 for _ in f)
    except OSError:
        return p, 0

def deny(p, n):
    print(p + " has " + str(n) + " lines: look the symbol up with grep -n and read only that part (Read with offset and limit <= " + str(MAX) + ")")
    sys.exit(0)

if d.get("tool_name") == "Read":
    lim = ti.get("limit")
    if lim is None or lim > MAX:
        p, n = lines(ti.get("file_path", ""), cwd)
        if n > MAX:
            deny(p, n)
    sys.exit(0)

cmd = ti.get("command", "")
base = cwd
for seg in re.split(r"&&|;|\n", cmd):
    if "|" in seg or ">" in seg:
        continue
    try:
        w = shlex.split(seg)
    except ValueError:
        continue
    if len(w) == 2 and w[0] == "cd":
        base = os.path.join(base, os.path.expanduser(w[1]))
    elif len(w) == 2 and w[0] == "cat":
        p, n = lines(w[1], base)
        if n > MAX:
            deny(p, n)
    elif len(w) == 4 and w[0] == "sed" and w[1] == "-n":
        m = re.fullmatch(r"(\d+),(\d+)p", w[2])
        if m and int(m.group(2)) - int(m.group(1)) + 1 > MAX:
            p, n = lines(w[3], base)
            if n > MAX:
                deny(p, n)
' 2>/dev/null)
[ -z "$out" ] && exit 0
echo "read-limit: $out" >&2
exit 2
