#!/usr/bin/env bash
# Controlla il design tecnico di una feature e i task che lo citano. L'architect lo lancia quando controlla i task.
#   design-check.sh <cartella feature> <task.md>...
#   design-check.sh docs/features/mondo-unico-xoria tasks/mondo-unico-xoria/c4-0*.md
# Segnala: file del design (indice e design-tecnico/, archivio escluso) oltre 150 righe; citazioni
# `design-tecnico/<file>.md` § «titolo» a un file o a un titolo (riga #) che non esiste, o all'archivio;
# task senza la sezione «Da leggere» o con la sezione vuota. Esce con 1 se trova qualcosa.
set -euo pipefail
[ $# -ge 2 ] || { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

python3 - "$@" <<'EOF'
import glob, os, re, sys
MAX = 150
feat, tasks = sys.argv[1].rstrip("/"), sys.argv[2:]
D = feat + "/design-tecnico/"
bad = []

if not os.path.isdir(D):
    bad.append("manca la cartella " + D)
files = [feat + "/design-tecnico.md"] + [f for f in glob.glob(D + "**/*.md", recursive=True) if "/archivio/" not in f]
heads = {}
for f in files:
    if not os.path.isfile(f):
        bad.append("manca " + f); continue
    ls = open(f, encoding="utf-8").read().splitlines()
    if len(ls) > MAX:
        bad.append("%s: %d righe, il massimo è %d" % (f, len(ls), MAX))
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

cite = re.compile(r"design-tecnico/([A-Za-z0-9_/.-]+\.md)`?\s*§")
for t in tasks:
    s = open(t, encoding="utf-8").read()
    name = os.path.basename(t)
    for m in cite.finditer(s):
        fn = m.group(1)
        if fn.startswith("archivio/"):
            bad.append("%s: cita l'archivio (%s)" % (name, fn)); continue
        if fn not in heads:
            bad.append("%s: file del design inesistente (%s)" % (name, fn)); continue
        rest = s[m.end():]
        stop = re.search(r"design-tecnico/[A-Za-z0-9_/.-]+\.md|\n\n|\.\s", rest)
        qs = quotes(rest[:stop.start()] if stop else rest)
        if not qs:
            bad.append("%s: %s citato senza «titolo»" % (name, fn))
        for q in qs:
            q = " ".join(q.split())
            if q not in heads[fn]:
                bad.append("%s: titolo inesistente in %s: «%s»" % (name, fn, q))
    sec = re.search(r"^#+\s*Da leggere\s*$(.*?)(?=^#+\s|\Z)", s, re.M | re.S) or \
          re.search(r"^\*\*Da leggere\*\*(.*?)(?=^\*\*[A-Z]|\Z)", s, re.M | re.S)
    if not sec or not sec.group(1).strip(" —-:\n"):
        bad.append("%s: manca la sezione «Da leggere» o è vuota" % name)

for b in bad:
    print(b)
print("design-check: %d task, %d problemi" % (len(tasks), len(bad)))
sys.exit(1 if bad else 0)
EOF
