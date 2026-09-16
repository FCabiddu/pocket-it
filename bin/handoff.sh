#!/usr/bin/env bash
# pocket-it handoff — the project's narrative memory, written by agents, read by the orchestrator and by humans.
# Usage (project root):
#   bash ~/.claude/agents/pocket-it/bin/handoff.sh log  "T-3.1.2 PR #41 draft — contratto ordini, 2 test"
#   bash ~/.claude/agents/pocket-it/bin/handoff.sh fact "Le migrazioni vanno applicate a mano: <comando>"
#   bash ~/.claude/agents/pocket-it/bin/handoff.sh retract "il testo esatto del fatto da nascondere"
#   bash ~/.claude/agents/pocket-it/bin/handoff.sh facts | show | recent N | recent --all | grep REGEX | where
#
# PI-16 — EVERY WRITE CREATES A NEW IMMUTABLE FILE, AND NOTHING IS EVER WRITTEN TWICE (TAD ADR-1, ADR-5).
# `log`, `fact` and `retract` create one fragment per invocation under
#   docs/handoff/{AAAA-MM}/{AAAAMMGGTHHMMSSZ}-{slug}-{rand4}.md
# holding exactly one section and one entry. The file is created with O_EXCL (the syscall flag `set -o
# noclobber` is itself implemented with): a name that already exists is never overwritten and never
# appended to — another name is generated instead. Because no two invocations ever touch one path, two
# branches cannot conflict on the memory: a merge is a union of added files, whoever performs it.
#
# FROZEN SOURCES (ADR-3). docs/SESSION_HANDOFF.md and docs/SESSION_HANDOFF_ARCHIVE.md are never written
# again by this script — not created, not appended, not normalised. They stay as they are and the
# composer keeps reading them for ever, so nothing has to be migrated and no line can be lost in the
# move. A repo that never had them never gets them.
#
# NO ROTATION (ADR-4). Nothing is moved between files any more: LOGCAP is the number of log lines `show`
# and a bare `recent` DISPLAY (`recent --all` shows everything), and CAP is a WRITE cap on the visible
# facts. A fact is removed from the view with `retract`, which creates a `## Ritirati` fragment holding
# the sha1 of its text — never by editing a file somebody else's branch also holds.
#
# `facts`, `show`, `recent`, `grep` and `where` are PURE READS (ADR-2): `git status --porcelain` is
# identical before and after each of them, from any directory, with or without the frozen files.
# `where` additionally needs NO git repository at all — it prints the relative directory a write would
# use and exits 0, which is the verifiable signal that this version is installed (TAD §9.2).
#
# One list of subcommands, one home for the record format: SPEC below is the only declaration of what
# this CLI accepts (arity, per-argument check, whether it needs a repo, usage text), and
# bin/handoff_sections.py is the only definition of where a section begins and of what makes one record.
set -uo pipefail
CAP=100
LOGCAP=40
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/handoff_sections.py"
[[ -r "$LIB" ]] || { echo "handoff: cannot read $LIB — install is incomplete" >&2; exit 1; }

# The python program below is fed to `python3 -` as: the shared helpers, then the program itself.
# sys.argv is unchanged by this (argv[0] is "-", argv[1:] are the arguments passed here). python3
# compiles the whole of stdin before executing a line of it, so an early sys.exit() cannot SIGPIPE the
# cats and turn the exit code into 141 under pipefail.
py_run() { { cat "$LIB"; cat; } | python3 - "$@"; }

# No `case` on the subcommand here, deliberately: a bash dispatch list is a SECOND list of subcommands
# that python's `assert set(SPEC) == set(HANDLERS)` cannot see, and a write subcommand missing from SPEC
# would then run unvalidated (PI-14 review finding). Everything is routed by SPEC.
cmd="${1:-show}"; shift || true
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=""

py_run "$ROOT" "$CAP" "$LOGCAP" "$cmd" "$@" <<'PY'
import sys, os, re, glob, hashlib, subprocess, random, string, datetime

root, CAP, LOGCAP, cmd = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
rest = sys.argv[5:]

