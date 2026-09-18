# PI-48 — The two self-mutating blocks in cleanup-merged.test.sh must use the shared gate

**Status**: In Review
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: PI-45
**Wave**: 1
**Files**: bin/cleanup-merged.test.sh, bin/self-mutation-gate.sh (new), bin/doctor.test.sh, tasks/PI-48-cleanup-test-self-mutation-reuses-the-gate.md
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**: task/pi-48-cleanup-test-reuses-gate
**PR**: https://github.com/FCabiddu/pocket-it/pull/112

## Goal
Two blocks in `bin/cleanup-merged.test.sh` build a mutant from the live `$SCRIPT` and then run assertions
that are not gated on the mutation having actually applied: around line 322 (PI-31 AC5) and around line 503
(PI-38 AC5). Identified by PI-45's developer, confirmed by PI-45's reviewer as the same defect class as the
six sites PI-45 closed in `bin/doctor.test.sh`, and deliberately left out of that PR because the file was
owned by a concurrent agent at the time. PR #84 has since merged; the file is free.

The damage is PI-45's damage: **a test failure that names the wrong test.** When the mutation silently fails
to apply — the anchor moved, the substitution matched nothing, the range ran past its end — the downstream
assertions run against an unmutated or truncated script and fail under some other assertion's name, or pass
and report success about a mutation that never happened.

## Acceptance criteria
- [ ] AC1 — Given each of the two blocks, when its mutation does not apply, then the run fails under a check
      that names self-mutation, and never under a downstream assertion's name.
- [ ] AC2 — Given PI-45 built a shared gate in `bin/doctor.test.sh` for exactly this, when these two blocks
      are fixed, then they **use** that gate rather than a second implementation of it. If the gate is not
      reachable from this file as it stands, moving it to a place both files read is the work; two copies
      that can drift is the defect one layer up, and copying it is not an acceptable outcome of this task.
- [ ] AC3 — Given the anchor-loss cases PI-45 enumerated — opening anchor lost, closing anchor lost, either
      one doubled, and a substitution that matches nothing — when each is executed against these two blocks,
      then each produces a failure that names self-mutation. Execute them; a table asserted by reading is not
      evidence. State for each row whether it was run or read.
- [ ] AC4 — Given the whole file, when it is searched for blocks that build a mutant from the live script,
      then the number found equals the number gated, and the file fails itself if a block declares a mutation
      without the gate — the property PI-45 established for its own file. Derive the two sides of that
      equality from **independent** sources: a count and a check that both come from the same pattern can
      never disagree, and the self-check is then decorative.
- [ ] AC5 — Given `bash bin/cleanup-merged.test.sh`, when it runs, then it is green and the `ok` count is not
      lower than before this change.

## Tests expected
The change is inside the test file itself; AC3 and AC4 are the evidence. Integration/E2E: not needed.

## Notes
Starting points only, not the boundary of the work: `bin/cleanup-merged.test.sh` ~322 (PI-31 AC5) and ~503
(PI-38 AC5). AC4 exists precisely because those two were found by another agent reading a different file —
nobody has yet established that this file has only two.

Blocked on PI-45 (PR #85) landing, because AC2 requires reusing the gate that PR builds. Do not start before
it merges, and do not anticipate its shape: read what actually landed.

**Measured at implementation time (the title's "two" is wrong):** the file has **four** self-mutating
blocks, not two — `grep -n 'sed .*"\$SCRIPT"' bin/cleanup-merged.test.sh` at lines 371, 607, 630 and 640 on
the pre-change file. AC4 was the criterion that asked; this is its answer. The title is left as it was filed
so the id and the filing are not rewritten after the fact.

**`**Files**` above was re-derived from the branch, not from this note:**
`git diff --name-only $(git merge-base origin/main HEAD) HEAD` on `task/pi-48-cleanup-test-reuses-gate`.
`docs/reports/**` and `docs/handoff/**` are on the branch too and are deliberately not listed: PI-65 AC4
excludes those two prefixes by name, while the task file itself is not on that exclusion list, so it is.
