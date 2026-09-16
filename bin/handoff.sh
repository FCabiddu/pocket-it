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

# --- PI-40: ONE definition of where a section begins, shared by the writer (`log`, `fact`) and by the
# read-only composer (`facts|show|recent|grep`). Threat model: this file is free text written by agents
# and it legitimately quotes its own markers — a fact explaining how to read the log carries `## Log`
# inside its text. Such a quote is DATA. A heading is "## " at the START OF A LINE, nowhere else.
# What it protects against: a heading deleted, or a fact reclassified into another section, by the mere
# act of writing a line. `log` used to split the file with s.partition("## Log") — a substring match — so
# the first fact quoting the marker took the heading's place: the real heading was then dropped (it does
# not start with "- "), every fact below the quote was rewritten as a log line, and the facts cap then
# trimmed real facts to make room for progress lines. What it deliberately leaves out: a heading whose
# own text is wrong or duplicated (two real "## Log" headings) — the first one wins, as before; and any
# reader living outside this script.
PY_SECTIONS=$(cat <<'PY'
import re

def split_section(text, name):
    r"""Split TEXT on the first "## {name}..." HEADING; return (before, heading, body, after).

      before  -- everything above the heading, verbatim
      heading -- the heading line itself, without its newline ("" when the file has no such heading)
      body    -- everything between that heading and the next "## " heading (or EOF)
      after   -- from that next heading to EOF, verbatim ("" when there is none)

    A heading is matched with re.M, where only "\n" starts a line (Python's re, like awk's RS="\n",
    never treats \r \v \f \x1c-\x1e U+0085 U+2028 U+2029 as line boundaries) -- so "## Log" occurring
    inside a line's text is data and is left in `before`/`body` untouched.
    """
    m = re.search(r'^## ' + re.escape(name) + r'[^\n]*', text, re.M)
    if not m:
        return text, "", "", ""
    before, heading, rest = text[:m.start()], m.group(0), text[m.end():]
    if rest.startswith("\n"):
        rest = rest[1:]
    nxt = re.search(r'^## ', rest, re.M)
    if not nxt:
        return before, heading, rest, ""
    return before, heading, rest[:nxt.start()], rest[nxt.start():]

def section_body(text, name):
    # body of the first "## {name}..." section, up to the next "## " heading or EOF -- same extraction
    # the pre-PI-14 `awk '/^## Fatti/{f=1;next} /^## /{f=0} f && /^- /'` performed, so AC1 stays
    # byte-identical.
    return split_section(text, name)[2]

def dash_lines(body):
    # split ONLY on "\n" -- never str.splitlines(), which also breaks on \v \f \x1c-\x1e U+0085 U+2028
    # U+2029 and a lone \r, characters awk's default RS="\n" treats as ordinary data. Splitting on those
    # truncates a line silently: the tail after the character doesn't start with "- " and is dropped.
    return [l for l in body.split('\n') if l.startswith("- ")]

def read_text(path):
    # newline='' disables universal-newline translation: CR, CRLF and every other line-ish byte stay as
    # literal data in the string, exactly like awk (RS="\n") sees them -- only a bare "\n" ends a record.
    # The writer needs this as much as the reader: reading with translation ON and writing the result
    # back rewrites every CR in the file, which silently cuts the tail off the line that held it.
    with open(path, encoding="utf-8", newline='') as f:
        return f.read()

def write_text(path, text):
    with open(path, "w", encoding="utf-8", newline='') as f:
        f.write(text)
PY
)
# Every python program below is fed to `python3 -` as: the shared helpers, then the program itself.
# sys.argv is unchanged by this (argv[0] is "-", argv[1:] are the arguments passed here).
py_run() { { printf '%s\n' "$PY_SECTIONS"; cat; } | python3 - "$@"; }

# PI-40 — one home for "what a writer appends is ONE record, always". The reader's record separator is
# "\n" and nothing else: split_section anchors "## " right after one, dash_lines splits on one. So a
# newline inside the caller's own text is the only character that can turn free text into a second line —
# a heading the caller never meant to write, or a data line that the next write then deletes. Collapsing
# it here, on the caller's text, is what makes a heading impossible to introduce AS DATA, whatever the
# argument is and from either writer; the marker itself needs no blacklist, because it can only ever land
# mid-line. The other line-ish characters (\r \v \f \x1c-\x1e U+0085 U+2028 U+2029) are data for every
# reader and are left byte for byte, so a line holding one still reads back exactly as written.
# Applied BEFORE anything else looks at the text, and that order is load-bearing: PI-39's leading-date
# strip must see the single line the caller meant, or "2026-01-01\nfoo" reaches the file as one line
# carrying two dates — collapsing after the date is prepended would reintroduce exactly what PI-39 forbids.
one_line() { local t="${1-}"; printf '%s' "${t//$'\n'/ }"; }