FRAG_REL = "docs/handoff"


def read(path):
    # section_body / dash_lines / read_text / one_line come from bin/handoff_sections.py (PI-40/PI-16):
    # one definition of where a section begins and of what one record is, shared by this composer, by
    # the three writers, and from PI-43 by bin/retro-due.sh.
    try:
        return read_text(path)
    except (FileNotFoundError, IsADirectoryError):
        return None


def hash12(text):
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:12]


# ---------------------------------------------------------------------------------------------------
# Composition (read-only). Sources are loaded LAZILY: `where` needs no repo and must touch no path at
# all, and a read must not glob a tree it was never pointed at.
# ---------------------------------------------------------------------------------------------------
NEG = ""  # frozen sources sort before every fragment timestamp string (ADR-3: they are older than everything)
TS_RE = re.compile(r'^(\d{8}T\d{6}Z)-')
_sources = None


def ts_of(name):
    m = TS_RE.match(name)
    return m.group(1) if m else NEG


def load_sources():
    global _sources
    if _sources is not None:
        return _sources
    sources = []
    seen_names = set()

    def add_fragment(name, text):
        # declared copies (TAD §4.3): an archived "### {name}" section and a live fragment of the same
        # name, or two archived sections with the same name, are the SAME source — identity is the name,
        # never the content — so the first one seen wins and later ones with the same name are skipped.
        if name in seen_names:
            return
        seen_names.add(name)
        sources.append({"name": name, "age": ts_of(name), "kind": "fragment",
                        "facts": dash_lines(section_body(text, "Fatti")),
                        "log": dash_lines(section_body(text, "Log")),
                        "retracts": dash_lines(section_body(text, "Ritirati"))})

    main_text = read(os.path.join(root, "docs", "SESSION_HANDOFF.md"))
    if main_text is not None:
        sources.append({"name": "SESSION_HANDOFF.md", "age": NEG, "kind": "frozen-main",
                        "facts": dash_lines(section_body(main_text, "Fatti")),
                        "log": dash_lines(section_body(main_text, "Log")),
                        "retracts": []})

    arch_text = read(os.path.join(root, "docs", "SESSION_HANDOFF_ARCHIVE.md"))
    if arch_text is not None:
        sources.append({"name": "SESSION_HANDOFF_ARCHIVE.md", "age": NEG, "kind": "frozen-archive",
                        "facts": [],
                        "log": dash_lines(section_body(arch_text, "Log archiviato")),
                        "retracts": []})

    frag_dir = os.path.join(root, FRAG_REL)
    archive_dir = os.path.join(frag_dir, "archive")
    if os.path.isdir(frag_dir):
        for month_dir in sorted(glob.glob(os.path.join(frag_dir, "*"))):
            if os.path.abspath(month_dir) == os.path.abspath(archive_dir) or not os.path.isdir(month_dir):
                continue
            for fp in sorted(glob.glob(os.path.join(month_dir, "*.md"))):
                add_fragment(os.path.splitext(os.path.basename(fp))[0], read(fp) or "")

        if os.path.isdir(archive_dir):
            for fp in sorted(glob.glob(os.path.join(archive_dir, "*.md"))):
                text = read(fp) or ""
                for m in re.finditer(r'^### (.+)\n', text, re.M):
                    name = m.group(1).strip()
                    start = m.end()
                    nxt = re.search(r'^### ', text[start:], re.M)
                    add_fragment(name, text[start: start + nxt.start()] if nxt else text[start:])

    _sources = sources
    return _sources


def retract_ages(h=None):
    """(hash12, age-of-the-fragment-that-retracted-it) for every retract entry, or only for hash H."""
    out = []
    for s in load_sources():
        for r in s["retracts"]:
            m = re.match(r'^- ~ ([0-9a-f]{12})$', r)
            if m and (h is None or m.group(1) == h):
                out.append((m.group(1), s["age"]))
    return out


