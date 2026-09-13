#!/usr/bin/env bash
# pocket-it retro-due — deterministic answer to "is a retro due, and on what?"
# Usage (project root): bash ~/.claude/agents/pocket-it/bin/retro-due.sh   (no arguments)
#
# Reads the handoff log — via bin/handoff.sh's read-only composer (`recent --all`, PI-14) when this
# install declares one, else directly from docs/SESSION_HANDOFF.md's "## Log" section plus
# docs/SESSION_HANDOFF_ARCHIVE.md — and counts signals since the last retro-mark line. A signal is any of:
#   (a) a "needs work" line whose cause is present and is not "first-round"
#   (b) the same cause recurring on two different tasks (first-round excluded, same as (a))
#   (c) a task reaching three or more "needs work" lines (signalled once, at the third)
#   (d) any BUDGET or STALL line
# retro-mark line: written by the retro agent (see .claude/agents/retro.md), in the EXACT anchored shape
# "- <log date> retro-mark <date> <scope>" — a real signature, not a word that happens to appear in prose,
# a log line's own description, a fact or a PR title (round 2 finding: the plain \bretro-mark\b word match
# hid every real signal behind the PR's own "… retro-due.sh … retro-mark write …" log line). Every line
# strictly after the most recent real mark is in scope; with no mark at all, the whole log is in scope.
#
# "needs work" / BUDGET / STALL are recognised only in the shape implementing-common.md §6/§8 actually
# produce (round 2 finding: a bare substring search also counted BUDGET/STALL named in an unrelated log
# line's own description, and counted a skill's own PR-closing log line — "QF-{n} PR #{m} needs work — …"
# — as a second needs-work round on top of the reviewer's; quickfix's closing status word is now
# "needs-work", hyphenated, precisely so it never collides with this anchor).
#
# Read-only: never writes, never touches git status (the composer path inherits this from bin/handoff.sh's
# own PI-14 guarantee; the fallback path only ever opens files for reading).
#
# Exit codes: 0 = "retro-due: nothing" (no signals); 10 = "RETRO DUE: <n> segnali" followed by one line per
# signal ("<task> — <tipo> — <riga di log>"); 2 = input error — no arguments are accepted, a frozen source
# exists but cannot be read as a plain text file, the main handoff file exists but has no "## Log" section,
# a declared composer fails instead of being silently skipped, or not run inside a git repository. Every
# other unexpected failure also maps to exit 2 (round 2 finding: a bare crash exited 1, outside the 0/10/2
# contract every caller relies on).
set -uo pipefail
[[ $# -eq 0 ]] || { echo "usage: retro-due.sh (no arguments)" >&2; exit 2; }
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "retro-due: not a git repository" >&2; exit 2; }
HANDOFF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/handoff.sh"
python3 - "$ROOT" "$HANDOFF" <<'PY'
import sys, os, re, subprocess

root, handoff = sys.argv[1], sys.argv[2]

# A real id: a letter-led prefix (alphanumeric segments allowed, e.g. E2E, I18N), one or more -/. segments,
# with a digit required somewhere past the first hyphen — same shape as next-wave.sh/doctor.sh, kept
# identical on purpose. A date (2026-09-13) never matches: it does not start with a letter.
ID_RE = re.compile(r'(?=[A-Za-z][A-Za-z0-9]*-[^\s:]*\d)([A-Za-z][A-Za-z0-9]*(?:[-.][A-Za-z0-9]+)+)')
DATE = r'\d{4}-\d{2}-\d{2}'
# The mark's EXACT written shape (retro.md): "- <log date> retro-mark <date> <scope>", scope one token,
# nothing else on the line. Anchored start-to-end so it can never fire on a line that merely mentions the
# word — a draft/fix log line, a PR title ("retro-mark: {scope}"), a fact, or a needs-work line.
MARK_RE = re.compile(rf'^- {DATE} retro-mark {DATE} \S+$')
# BUDGET/STALL are the 2nd token, right after the date — implementing-common.md §8's own shape
# ("- <date> BUDGET <ID> …" / "- <date> STALL <ID> …") — never a word search across the whole line.
BUDGET_RE = re.compile(rf'^- {DATE} BUDGET\b')
STALL_RE = re.compile(rf'^- {DATE} STALL\b')
# A real review round: "<ID> PR #<n> needs work …" (reviewer.md), the ID and "PR #<n>" always immediately
# before it, with no em-dash in between — an em-dash starts the free-text description that follows. This
# also excludes a skill's own PR-closing log line, which never uses this two-word, space-separated form.
NEEDS_WORK_RE = re.compile(r'PR #\d+[^—]*\bneeds work\b')
# The cause value stops at the first em-dash: reviewer.md's own line shape is
# "cause: {taxonomy} — fix at: {destination}" — the old non-anchored ".+?$" swallowed "— fix at: …" too,
# so no two "cause: X — fix at: A" / "cause: X — fix at: B" pair (b)'s own diagnostic case ever compared
# equal.
CAUSE_RE = re.compile(r'cause:\s*([^—]+)')


class InputError(Exception):
    """Any condition that makes the answer unknowable rather than 'nothing due' — exit 2, never 0/10."""


def check_readable(path):
    """None if the path is simply absent (not an error: an empty/fresh project has no handoff yet). Raises
    otherwise — a directory where a file is expected, a permission error, a decoding failure — so a broken
    source is never mistaken for an empty one."""
    if not os.path.exists(path):
        return
    if not os.path.isfile(path):
        raise InputError(f"{path} exists but is not a regular file")
    try:
        with open(path, encoding="utf-8") as f:
            f.read()
    except Exception as e:
        raise InputError(f"cannot read {path}: {e}")


def check_main_structure(path):
    """The main handoff file, when it exists and is readable, must actually have a '## Log' section —
    a file that exists but was never given one (hand-built, truncated, from a version predating it) must
    not silently read as 'nothing due'."""
    if not os.path.exists(path):
        return
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if "## Log" not in text:
        raise InputError(f"{path} exists but has no '## Log' section")


def read_log_section(path):
    """Newest-first lines from the '## Log' section of SESSION_HANDOFF.md. [] if the file is absent
    (readability and structure are already proven by the checks above)."""
    if not os.path.exists(path):
        return []
    text = open(path, encoding="utf-8").read()
    head, sep, tail = text.partition("## Log")
    if not sep:
        return []
    _, _, body = tail.partition("\n")
    body = body.split("\n## ")[0]
    return [l for l in body.splitlines() if l.startswith("- ")]


def read_archive(path):
    """Oldest-first lines from SESSION_HANDOFF_ARCHIVE.md. [] if the file is absent."""
    if not os.path.exists(path):
        return []
    text = open(path, encoding="utf-8").read()
    head, sep, tail = text.partition("## Log archiviato")
    src = tail if sep else text
    return [l for l in src.splitlines() if l.startswith("- ")]


def read_log_fallback(root):
    """docs/SESSION_HANDOFF.md + its archive, oldest to newest overall. Read-only."""
    newest_first = read_log_section(os.path.join(root, "docs", "SESSION_HANDOFF.md"))
    oldest_first_archive = read_archive(os.path.join(root, "docs", "SESSION_HANDOFF_ARCHIVE.md"))
    return oldest_first_archive + list(reversed(newest_first))


def has_composer(handoff):
    """bin/handoff.sh grows the recent/grep read-only composer at PI-14 — detect it by its own
    case-statement grammar rather than assuming a fixed pocket-it version is installed everywhere."""
    if not os.path.isfile(handoff):
        return False
    src = open(handoff, errors="ignore").read()
    return re.search(r'facts\|show\|recent\|grep', src) is not None


def read_log_composer(handoff):
    """Newest-first via `handoff.sh recent --all`. Raises InputError on any failure — a declared composer
    that cannot answer is a different fact from 'no signals', and must never look the same (round 2
    finding; same class as the 'gh cannot answer vs gh says no' fact already in this project's memory)."""
    try:
        r = subprocess.run(["bash", handoff, "recent", "--all"], capture_output=True, text=True)
    except OSError as e:
        raise InputError(f"cannot run composer {handoff}: {e}")
    if r.returncode != 0:
        raise InputError(
            f"composer {handoff} recent --all failed (exit {r.returncode}): {r.stderr.strip()[:200]}"
        )
    return [l for l in r.stdout.split("\n") if l.startswith("- ")]


def read_log(root, handoff):
    if has_composer(handoff):
        return list(reversed(read_log_composer(handoff)))
    return read_log_fallback(root)


def extract_id(line):
    m = ID_RE.search(line)
    return m.group(1) if m else "?"


def strip_marker(line):
    return line[2:] if line.startswith("- ") else line


def run():
    check_readable(os.path.join(root, "docs", "SESSION_HANDOFF.md"))
    check_readable(os.path.join(root, "docs", "SESSION_HANDOFF_ARCHIVE.md"))
    check_main_structure(os.path.join(root, "docs", "SESSION_HANDOFF.md"))

    chronological = read_log(root, handoff)

    mark_idx = -1
    for i, line in enumerate(chronological):
        if MARK_RE.match(line):
            mark_idx = i
    since_mark = chronological[mark_idx + 1:] if mark_idx >= 0 else chronological

    signals = []
    needs_work_count = {}
    cause_first_task = {}
    for line in since_mark:
        if MARK_RE.match(line):
            continue
        tid = extract_id(line)
        if BUDGET_RE.match(line):
            signals.append((tid, "budget", line))
            continue
        if STALL_RE.match(line):
            signals.append((tid, "stall", line))
            continue
        if NEEDS_WORK_RE.search(line):
            needs_work_count[tid] = needs_work_count.get(tid, 0) + 1
            m = CAUSE_RE.search(line)
            cause = m.group(1).strip() if m else None
            if cause and cause != "first-round":
                signals.append((tid, "needs-work-cause", line))
                prior = cause_first_task.get(cause)
                if prior is None:
                    cause_first_task[cause] = tid
                elif prior != tid:
                    signals.append((tid, "same-cause", line))
            if needs_work_count[tid] == 3:
                signals.append((tid, "repeat-needs-work", line))

    if not signals:
        print("retro-due: nothing")
        sys.exit(0)

    print(f"RETRO DUE: {len(signals)} segnali")
    for tid, kind, line in signals:
        print(f"{tid} — {kind} — {strip_marker(line)}")
    sys.exit(10)


try:
    run()
except InputError as e:
    print(f"retro-due: {e}", file=sys.stderr)
    sys.exit(2)
except Exception as e:
    print(f"retro-due: unexpected error: {e}", file=sys.stderr)
    sys.exit(2)
PY
