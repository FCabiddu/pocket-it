# PI-49 — A producer the selector drops in silence: the value-quoting dimension

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: XS
**Budget**: 60
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/verify.test.sh
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**:
**PR**:

## Goal
PI-46 closed one dimension of a class and left the other open, measured and named by its reviewer.

`bin/verify.test.sh` selects the producers it builds its sandbox and assertions from, and cross-checks the
count two ways: bash `grep -E 'CMD_[A-Z0-9]+='` against a python `CMD_(\w+)=` ground truth. That cross-check
is genuinely independent on the **name** side — `CMD_E2E_RUN=` and `CMD_Test=` both turn it red at `10 == 11`.

But both selectors share the same **value** pattern, `("[^"]*"|\$\()`. A producer whose value is
single-quoted — `CMD_SQ='go test ./...'` — is therefore invisible to both at once, so the cross-check finds
nothing to disagree about and reports agreement. Measured on the landed code, 2026-09-17: bash 10, python 10,
suite ALL PASS at 145 ok, with the producer silently absent from the sandbox and from every assertion.

The damage is the one that costs most and shows least: **the suite reports success about producers it never
saw.** A wrong red is a re-run; a green that covers nothing is a guard that has stopped guarding without
saying so.

## Acceptance criteria
- [ ] AC1 — Given a producer whose value is written in any form the file's own conventions permit, when the
      selectors run, then it is either selected or the run fails naming it. Silence is the defect; a producer
      dropped without a word is what this task exists to remove.
- [ ] AC2 — Given the cross-check between the two selectors, when one of them is narrowed in a way that
      drops a producer, then they disagree and the suite goes red. Establish that this holds along the
      **value** axis as it already does along the name axis — two checks that share a blind spot are one
      check reported twice. State in the report what the two sides now derive from independently.
- [ ] AC3 — Given the class "a producer the selector drops in silence", when you enumerate its dimensions,
      then say how you established the list is complete — name charset and value quoting are the two known
      today, found one at a time by two different agents, neither of whom was looking for a list. Do not
      assume there are only two because only two have been found.
- [ ] AC4 — Given `bash bin/verify.test.sh`, when it runs, then it is green and the `ok` count is not lower
      than 145.

## Tests expected
The change is inside the test file; AC1–AC3 are the evidence, each executed rather than read.
Integration/E2E: not needed.

## Notes
Starting points only, not the boundary of the work: the value pattern `("[^"]*"|\$\()` shared by both
selectors. `XS` because the shape of the fix is small; the sizing is not a licence to answer AC3 by naming
the two dimensions already known.

Related, but a different defect and a different task: PI-47 (`base_blockers` clears a real script name in
the bare `<pm> <script>` form). Both live in the verify family; do not merge them into one branch.