def visible_facts():
    """[(line, age of the source it came from)] — the composed, deduplicated, retract-filtered view.
    order (TAD §4.3): frozen facts in file order, then fragment facts by timestamp ascending (appended
    at the bottom, as `fact` has always behaved) — with no fragments this is exactly the frozen file's
    order, byte for byte."""
    sources = load_sources()
    frozen = [s for s in sources if s["age"] == NEG]
    frags = sorted([s for s in sources if s["age"] != NEG], key=lambda s: (s["age"], s["name"]))
    retracts = retract_ages()
    seen_text = set()
    out = []
    for s in frozen + frags:
        for f in s["facts"]:
            text = f[2:]
            h = hash12(text)
            # a retract hides a fact only from a source STRICTLY OLDER than the retract itself — a fact
            # rewritten after the retract (same or newer source) stays visible (TAD §4.3, last row).
            # Both writers keep that comparison decidable at one-second resolution: see `after=` in
            # create_fragment().
            if any(h == rh and s["age"] < rage for rh, rage in retracts):
                continue
            if text in seen_text:  # facts dedup by text (a claim, not an event) — first occurrence wins
                continue
            seen_text.add(text)
            out.append((f, s["age"]))
    return out


def collect_facts():
    return [f for f, _age in visible_facts()]


DAY_RE = re.compile(r'^- (\d{4}-\d{2}-\d{2})')


def day_of(line):
    m = DAY_RE.match(line)
    return m.group(1) if m else ""


def collect_log():
    # order (TAD §4.3): key1 = day descending. key2, at equal day: fragments first (by timestamp
    # descending, then name), then frozen rows (main log top-down, archive bottom-up). Never
    # deduplicated — two identical lines from two sources are two events, verified as a multiset.
    # Built as one single secondary-order list (ignoring day), then a stable sort by day descending:
    # ties keep the secondary order exactly as built, which IS the tie-break rule above.
    sources = load_sources()
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


# ---------------------------------------------------------------------------------------------------
# Fragment creation. THREAT MODEL: the file name carries a branch name, which is attacker-shaped input
# (a branch may legally hold "..", "/", spaces, quotes and shell metacharacters). What this guards
# against is a write landing anywhere other than docs/handoff/{AAAA-MM}/, and a second invocation ever
# writing a path a first one already wrote. It does NOT guard against someone editing a fragment after
# the fact — that is doctor.sh's job (PI-17) — nor against a hostile filesystem.
# ---------------------------------------------------------------------------------------------------
# No "." and no "/" anywhere in the stem, so no generated name can be ".." or climb out of the month
# directory whatever the branch is called; "T"/"Z" are the only upper-case characters, from the stamp.
NAME_RE = re.compile(r'^[0-9A-Za-z][0-9A-Za-z-]*\.md$')


def _git(*args):
    try:
        r = subprocess.run(["git", "-C", root] + list(args), capture_output=True, text=True)
    except OSError:
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def branch_slug():
    """The branch name, lowercased and with every character outside [a-z0-9] replaced by '-', capped at
    40 characters; `detached-{sha7}` when HEAD is detached. It exists for a human opening the directory,
    never to make the name unique (that is create_fragment's exclusive create). Lowercasing first is
    what keeps an upper-case branch readable: a literal [^a-z0-9] pass over "Task/PI-14" would leave
    nothing but dashes."""
    b = _git("symbolic-ref", "--quiet", "--short", "HEAD")
    if b:
        return re.sub(r'[^a-z0-9]', '-', b.lower())[:40]
    sha = _git("rev-parse", "--short=7", "HEAD")
    return "detached-" + re.sub(r'[^0-9a-f]', '', sha.lower())[:7] if sha else "detached"


def rand4():
    """4 characters [a-z0-9] from the OS entropy source (/dev/urandom, via random.SystemRandom)."""
    rnd = random.SystemRandom()
    return "".join(rnd.choice(string.ascii_lowercase + string.digits) for _ in range(4))


STAMP_FMT = "%Y%m%dT%H%M%SZ"


