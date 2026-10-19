#!/usr/bin/env bash
# PreToolUse(Read|Bash): developer, reviewer e tester non leggono più di 300 righe di un file per volta.
# Read senza limit (o con limit > 300) su un file di oltre 300 righe è negato; così `cat <file>` e
# `sed -n 'a,bp' <file>` con più di 300 righe. Si cerca il simbolo con grep e si legge solo quella parte.
# Gli altri agenti e la sessione principale passano.
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
    print(p + " ha " + str(n) + " righe: cerca il simbolo con grep -n e leggi solo quella parte (Read con offset e limit <= " + str(MAX) + ")")
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
