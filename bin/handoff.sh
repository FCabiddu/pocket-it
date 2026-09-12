#!/usr/bin/env bash
# pocket-it handoff — the project's narrative memory, written by agents, read by the orchestrator and by humans.
# Usage (project root):
#   bash ~/.claude/agents/pocket-it/bin/handoff.sh log  "T-3.1.2 PR #41 draft — contratto ordini, 2 test"   # prepend a log line (dated)
#   bash ~/.claude/agents/pocket-it/bin/handoff.sh fact "Le migrazioni Supabase vanno applicate a mano: supabase db push"   # add an evergreen fact
#   bash ~/.claude/agents/pocket-it/bin/handoff.sh show
# Creates docs/SESSION_HANDOFF.md if missing. Log keeps the last 40 lines; the rest are moved (never dropped)
# to docs/SESSION_HANDOFF_ARCHIVE.md, appended, oldest batch at the bottom. Facts are capped at CAP (see below)
# — at the cap a new fact is refused (exit 3), it does not drop the oldest.
set -uo pipefail
CAP=100
LOGCAP=40
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "handoff: not a git repository" >&2; exit 1; }
F="$ROOT/docs/SESSION_HANDOFF.md"; ARCHIVE="$ROOT/docs/SESSION_HANDOFF_ARCHIVE.md"; mkdir -p "$ROOT/docs"
if [[ ! -f "$F" ]]; then cat > "$F" <<'EOF'
# Session handoff

Memoria della pipeline, scritta dagli agenti. Lo stato del lavoro non sta qui (si calcola con `status.sh`): qui stanno i fatti che non scadono e il log degli eventi.

## Fatti che non scadono
<!-- max 30 righe: invarianti, gotcha, decisioni e perché. Chi aggiunge una riga toglie quella che non vale più. -->

## Log (più recente in alto, ultime 40 righe)
EOF
fi
# Normalise a stale cap comment from an older version of this script (e.g. "max 30 righe")
# to the current CAP, on every run — no project is left with a comment that contradicts it.
sed -i.bak -E "s/max [0-9]+ righe:/max $CAP righe:/" "$F" && rm -f "$F.bak"
cmd="${1:-show}"; shift || true
case "$cmd" in
  log)
    line="- $(date +%Y-%m-%d) $*"
    python3 - "$F" "$ARCHIVE" "$LOGCAP" "$line" <<'PY'
import sys,os
p,archive,logcap,line=sys.argv[1],sys.argv[2],int(sys.argv[3]),sys.argv[4]
s=open(p).read()
head,sep,tail=s.partition("## Log")
if not sep: s=s.rstrip()+"\n\n## Log (più recente in alto, ultime 40 righe)\n"; head,sep,tail=s.partition("## Log")
title,_,body=tail.partition("\n")
lines=[l for l in body.splitlines() if l.startswith("- ")]
lines=[line]+lines
overflow=lines[logcap:]
lines=lines[:logcap]
open(p,"w").write(head+sep+title+"\n"+"\n".join(lines)+"\n")
if overflow:
    if not os.path.exists(archive):
        with open(archive,"w") as f:
            f.write("# Session handoff — archive\n\nRighe di log spostate qui da SESSION_HANDOFF.md quando superano le ultime "
                     f"{logcap}. Nessuna riga viene persa: questo file si accoda, non si sovrascrive mai.\n\n## Log archiviato\n")
    with open(archive,"a") as f:
        f.write("\n".join(overflow)+"\n")
    print(f"handoff: archived {len(overflow)} line(s) to docs/SESSION_HANDOFF_ARCHIVE.md")
PY
    echo "handoff: logged";;
  fact)
    python3 - "$F" "$CAP" "$*" <<'PY'
import sys
p,CAP,text=sys.argv[1],int(sys.argv[2]),sys.argv[3]; s=open(p).read()
head,sep,tail=s.partition("## Fatti che non scadono")
body,sep2,rest=tail.partition("\n## ")
lines=[l for l in body.splitlines() if l.startswith("- ")]
line="- "+text
if line in lines:
    print("handoff: fact already present"); sys.exit(0)
if len(lines)>=CAP:
    print(f"handoff: facts at cap ({CAP}/{CAP}) — not added. Ask the retro to promote stable facts to best-practices, or remove one line by hand: {text}", file=sys.stderr)
    sys.exit(3)
lines.append(line)
comment=f"\n<!-- max {CAP} righe: invarianti, gotcha, decisioni e perché. Chi aggiunge una riga toglie quella che non vale più. -->\n"
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
    [[ "$n" -eq "$CAP" ]] && echo "facts: $CAP/$CAP (cap)"
    true;;
  *) echo "usage: handoff.sh log|fact|show …" >&2; exit 2;;
esac
