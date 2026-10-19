#!/usr/bin/env bash
# Checks the technical design of a feature and the tasks that cite it. The architect runs it when checking the tasks.
#   design-check.sh <feature folder> <task.md>...
#   design-check.sh docs/features/mondo-unico-xoria tasks/mondo-unico-xoria/c4-0*.md
# Reports: design files (index and technical-design/, archive excluded) over 150 lines; citations
# `technical-design/<file>.md` § «title» to a file or a heading (# line) that does not exist, or to the archive;
# tasks without the «To read» section or with an empty one. Exits with 1 if it finds anything.
set -euo pipefail
[ $# -ge 2 ] || { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

python3 - "$@" <<'EOF'
import glob, os, re, sys
MAX = 150
feat, tasks = sys.argv[1].rstrip("/"), sys.argv[2:]
D = feat + "/technical-design/"
bad = []

if not os.path.isdir(D):
    bad.append("missing folder " + D)
files = [feat + "/technical-design.md"] + [f for f in glob.glob(D + "**/*.md", recursive=True) if "/archive/" not in f]
heads = {}
for f in files:
    if not os.path.isfile(f):
        bad.append("missing " + f); continue
    ls = open(f, encoding="utf-8").read().splitlines()
    if len(ls) > MAX:
        bad.append("%s: %d lines, the maximum is %d" % (f, len(ls), MAX))
    if f.startswith(D):
        heads[os.path.relpath(f, D)] = {re.sub(r"^#+\s*", "", l).strip() for l in ls if l.startswith("#")}

def quotes(s):
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch == "«":
            if depth: cur += ch
            depth += 1
        elif ch == "»" and depth:
            depth -= 1
            if depth: cur += ch
            else: out.append(cur); cur = ""
        elif depth:
            cur += ch
    return out

cite = re.compile(r"technical-design/([A-Za-z0-9_/.-]+\.md)`?\s*§")
for t in tasks:
    s = open(t, encoding="utf-8").read()
    name = os.path.basename(t)
    for m in cite.finditer(s):
        fn = m.group(1)
        if fn.startswith("archive/"):
            bad.append("%s: cites the archive (%s)" % (name, fn)); continue
        if fn not in heads:
            bad.append("%s: nonexistent design file (%s)" % (name, fn)); continue
        rest = s[m.end():]
        stop = re.search(r"technical-design/[A-Za-z0-9_/.-]+\.md|\n\n|\.\s", rest)
        qs = quotes(rest[:stop.start()] if stop else rest)
        if not qs:
            bad.append("%s: %s cited without «title»" % (name, fn))
        for q in qs:
            q = " ".join(q.split())
            if q not in heads[fn]:
                bad.append("%s: nonexistent heading in %s: «%s»" % (name, fn, q))
    sec = re.search(r"^#+\s*To read\s*$(.*?)(?=^#+\s|\Z)", s, re.M | re.S) or \
          re.search(r"^\*\*To read\*\*(.*?)(?=^\*\*[A-Z]|\Z)", s, re.M | re.S)
    if not sec or not sec.group(1).strip(" —-:\n"):
        bad.append("%s: the «To read» section is missing or empty" % name)

for b in bad:
    print(b)
print("design-check: %d tasks, %d problems" % (len(tasks), len(bad)))
sys.exit(1 if bad else 0)
EOF
