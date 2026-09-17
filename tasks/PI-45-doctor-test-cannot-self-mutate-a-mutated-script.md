# PI-45 — doctor.test.sh non sa mutare uno script già mutato, e ne incolpa altri test

**Status**: Done
**Label**: DevOps
**Epic**: pipeline-improvements
**Story**: pipeline-improvements
**Priority**: Should
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/doctor.test.sh
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**: task/pi-45-doctor-test-self-mutation
**PR**: https://github.com/FCabiddu/pocket-it/pull/85

## Goal
`mutate_has_section()` (`bin/doctor.test.sh`, ~lines 1006-1020) builds its patched copy by reading
the **current** `$SCRIPT` and doing a verbatim search-and-replace of `_has_section`'s literal source
text, asserting the substitution count is exactly 1. That assumes `$SCRIPT` still holds that exact,
unmutated text.

When a reviewer runs the suite against an externally mutated `bin/doctor.sh` — the normal way to
prove a suite is not vacuous — the assertion fails and the failure cascades. Measured: 16 FAILs, of
which **9 were artifacts** of this collision, including malformed-range, unrecognised-qualifier and
AC5 assertions that never call `_has_section` at all. The real regressions were separable only by
re-running the suite a second time with that block removed.

A mutation test that cannot run on a mutated script is fragile exactly where it is supposed to be
strongest, and worse than fragile: it accuses tests that are fine. The damage to prevent is a test
failure that names the wrong test.

## Acceptance criteria
- [x] AC1 — Given `bin/doctor.sh` has been modified before the suite runs, in any way and anywhere,
      when the suite runs, then no assertion that does not depend on the modified code reports a
      failure caused by it. The invariant is isolation between checks, not the one function named
      here.
- [x] AC2 — Given the self-mutation cannot be applied, when that happens, then the suite says so in
      its own named error ("cannot self-mutate: source text not found") and fails only that check —
      never an opaque assertion whose failure is indistinguishable from a real regression.
- [x] AC3 — Given the suite mutates the script, when it does, then it mutates a copy of the content
      it captured for itself, not whatever `$SCRIPT` currently contains — so two mutations in the
      same run, or an external one, cannot interfere.
- [x] AC4 — Given any other self-mutating block in this file or its siblings makes the same
      assumption, when this task is done, then it has been found and closed too; the fix is the rule,
      not the single call site.
- [x] AC5 — Given a genuine regression in `_has_section`, when the suite runs, then it is still
      caught and still reported against the right check — the isolation must not buy silence.

## Tests expected
A case that runs the suite against a pre-mutated `bin/doctor.sh` and asserts the failure set is
exactly the checks that depend on the mutated code, plus a case for the named self-mutation error.
Integration/E2E: not needed.

## Notes
Found by the PI-42 reviewer while proving its own non-vacuity check, not by a failing run —
the suite is green in normal use, which is why it survived. The cascade is only visible to whoever
mutates the script from outside, i.e. exactly the reviewer role.
