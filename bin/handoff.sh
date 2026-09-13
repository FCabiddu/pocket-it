#!/usr/bin/env bash
# pocket-it handoff — the project's narrative memory, written by agents, read by the orchestrator and by humans.
# Usage (project root):
#   bash ~/.claude/agents/pocket-it/bin/handoff.sh log  "T-3.1.2 PR #41 draft — contratto ordini, 2 test"   # prepend a log line (dated)
#   bash ~/.claude/agents/pocket-it/bin/handoff.sh fact "Le migrazioni Supabase vanno applicate a mano: supabase db push"   # add an evergreen fact
#   bash ~/.claude/agents/pocket-it/bin/handoff.sh facts | show | recent N | recent --all | grep REGEX
# `log`/`fact` still create docs/SESSION_HANDOFF.md if missing and write only there (PI-16 moves writes to
# per-invocation fragments under docs/handoff/**; until then this is the only writer). Log keeps the last
# LOGCAP lines; the rest are moved (never dropped) to docs/SESSION_HANDOFF_ARCHIVE.md, oldest entry at the
# top throughout the whole archive. Facts are capped at CAP — at the cap a new fact is refused (exit 3).
#
# `facts`, `show`, `recent`, `grep` are a PURE READ-ONLY COMPOSER (PI-14, TAD §2.1/§8.1, ADR-2): they merge
# the frozen sources (SESSION_HANDOFF.md, SESSION_HANDOFF_ARCHIVE.md, both optional) with any fragments under
# docs/handoff/** (written from PI-16 on; harmless no-op today, nothing writes them yet) and NEVER touch disk
# — no mkdir, no file creation, no normalisation. `git status --porcelain` is identical before and after any
# of the four, from any directory inside the repo, with or without the frozen files.
set -uo pipefail
CAP=100
LOGCAP=40
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "handoff: not a git repository" >&2; exit 1; }
F="$ROOT/docs/SESSION_HANDOFF.md"; ARCHIVE="$ROOT/docs/SESSION_HANDOFF_ARCHIVE.md"

compose() {
  python3 - "$ROOT" "$CAP" "$LOGCAP" "$cmd" "$@" <<'PY'
import sys, os, re, glob, hashlib

root, CAP, LOGCAP, cmd = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
rest = sys.argv[5:]

MAIN = os.path.join(root, "docs", "SESSION_HANDOFF.md")
ARCHIVE_OLD = os.path.join(root, "docs", "SESSION_HANDOFF_ARCHIVE.md")
FRAG_DIR = os.path.join(root, "docs", "handoff")
ARCHIVE_DIR = os.path.join(FRAG_DIR, "archive")

def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except (FileNotFoundError, IsADirectoryError):
        return None

def section_body(text, name):
    # body of the first "## {name}..." section, up to the next "## " heading or EOF — same extraction
    # the pre-PI-14 `awk '/^## Fatti/{f=1;next} /^## /{f=0} f && /^- /'` performed, so AC1 stays byte-identical.
    m = re.search(r'^## ' + re.escape(name) + r'.*?\n', text, re.M)
    if not m:
        return ""
    start = m.end()
    nxt = re.search(r'^## ', text[start:], re.M)
    return text[start: start + nxt.start()] if nxt else text[start:]

def dash_lines(body):
    return [l for l in body.splitlines() if l.startswith("- ")]

NEG = ""  # frozen sources sort before every fragment timestamp string (ADR-3: they are older than everything)

sources = []

main_text = read(MAIN)
if main_text is not None:
    sources.append({"name": "SESSION_HANDOFF.md", "age": NEG, "kind": "frozen-main",
                     "facts": dash_lines(section_body(main_text, "Fatti")),
                     "log": dash_lines(section_body(main_text, "Log")),
                     "retracts": []})

arch_text = read(ARCHIVE_OLD)
if arch_text is not None:
    sources.append({"name": "SESSION_HANDOFF_ARCHIVE.md", "age": NEG, "kind": "frozen-archive",
                     "facts": [],
                     "log": dash_lines(section_body(arch_text, "Log archiviato")),
                     "retracts": []})

TS_RE = re.compile(r'^(\d{8}T\d{6}Z)-')
def ts_of(name):
    m = TS_RE.match(name)
    return m.group(1) if m else NEG

seen_names = set()
def add_fragment(name, text):
    # declared copies (TAD §4.3): an archived "### {name}" section and a live fragment of the same name,
    # or two archived sections with the same name, are the SAME source — identity is the name, never the
    # content — so the first one seen wins and later ones with the same name are skipped.
    if name in seen_names:
        return
    seen_names.add(name)
    sources.append({"name": name, "age": ts_of(name), "kind": "fragment",
                     "facts": dash_lines(section_body(text, "Fatti")),
                     "log": dash_lines(section_body(text, "Log")),
                     "retracts": dash_lines(section_body(text, "Ritirati"))})

if os.path.isdir(FRAG_DIR):
    for month_dir in sorted(glob.glob(os.path.join(FRAG_DIR, "*"))):
        if os.path.abspath(month_dir) == os.path.abspath(ARCHIVE_DIR) or not os.path.isdir(month_dir):
            continue
        for fp in sorted(glob.glob(os.path.join(month_dir, "*.md"))):
            name = os.path.splitext(os.path.basename(fp))[0]
            add_fragment(name, read(fp) or "")

    if os.path.isdir(ARCHIVE_DIR):
        for fp in sorted(glob.glob(os.path.join(ARCHIVE_DIR, "*.md"))):
            text = read(fp) or ""
            for m in re.finditer(r'^### (.+)\n', text, re.M):
                name = m.group(1).strip()
                start = m.end()
                nxt = re.search(r'^### ', text[start:], re.M)
                sub = text[start: start + nxt.start()] if nxt else text[start:]
                add_fragment(name, sub)

def hash12(text):
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:12]

