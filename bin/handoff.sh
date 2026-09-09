#!/usr/bin/env bash
# pocket-it handoff — the project's narrative memory, written by agents, read by the orchestrator and by humans.
# Usage (project root):
#   bash ~/.claude/agents/pocket-it/bin/handoff.sh log  "T-3.1.2 PR #41 draft — contratto ordini, 2 test"   # prepend a log line (dated)
#   bash ~/.claude/agents/pocket-it/bin/handoff.sh fact "Le migrazioni Supabase vanno applicate a mano: supabase db push"   # add an evergreen fact
#   bash ~/.claude/agents/pocket-it/bin/handoff.sh show
# Creates docs/SESSION_HANDOFF.md if missing. Log keeps the last 40 lines; facts are capped at 30 — at the cap a new fact is refused (exit 3), it does not drop the oldest.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "handoff: not a git repository" >&2; exit 1; }
F="$ROOT/docs/SESSION_HANDOFF.md"; mkdir -p "$ROOT/docs"
if [[ ! -f "$F" ]]; then cat > "$F" <<'EOF'
# Session handoff

Memoria della pipeline, scritta dagli agenti. Lo stato del lavoro non sta qui (si calcola con `status.sh`): qui stanno i fatti che non scadono e il log degli eventi.

## Fatti che non scadono
<!-- max 30 righe: invarianti, gotcha, decisioni e perché. Chi aggiunge una riga toglie quella che non vale più. -->

## Log (più recente in alto, ultime 40 righe)
EOF
fi
cmd="${1:-show}"; shift || true
case "$cmd" in
  log)
    line="- $(date +%Y-%m-%d) $*"
    python3 - "$F" "$line" <<'PY'
import sys,re
p,line=sys.argv[1],sys.argv[2]; s=open(p).read()
head,sep,tail=s.partition("## Log")
if not sep: s=s.rstrip()+"\n\n## Log (più recente in alto, ultime 40 righe)\n"; head,sep,tail=s.partition("## Log")
title,_,body=tail.partition("\n")
lines=[l for l in body.splitlines() if l.startswith("- ")]
lines=[line]+lines
lines=lines[:40]
open(p,"w").write(head+sep+title+"\n"+"\n".join(lines)+"\n")
PY
    echo "handoff: logged";;
  fact)
    python3 - "$F" "$*" <<'PY'
import sys
p,text=sys.argv[1],sys.argv[2]; s=open(p).read()
head,sep,tail=s.partition("## Fatti che non scadono")
body,sep2,rest=tail.partition("\n## ")
lines=[l for l in body.splitlines() if l.startswith("- ")]
line="- "+text
CAP=30
if line in lines:
    print("handoff: fact already present"); sys.exit(0)
if len(lines)>=CAP:
    print(f"handoff: facts at cap ({CAP}/{CAP}) — not added. Ask the retro to promote stable facts to best-practices, or remove one line by hand: {text}", file=sys.stderr)
    sys.exit(3)
lines.append(line)
comment="\n<!-- max 30 righe: invarianti, gotcha, decisioni e perché. Chi aggiunge una riga toglie quella che non vale più. -->\n"
open(p,"w").write(head+sep+comment+"\n".join(lines)+"\n\n"+("## "+rest if sep2 else ""))
if len(lines)==CAP:
    print(f"handoff: facts {CAP}/{CAP} — cap reached, next fact will be refused", file=sys.stderr)
else:
    print("handoff: fact added")
PY
    exit $?;;
  show)
    cat "$F"
    n=$(awk '/^## Fatti che non scadono/{f=1;next} /^## /{f=0} f && /^- /{c++} END{print c+0}' "$F")
    [[ "$n" -eq 30 ]] && echo "facts: 30/30 (cap)"
    true;;
  *) echo "usage: handoff.sh log|fact|show …" >&2; exit 2;;
esac