def create_fragment(section, entry, after=None):
    """Create the one fragment this invocation writes, and return its path.

    AFTER, when given, is the timestamp of a source this fragment must SUPERSEDE (the facts a retract
    hides; the retract a re-declared fact overrides). The filename stamp has one-second resolution, so
    two invocations inside the same second would otherwise be unordered and the "strictly older" rule of
    §4.3 would fall on the wrong side of a coin toss — `fact X` immediately followed by `retract X`
    would leave X visible. Whenever that happens the stamp is moved to AFTER + 1s: the name says when
    the entry takes effect, which is never before what it supersedes. It costs at most one second of
    apparent age, only in the sub-second race, and it keeps the rule decidable without sleeping, without
    depending on the random suffix, and without ever rewriting a file."""
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime(STAMP_FMT)
    if after and stamp <= after:
        stamp = (datetime.datetime.strptime(after, STAMP_FMT) +
                 datetime.timedelta(seconds=1)).strftime(STAMP_FMT)
    month_dir = os.path.join(root, FRAG_REL, "%s-%s" % (stamp[:4], stamp[4:6]))
    slug = branch_slug()
    body = "## %s\n%s\n" % (section, entry)
    os.makedirs(month_dir, exist_ok=True)
    for _ in range(64):
        name = "%s-%s-%s.md" % (stamp, slug, rand4())
        if not NAME_RE.match(name):
            print("handoff: refusing to write a fragment named %r — sanitisation failed" % name,
                  file=sys.stderr)
            sys.exit(2)
        path = os.path.join(month_dir, name)
        try:
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
        except FileExistsError:
            continue          # never overwrite, never append: generate another name (ADR-5)
        with os.fdopen(fd, "w", encoding="utf-8", newline='') as f:
            f.write(body)
        return path
    print("handoff: could not create a unique fragment in %s after 64 attempts" % month_dir,
          file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------------------------------
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


def do_where(rest):
    # No repo, no filesystem touch, no write: the installed-version signal (TAD §9.2). Read from any
    # directory, including one that is not a git repository at all.
    print("%s/%s/" % (FRAG_REL, datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m")))


def do_log(rest):
    # one_line() FIRST, on the caller's own text, before any other rule looks at it — see the order note
    # in bin/handoff_sections.py. Then PI-39: a caller can pass a message that already starts with an
    # ISO date (its own or someone else's), and the line must never carry that date AND the one written
    # here. Strip every LEADING "YYYY-MM-DD " run (a caller can double it), then the limit case where
    # the whole remaining message IS just a date. A date elsewhere in the free text is never touched.
    msg = one_line(" ".join(rest))
    while re.match(r'^\d{4}-\d{2}-\d{2} ', msg):
        msg = msg[11:]
    if re.fullmatch(r'\d{4}-\d{2}-\d{2}', msg):
        msg = ""
    line = "- " + datetime.date.today().strftime("%Y-%m-%d") + ((" " + msg) if msg else "")
    print("handoff: logged — %s" % create_fragment("Log", line))


def do_fact(rest):
    text = one_line(" ".join(rest))
    visible = collect_facts()
    if ("- " + text) in visible:
        print("handoff: fact already present — %s" % os.path.join(root, FRAG_REL))
        return
    if len(visible) >= CAP:
        print("handoff: facts at cap (%d/%d) — not added. Ask the retro to promote stable facts to "
              "best-practices, or retract one first: handoff.sh retract \"<il testo esatto del fatto>\""
              ": %s" % (len(visible), CAP, text), file=sys.stderr)
        sys.exit(3)
    # supersede every retract of this exact text, so a fact re-declared after a retract is visible
    # again even when the two land in the same second (see create_fragment's `after`).
    ages = [age for _h, age in retract_ages(hash12(text)) if age != NEG]
    path = create_fragment("Fatti", "- " + text, after=max(ages) if ages else None)
    if len(visible) + 1 == CAP:
        print("handoff: facts %d/%d — cap reached, next fact will be refused — %s"
              % (CAP, CAP, path), file=sys.stderr)
    else:
        print("handoff: fact added — %s" % path)


def do_retract(rest):
    # Hides a fact from the view without touching ANY existing file: the fragment carries the sha1 of
    # the fact's text, and the composer drops every matching fact from a source older than this one
    # (ADR-4). Rewriting the same text afterwards makes it visible again.
    text = one_line(" ".join(rest))
    ages = [age for line, age in visible_facts() if line == "- " + text]
    if not ages:
        print("handoff: no visible fact with that exact text — nothing retracted: %s" % text,
              file=sys.stderr)
        sys.exit(2)
    h = hash12(text)
    # supersede the newest source the fact is visible from, so the retract cannot report success while
    # being a no-op when the fact was written in this same second (see create_fragment's `after`).
    newest = max(a for a in ages) if any(a != NEG for a in ages) else None
    print("handoff: retracted %s — %s" % (h, create_fragment("Ritirati", "- ~ " + h, after=newest)))


def _is_valid_regex(a):
    try:
        re.compile(a)
        return True
    except re.error:
        return False


# --- THE single declaration of this CLI's grammar, for every subcommand, read one and write alike:
# (min args, max args or None for "one or more, joined with a space", per-arg check or None, one example
# value known to fail that check — used only to generate a test, "repo" when a git repository is
# required and "free" when it is not, and the syntax fragment printed in the usage line). `validate()`,
# the usage text and `__spec` (bin/handoff.test.sh) all read this same dict, and handoff.sh has no
# dispatch `case` of its own, so there is exactly ONE list of subcommands anywhere. SPEC and HANDLERS
# are asserted in sync below: a handler added without a SPEC entry cannot run, and a SPEC entry without
# a handler fails on the next invocation of anything — the whole suite catches either immediately.
SPEC = {
    "facts":   (0, 0,    None,            None,  "repo", "facts"),
    "show":    (0, 0,    None,            None,  "repo", "show"),
    "recent":  (0, 1,    lambda a: a == "--all" or bool(re.fullmatch(r'[0-9]+', a)), "abc",
                                                        "repo", "recent N|--all"),
    "grep":    (1, 1,    _is_valid_regex, "[",   "repo", "grep REGEX"),
    "log":     (1, None, None,            None,  "repo", "log \"testo\""),
    "fact":    (1, None, None,            None,  "repo", "fact \"testo\""),
    "retract": (1, None, None,            None,  "repo", "retract \"testo esatto\""),
    "where":   (0, 0,    None,            None,  "free", "where"),
}
HANDLERS = {"facts": do_facts, "show": do_show, "recent": do_recent, "grep": do_grep,
            "log": do_log, "fact": do_fact, "retract": do_retract, "where": do_where}
assert set(SPEC) == set(HANDLERS), "handoff.sh: SPEC and HANDLERS out of sync — every subcommand needs both"


def usage_exit():
    print("usage: handoff.sh " + " | ".join(s[5] for s in SPEC.values()), file=sys.stderr)
    sys.exit(2)


def validate(cmd, rest):
    lo, hi, check, _bad, _kind, _syntax = SPEC[cmd]
    if len(rest) < lo or (hi is not None and len(rest) > hi):
        usage_exit()
    if check:
        for a in rest:
            if not check(a):
                usage_exit()


# A repo is required for everything except the subcommands SPEC marks "free", and for an unknown
# subcommand too — same order as every earlier version, which resolved the toplevel before looking at
# the command at all.
if SPEC.get(cmd, (0, 0, None, None, "repo", ""))[4] != "free" and not root:
    print("handoff: not a git repository", file=sys.stderr)
    sys.exit(1)

if cmd == "__spec":  # internal, used only by bin/handoff.test.sh to generate the tests below
    for name, (lo, hi, _check, bad, kind, syntax) in SPEC.items():
        print("%s %s %s %s %s %s" % (name, lo, "-" if hi is None else hi,
                                     bad if bad is not None else "-", kind, syntax))
elif cmd not in SPEC:
    usage_exit()
else:
    validate(cmd, rest)
    HANDLERS[cmd](rest)
PY