def collect_facts():
    # order (TAD §4.3): frozen facts in file order, then fragment facts by timestamp ascending (append at
    # the bottom, like today's `fact` does) — with no fragments this is exactly the frozen file's order.
    frozen = [s for s in sources if s["age"] == NEG]
    frags = sorted([s for s in sources if s["age"] != NEG], key=lambda s: (s["age"], s["name"]))
    order = frozen + frags
    retracts = []  # (hash12, age-of-the-source-that-retracted-it)
    for s in sources:
        for r in s["retracts"]:
            m = re.match(r'^- ~ ([0-9a-f]{12})$', r)
            if m:
                retracts.append((m.group(1), s["age"]))
    seen_text = set()
    out = []
    for s in order:
        for f in s["facts"]:
            text = f[2:]
            h = hash12(text)
            # a retract hides a fact only from a source STRICTLY OLDER than the retract itself — a fact
            # rewritten after the retract (same or newer source) stays visible (TAD §4.3, last row).
            if any(h == rh and s["age"] < rage for rh, rage in retracts):
                continue
            if text in seen_text:  # facts dedup by text (a claim, not an event) — first occurrence wins
                continue
            seen_text.add(text)
            out.append(f)
    return out

DAY_RE = re.compile(r'^- (\d{4}-\d{2}-\d{2})')
def day_of(line):
    m = DAY_RE.match(line)
    return m.group(1) if m else ""

def collect_log():
    # order (TAD §4.3): key1 = day descending. key2, at equal day: fragments first (by timestamp
    # descending, then name), then frozen rows (main log top-down, archive bottom-up). Never deduplicated
    # — two identical lines from two sources are two events, verified as a multiset (AC2/AC3).
    # Built as one single secondary-order list (ignoring day), then a stable sort by day descending: ties
    # keep the secondary order exactly as built, which IS the tie-break rule above.
    frag_sources = sorted([s for s in sources if s["kind"] == "fragment"],
                           key=lambda s: (s["age"], s["name"]), reverse=True)
    secondary = []
    for s in frag_sources:
        secondary.extend(s["log"])
    main_log = next((s["log"] for s in sources if s["kind"] == "frozen-main"), [])
    arch_log = next((s["log"] for s in sources if s["kind"] == "frozen-archive"), [])
    secondary.extend(main_log)             # frozen main: as written, top of file = newest = first
    secondary.extend(reversed(arch_log))   # frozen archive: oldest-at-top-in-file, read bottom-up = newest first
    return sorted(secondary, key=lambda l: day_of(l), reverse=True)

if cmd == "facts":
    for l in collect_facts():
        print(l)
elif cmd == "show":
    facts = collect_facts()
    log = collect_log()[:LOGCAP]
    print("# Session handoff\n")
    print("Memoria della pipeline, scritta dagli agenti. Lo stato del lavoro non sta qui (si calcola con "
          "`status.sh`): qui stanno i fatti che non scadono e il log degli eventi.\n")
    print("## Fatti che non scadono")
    for l in facts:
        print(l)
    print()
    print(f"## Log (più recente in alto, ultime {LOGCAP} righe)")
    for l in log:
        print(l)
    if len(facts) >= CAP:
        tag = f"{CAP}/{CAP} (cap)" if len(facts) == CAP else f"{len(facts)}/{CAP} (oltre il tetto)"
        print(f"facts: {tag}")
