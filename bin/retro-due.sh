#!/usr/bin/env bash
# pocket-it retro-due — deterministic answer to "is a retro due, and on what?"
# Usage (project root): bash ~/.claude/agents/pocket-it/bin/retro-due.sh
#
# Reads the handoff log — via bin/handoff.sh's read-only composer (`recent --all`, PI-14) when this
# install has one, else directly from docs/SESSION_HANDOFF.md's "## Log" section plus
# docs/SESSION_HANDOFF_ARCHIVE.md — and counts signals since the last retro-mark line. A signal is any of:
#   (a) a "needs work" line whose cause is present and is not "first-round"
#   (b) the same cause recurring on two different tasks (first-round excluded, same as (a))
#   (c) a task reaching three or more "needs work" lines (signalled once, at the third)
#   (d) any BUDGET or STALL line
# retro-mark line: written by the retro agent, after it merges its own PR (see .claude/agents/retro.md),
# in the exact shape `retro-mark <date> <scope>` — logged with handoff.sh so it lands as a normal log line
# ("- <log date> retro-mark <date> <scope>"). Every line strictly after the most recent one is in scope;
# with no retro-mark at all, the whole log is in scope. Read-only: never writes, never touches git status
# (the composer path inherits this from bin/handoff.sh's own PI-14 guarantee; the fallback path only
# ever opens files for reading).
#
# Exit codes: 0 = "retro-due: nothing" (no signals); 10 = "RETRO DUE: <n> segnali" followed by one line per
# signal ("<task> — <tipo> — <riga di log>"); 2 = input error (not run inside a git repository).
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "retro-due: not a git repository" >&2; exit 2; }
HANDOFF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/handoff.sh"
python3 - "$ROOT" "$HANDOFF" <<'PY'
import sys, os, re, subprocess

root, handoff = sys.argv[1], sys.argv[2]

# A real id: a letter-led prefix (alphanumeric segments allowed, e.g. E2E, I18N), one or more -/. segments,
# with a digit required somewhere past the first hyphen — same shape as next-wave.sh/doctor.sh, kept
# identical on purpose. A date (2026-09-13) never matches: it does not start with a letter.
ID_RE = re.compile(r'(?=[A-Za-z][A-Za-z0-9]*-[^\s:]*\d)([A-Za-z][A-Za-z0-9]*(?:[-.][A-Za-z0-9]+)+)')
CAUSE_RE = re.compile(r'cause:\s*(.+?)\s*$')
MARK_RE = re.compile(r'\bretro-mark\b')
BUDGET_RE = re.compile(r'\bBUDGET\b')
STALL_RE = re.compile(r'\bSTALL\b')


def read_log_section(path):
    """Newest-first lines from the '## Log' section of SESSION_HANDOFF.md. [] if file/section absent."""
    if not os.path.exists(path):
        return []
    text = open(path, errors="ignore").read()
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
    text = open(path, errors="ignore").read()
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
    """Newest-first via `handoff.sh recent --all` — the read-only composer (frozen files + fragments,
    PI-14/PI-16). None on any failure, so the caller can fall back rather than crash."""
    try:
        r = subprocess.run(["bash", handoff, "recent", "--all"], capture_output=True, text=True)
    except OSError:
        return None
    if r.returncode != 0:
        return None
    return [l for l in r.stdout.split("\n") if l.startswith("- ")]


def read_log(root, handoff):
    if has_composer(handoff):
        newest_first = read_log_composer(handoff)
        if newest_first is not None:
            return list(reversed(newest_first))
    return read_log_fallback(root)


def extract_id(line):
    m = ID_RE.search(line)
    return m.group(1) if m else "?"


def strip_marker(line):
    return line[2:] if line.startswith("- ") else line


chronological = read_log(root, handoff)

mark_idx = -1
for i, line in enumerate(chronological):
    if MARK_RE.search(line):
        mark_idx = i
since_mark = chronological[mark_idx + 1:] if mark_idx >= 0 else chronological

signals = []
needs_work_count = {}
cause_first_task = {}
for line in since_mark:
    if MARK_RE.search(line):
        continue
    tid = extract_id(line)
    if BUDGET_RE.search(line):
        signals.append((tid, "budget", line))
        continue
    if STALL_RE.search(line):
        signals.append((tid, "stall", line))
        continue
    if "needs work" in line:
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
PY