compose() {
  py_run "$ROOT" "$CAP" "$LOGCAP" "$cmd" "$@" <<'PY'
import sys, os, re, glob, hashlib

root, CAP, LOGCAP, cmd = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
rest = sys.argv[5:]

MAIN = os.path.join(root, "docs", "SESSION_HANDOFF.md")
ARCHIVE_OLD = os.path.join(root, "docs", "SESSION_HANDOFF_ARCHIVE.md")
FRAG_DIR = os.path.join(root, "docs", "handoff")
ARCHIVE_DIR = os.path.join(FRAG_DIR, "archive")

def read(path):
    # section_body / dash_lines / read_text come from the shared block above (PI-40): one definition of
    # where a section begins, used by this read-only composer and by the writer alike.
    try:
        return read_text(path)
    except (FileNotFoundError, IsADirectoryError):
        return None

def usage_exit():
    print("usage: handoff.sh facts|show|recent N|recent --all|grep REGEX", file=sys.stderr)
    sys.exit(2)

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

def do_facts(rest):
    for l in collect_facts():
        print(l)

def do_show(rest):
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

def do_recent(rest):
    log = collect_log()
    if rest and rest[0] == "--all":
        out = log
    elif not rest:
        out = log[:LOGCAP]
    else:
        out = log[: int(rest[0])]  # validate() already proved rest[0] is "--all" or digits-only
    for l in out:
        print(l)

def do_grep(rest):
    pat = re.compile(rest[0])  # validate() already proved rest[0] compiles
    for l in collect_log():
        if pat.search(l):
            print(l)

def _is_valid_regex(a):
    try:
        re.compile(a)
        return True
    except re.error:
        return False

# --- Single declaration for every read subcommand's grammar (§5.1): (min args, max args, per-arg type
# check or None, one example value known to fail that check — used only to generate a test). Extra args,
# missing args, and a value that fails the check are ALL "malformed argv" (exit 2 + usage) — never a
# silent ignore, never a Python traceback. `validate()` and `__spec` (bin/handoff.test.sh) both read this
# same dict, so there is exactly one place that knows a subcommand's arity: HANDLERS and SPEC are asserted
# in sync below, so a new elif-branch added without a SPEC entry cannot run (validate() rejects it before
# the handler is ever reached) — the whole suite catches it immediately, not just one test.
SPEC = {
    "facts":  (0, 0, None, None),
    "show":   (0, 0, None, None),
    "recent": (0, 1, lambda a: a == "--all" or bool(re.fullmatch(r'[0-9]+', a)), "abc"),
    "grep":   (1, 1, _is_valid_regex, "["),
}
HANDLERS = {"facts": do_facts, "show": do_show, "recent": do_recent, "grep": do_grep}
assert set(SPEC) == set(HANDLERS), "handoff.sh: SPEC and HANDLERS out of sync — every read subcommand needs both"

def validate(cmd, rest):
    lo, hi, check, _bad = SPEC[cmd]
    if not (lo <= len(rest) <= hi):
        usage_exit()
    if check:
        for a in rest:
            if not check(a):
                usage_exit()

if cmd == "__spec":  # internal, used only by bin/handoff.test.sh to generate the arity/type tests below
    for name, (lo, hi, _check, bad) in SPEC.items():
        print(f"{name} {lo} {hi} {bad if bad is not None else '-'}")
elif cmd not in SPEC:
    usage_exit()
else:
    validate(cmd, rest)
    HANDLERS[cmd](rest)
PY
}

