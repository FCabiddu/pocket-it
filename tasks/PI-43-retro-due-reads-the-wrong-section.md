# PI-43 — retro-due.sh reads the wrong section and answers "nothing"

**Status**: Todo
**Label**: DevOps
**Epic**: pipeline-improvements
**Story**: pipeline-improvements
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: high
**Depends on**: none
**Wave**: 1
**Files**: bin/retro-due.sh, bin/retro-due.test.sh
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**:
**PR**:

## Goal
`read_log_section`, `read_archive` and `check_main_structure` locate their section with an
unanchored `partition("## Log")` / `partition("## Log archiviato")` / `"## Log" not in text`.
Any line anywhere in the file that merely *contains* the marker — a fact that quotes it, a
sentence that names it, a fenced code block that shows it — is matched first, so the script
reads the wrong region.

Measured on a real project file: the script reads **0 log lines** out of 40 and exits
`retro-due: nothing`. The trigger is silently disarmed: needs-work signals, BUDGET and STALL
lines are never seen, and `check_main_structure` — written precisely to refuse a file with no
log section — passes on a file whose only occurrence of the marker is inside a quoted fact.

An empty read must never be indistinguishable from "no signals".

## Acceptance criteria
- [ ] AC1 — Given a handoff file in which the marker text appears anywhere other than as its own
      heading, when the script reads the log section, then it reads the real section: this holds
      for the whole class of non-heading occurrences (start of a line, mid-line, indented, inside
      a fenced block, with trailing whitespace, in a fact that quotes it, appearing before and
      after the true heading), not only the cases named here.
- [ ] AC2 — Given a file that genuinely has no log heading, when the script runs, then it raises
      the existing `InputError` — a quoted or code-fenced occurrence must not satisfy the
      structure check.
- [ ] AC3 — Given the real signals are present (needs-work, BUDGET, STALL, and every other signal
      the script scores), when the log section is preceded by such a quoted occurrence, then the
      exit code and the printed signal lines are identical to the same file without it.
- [ ] AC4 — Given the archive file, when it is read, then the same anchoring rule applies to
      `## Log archiviato`, including its `src = tail if sep else text` fallback.
- [ ] AC5 — Given a section whose heading is the last one in the file, when it is read, then its
      lines are returned in full (no truncation at a marker that does not exist).
- [ ] AC6 — Given the section-splitting logic now shared with `bin/handoff.sh` (PI-40 introduced
      `split_section` there), when the two scripts classify the same file, then they agree on where
      every section begins and ends — one rule, one home, not two copies that can drift.

## Tests expected
One case in `bin/retro-due.test.sh` per criterion, each asserting on the script's own output
(counted lines and exit code), plus a mutation run: removing the anchor must turn the suite red.
Integration/E2E: not needed.

## Notes
Occurrences: `bin/retro-due.sh` lines ~113 (`check_main_structure`), ~123 (`read_log_section`),
~136 (`read_archive`). The identical defect in `bin/handoff.sh` is PI-40 (PR #81, in review) —
read PI-40's landed `split_section` before writing a second implementation. There the bug
*destroyed* data; here it is read-only, which is why it went unnoticed longer.