elif cmd == "recent":
    log = collect_log()
    out = log if (rest and rest[0] == "--all") else log[: (int(rest[0]) if rest else LOGCAP)]
    for l in out:
        print(l)
elif cmd == "grep":
    if not rest:
        sys.exit(2)
    pat = re.compile(rest[0])
    for l in collect_log():
        if pat.search(l):
            print(l)
else:
    sys.exit(2)
PY
}

cmd="${1:-show}"; shift || true
case "$cmd" in
  facts|show|recent|grep)
    compose "$@"; exit $?;;
esac
mkdir -p "$ROOT/docs"
if [[ ! -f "$F" ]]; then cat > "$F" <<EOF
# Session handoff

Memoria della pipeline, scritta dagli agenti. Lo stato del lavoro non sta qui (si calcola con \`status.sh\`): qui stanno i fatti che non scadono e il log degli eventi.

## Fatti che non scadono
<!-- max 30 righe: invarianti, gotcha, decisioni e perché. Chi aggiunge una riga toglie quella che non vale più. -->

## Log (più recente in alto, ultime $LOGCAP righe)
EOF
fi
# Normalise a stale cap comment from an older version of this script (e.g. "max 30 righe")
# to the current CAP, on every run — no project is left with a comment that contradicts it.
sed -i.bak -E "s/max [0-9]+ righe:/max $CAP righe:/" "$F" && rm -f "$F.bak"
case "$cmd" in
  log)
    line="- $(date +%Y-%m-%d) $*"
    python3 - "$F" "$ARCHIVE" "$LOGCAP" "$line" <<'PY'
import sys,os
p,archive,logcap,line=sys.argv[1],sys.argv[2],int(sys.argv[3]),sys.argv[4]
s=open(p).read()
head,sep,tail=s.partition("## Log")
if not sep: s=s.rstrip()+f"\n\n## Log (più recente in alto, ultime {logcap} righe)\n"; head,sep,tail=s.partition("## Log")
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
                     f"{logcap}. Nessuna riga viene persa: questo file si accoda, non si sovrascrive mai. Ordine: la più "
                     "vecchia in alto, la più recente in fondo — vale dentro un batch e tra un batch e il successivo, un solo ordine.\n\n## Log archiviato\n")
    with open(archive,"a") as f:
        # overflow is newest-first (index 0 = just pushed past the cap); reverse it so this batch is
        # written oldest-first. Batches are always appended in the chronological order they rotate,
        # so the whole archive file ends up oldest-at-top, newest-at-bottom, top to bottom, no exceptions.
        f.write("\n".join(reversed(overflow))+"\n")
    print(f"handoff: archived {len(overflow)} line(s) to docs/SESSION_HANDOFF_ARCHIVE.md")
PY
    echo "handoff: logged — $F";;
  fact)
    python3 - "$F" "$CAP" "$*" <<'PY'
import sys
p,CAP,text=sys.argv[1],int(sys.argv[2]),sys.argv[3]; s=open(p).read()
head,sep,tail=s.partition("## Fatti che non scadono")
body,sep2,rest=tail.partition("\n## ")
lines=[l for l in body.splitlines() if l.startswith("- ")]
line="- "+text
if line in lines:
    print(f"handoff: fact already present — {p}"); sys.exit(0)
if len(lines)>=CAP:
    print(f"handoff: facts at cap ({CAP}/{CAP}) — not added. Ask the retro to promote stable facts to best-practices, or remove one line by hand: {text}", file=sys.stderr)
    sys.exit(3)
lines.append(line)
comment=f"\n<!-- max {CAP} righe: invarianti, gotcha, decisioni e perché. Chi aggiunge una riga toglie quella che non vale più. -->\n"
open(p,"w").write(head+sep+comment+"\n".join(lines)+"\n\n"+("## "+rest if sep2 else ""))
if len(lines)==CAP:
    print(f"handoff: facts {CAP}/{CAP} — cap reached, next fact will be refused — {p}", file=sys.stderr)
else:
    print(f"handoff: fact added — {p}")
PY
    exit $?;;
  *) echo "usage: handoff.sh log|fact|facts|show|recent N|recent --all|grep REGEX …" >&2; exit 2;;
esac
