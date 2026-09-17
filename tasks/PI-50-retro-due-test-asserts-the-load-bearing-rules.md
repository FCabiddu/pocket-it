# PI-50 — The rules retro-due.sh calls load-bearing must be asserted

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: S
**Budget**: 120
**Risk**: high
**Depends on**: PI-16
**Wave**: 1
**Files**: bin/retro-due.test.sh
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**:
**PR**:

## Goal
QF-1's review approved PR #92 and named a cause inside that approval — `false-coverage-evidence`, the very
class QF-1 built the signal for. The finding: `bin/retro-due.sh`'s own header calls certain rules
load-bearing, and the suite does not assert them. Measured by the reviewer on 2026-09-17, against 119 green
assertions: changing `matches[-1]` to `matches[0]` — inverting the "last field-shaped occurrence on a line
wins" rule — leaves the suite at **0 FAIL**. The same holds for the `(?:^|\s)` boundary and for the
recogniser's case-sensitivity.

The suite is green about rules nobody is checking. This does not change *whether* a signal fires — the
reviewer established it can only change the cause *value* — and it is pre-existing: `main` before QF-1 missed
it too. That is why it was non-blocking, and why it is a task rather than a round.

The reviewer also reports that the `instantiate()` placeholder defect QF-1 fixed had **five** assertions
running green against a placeholder fixture, not the three the developer counted, with a sixth going red. A
count of how much was vacuous that is itself wrong by two is the same defect as the one being fixed.

## Acceptance criteria
- [ ] AC1 — Given each rule `bin/retro-due.sh`'s header declares load-bearing, when that rule is inverted in
      the script, then at least one assertion fails and names the rule. Enumerate the declared rules from
      the header itself rather than from this task file's three examples, and show the executed inversion
      for each — a row asserted by reading is not evidence.
- [ ] AC2 — Given a rule the header declares load-bearing that turns out **not** to be — inverting it
      changes nothing observable — when you find one, then say so and do not invent an assertion to cover
      it. A comment claiming a property the code does not have is a finding about the comment.
- [ ] AC3 — Given the cause *value* a line yields (not merely whether it fires), when the recogniser picks
      among several field-shaped occurrences on one line, then the choice is asserted: the last one wins,
      and a test proves the first-one-wins reading fails.
- [ ] AC4 — Given the suite as a whole, when an assertion runs against a fixture that never instantiated —
      a literal placeholder, an empty corpus, a file that was not written — then the run fails naming that,
      instead of passing. This is what let five assertions be green about nothing; the fix is the general
      property, not a recount of those five.
- [ ] AC5 — Given `bash bin/retro-due.test.sh`, when it runs, then it is green and the `ok` count is not
      lower than 119.

## Tests expected
The change is inside the test file; AC1–AC4 are the evidence, each executed. Integration/E2E: not needed.

## Notes
Starting points only, not the boundary of the work: `matches[-1]`, the `(?:^|\s)` boundary, and the
recogniser's case-sensitivity are the three the reviewer measured. AC1 asks for the header's list, not this
list.

`Risk: high` for the reason that governs everything about this script: over-firing is visible and
self-correcting, **under-firing is invisible** — `retro-due: nothing` is what a healthy run prints. An
assertion that cannot fail is indistinguishable from one that passes.

Blocked on PI-16 (PR #93), which also modifies `bin/retro-due.sh` — its composer detector matched a bash
`case` PI-16 deletes. Start from what actually landed there, not from today's file.