cmd="${1:-show}"; shift || true
case "$cmd" in
  facts|show|recent|grep|__spec)
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
# Anchored at the start of the line (PI-40, same reason as the heading anchor): the comment is a line of
# its own, so a fact or a log line quoting "max 30 righe:" is data and is left exactly as written.
sed -i.bak -E "s/^<!-- max [0-9]+ righe:/<!-- max $CAP righe:/" "$F" && rm -f "$F.bak"
case "$cmd" in
  log)
    # PI-39: a caller can pass a message that already starts with an ISO date (its own or someone
    # else's) — the log line must never carry that date AND the one this script prepends. Strip every
    # leading "YYYY-MM-DD " run first (a caller can double it, e.g. a copy-pasted "date id" prefix), then
    # the limit case where the whole remaining message IS just a date with nothing after it (no trailing
    # space to strip against). Only a LEADING date is touched: one anchored at the start (^), never a
    # date elsewhere in the free text (AC2).
    msg=$(one_line "$*")
    while [[ "$msg" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\  ]]; do
      msg="${msg:11}"
    done
    if [[ "$msg" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      msg=""
    fi
    line="- $(date +%Y-%m-%d)${msg:+ $msg}"
    py_run "$F" "$ARCHIVE" "$LOGCAP" "$line" <<'PY'
import sys,os
p,archive,logcap,line=sys.argv[1],sys.argv[2],int(sys.argv[3]),sys.argv[4]
s=read_text(p)
# PI-40: the Log section is located by its HEADING (shared split_section: "## " at the start of a line),
# never by the substring "## Log" wherever it appears — a fact quoting the marker is data, stays in
# `before` byte for byte, and cannot take the heading's place. Whatever follows the section (`after`) is
# carried over unchanged too, so no other section is deleted by writing a log line either.
before,heading,body,after=split_section(s,"Log")
if not heading:
    # No Log section at all (a fresh or hand-edited file): create it ONCE, at the END of the file, so
    # nothing already written above — dated lines included — is re-parented into it.
    before=s.rstrip()+"\n\n"
    heading=f"## Log (più recente in alto, ultime {logcap} righe)"
    body=after=""
lines=[line]+dash_lines(body)
overflow=lines[logcap:]
lines=lines[:logcap]
write_text(p,before+heading+"\n"+"\n".join(lines)+"\n"+("\n"+after if after else ""))
if overflow:
    if not os.path.exists(archive):
        with open(archive,"w",encoding="utf-8",newline='') as f:
            f.write("# Session handoff — archive\n\nRighe di log spostate qui da SESSION_HANDOFF.md quando superano le ultime "
                     f"{logcap}. Nessuna riga viene persa: questo file si accoda, non si sovrascrive mai. Ordine: la più "
                     "vecchia in alto, la più recente in fondo — vale dentro un batch e tra un batch e il successivo, un solo ordine.\n\n## Log archiviato\n")
    with open(archive,"a",encoding="utf-8",newline='') as f:
        # overflow is newest-first (index 0 = just pushed past the cap); reverse it so this batch is
        # written oldest-first. Batches are always appended in the chronological order they rotate,
        # so the whole archive file ends up oldest-at-top, newest-at-bottom, top to bottom, no exceptions.
        f.write("\n".join(reversed(overflow))+"\n")
    print(f"handoff: archived {len(overflow)} line(s) to docs/SESSION_HANDOFF_ARCHIVE.md")
PY
    echo "handoff: logged — $F";;
  fact)
    py_run "$F" "$CAP" "$(one_line "$*")" <<'PY'
import sys
p,CAP,text=sys.argv[1],int(sys.argv[2]),sys.argv[3]; s=read_text(p)
# PI-40: same single definition as `log` and as the composer — the facts section is found by its
# heading at the start of a line, so a LOG line quoting "## Fatti che non scadono" is data and no log
# line is ever reclassified as a fact.
before,heading,body,after=split_section(s,"Fatti che non scadono")
if not heading:
    # No facts section at all: create it ONCE, at the end — before PI-40 the fact was written under no
    # heading, where every reader (anchored on the heading) is blind to it.
    before=s.rstrip()+"\n\n"
    heading="## Fatti che non scadono"
    body=after=""
lines=dash_lines(body)
line="- "+text
if line in lines:
    print(f"handoff: fact already present — {p}"); sys.exit(0)
if len(lines)>=CAP:
    print(f"handoff: facts at cap ({CAP}/{CAP}) — not added. Ask the retro to promote stable facts to best-practices, or remove one line by hand: {text}", file=sys.stderr)
    sys.exit(3)
lines.append(line)
comment=f"\n<!-- max {CAP} righe: invarianti, gotcha, decisioni e perché. Chi aggiunge una riga toglie quella che non vale più. -->\n"
write_text(p,before+heading+comment+"\n".join(lines)+"\n\n"+after)
if len(lines)==CAP:
    print(f"handoff: facts {CAP}/{CAP} — cap reached, next fact will be refused — {p}", file=sys.stderr)
else:
    print(f"handoff: fact added — {p}")
PY
    exit $?;;
  *) echo "usage: handoff.sh log|fact|facts|show|recent N|recent --all|grep REGEX …" >&2; exit 2;;
esac
