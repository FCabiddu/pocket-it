# pocket-it handoff — THE ONE HOME for "what a record is" in the handoff memory.
#
# Every script that reads or writes pocket-it's narrative memory loads this file and nothing of its own:
# bin/handoff.sh (the composer and the three writers) and, from PI-43, bin/retro-due.sh's fallback
# readers. It is loadable two ways, so no caller needs a copy:
#
#   sh:     { cat "$(dirname "$0")/handoff_sections.py"; cat; } | python3 - "$@"     # prepend, as handoff.sh does
#   python: sys.path.insert(0, os.path.dirname(__file__)); from handoff_sections import split_section
#
# THREAT MODEL (PI-40, kept by PI-16). This memory is free text written by agents, and it legitimately
# quotes its own markers: a fact explaining how to read the log carries "## Log" inside its text. Such a
# quote is DATA. What the two rules below protect against is a heading, or a whole section of facts,
# being created or destroyed by the mere act of writing a line — which is how the original defect lost
# real facts twice on a real project.
#
#   (1) READER SIDE — a heading is "## " at the START OF A LINE, nowhere else (split_section), and a
#       record is a "- " line delimited by "\n" and by nothing else (dash_lines, read_text). The earlier
#       reader used s.partition("## Log"), a substring match, so the first fact quoting the marker took
#       the heading's place: the real heading was dropped (it does not start with "- ") and every fact
#       below the quote was reclassified as a log line.
#   (2) WRITER SIDE — what a write appends is ONE record: one_line() collapses the newlines in the
#       CALLER'S OWN TEXT before any other rule looks at it. A newline is the only character that can
#       move the caller's text to the start of a line, so collapsing it here is what makes a heading
#       impossible to introduce as data, whatever the argument is and from whichever writer. No marker
#       blacklist is needed or wanted: after this, a marker can only ever land mid-line.
#
# The ORDER in (2) is load-bearing and is not to be rearranged: one_line() runs BEFORE handoff.sh's
# PI-39 leading-date strip, because that strip matches a date followed by a SPACE — a date followed by a
# newline escapes it, and a collapse applied afterwards glues the caller's date to the one the writer
# prepends, reintroducing exactly what PI-39 exists to prevent.
#
# Deliberately NOT covered: a heading whose own text is wrong or duplicated (two real "## Log" headings
# — the first wins, as before); and any reader living outside the scripts that load this file.

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
    # body of the first "## {name}..." section, up to the next "## " heading or EOF -- the same
    # extraction the pre-PI-14 `awk '/^## Fatti/{f=1;next} /^## /{f=0} f && /^- /'` performed, so the
    # composer stays byte-identical to it on a memory with no fragments.
    return split_section(text, name)[2]


def dash_lines(body):
    # split ONLY on "\n" -- never str.splitlines(), which also breaks on \v \f \x1c-\x1e U+0085 U+2028
    # U+2029 and a lone \r, characters awk's default RS="\n" treats as ordinary data. Splitting on those
    # truncates a line silently: the tail after the character doesn't start with "- " and is dropped.
    return [l for l in body.split('\n') if l.startswith("- ")]


def read_text(path):
    # newline='' disables universal-newline translation: CR, CRLF and every other line-ish byte stay as
    # literal data in the string, exactly like awk (RS="\n") sees them -- only a bare "\n" ends a record.
    with open(path, encoding="utf-8", newline='') as f:
        return f.read()


def one_line(text):
    # Writer side of the threat model above. Collapse every "\n" in the caller's own text to a space, so
    # what the writer appends is ONE record. Called FIRST by every writer, before any other rule reads
    # the text (see the order note in the header). The other line-ish characters (\r \v \f \x1c-\x1e
    # U+0085 U+2028 U+2029) are data for every reader here and are left byte for byte, so a line holding
    # one still reads back exactly as written.
    return text.replace("\n", " ")
