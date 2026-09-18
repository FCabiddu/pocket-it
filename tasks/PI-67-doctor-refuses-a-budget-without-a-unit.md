# PI-67 — `doctor.sh` refuses a `**Budget**` whose value carries no unit

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: XS
**Budget**: 15 min
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/doctor.sh, bin/doctor.test.sh
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**:
**PR**:

## Goal
`**Budget**` is the one number an implementing agent compares itself against, and its unit decides the
comparison: the same bare `120` is read by one agent as 120 minutes and by another as a turn-era figure.
Shared rules §8 and the planner both now say the unit goes in the value — and that is prose asking a writer
to remember. Measured on one board: three task files written on a single day carried `Budget: 120`, `90` and
`60`, all unitless, copied from turn-era sizes that live in estimate facts. The rule needs a refusal, not a
fourth sentence.

## Acceptance criteria
- [ ] AC1 — Given a task file whose `**Budget**` value matches a bare number (optionally spaced, any case,
      `**Budget**:` and `**Budget:**` forms both), when `doctor.sh` runs, then it reports an **error** naming
      the file and the line, and exits non-zero. Given `Budget: 45 min` (or `min.`, `minutes`), then no error.
      Given no `**Budget**` line at all, then the current behaviour is unchanged — this task adds no new
      requirement for the field to exist.
- [ ] AC2 — Given the board of a real project, when `doctor.sh` runs before and after the change, then the
      report says how many files the new check names, and the count is derived by a command pasted into the
      report, not by reading.
- [ ] AC3 — Given `bin/doctor.test.sh`, when it runs, then it covers both directions of AC1 (a unitless value
      is red, a value with the unit is green) and a file where the string `Budget` appears in prose without
      being the field — which must stay green. Mutation executed, not described: remove the check and show
      the new cases turn green.

## Tests expected
`bin/doctor.test.sh` only. No integration or E2E.

## Notes
The check belongs with doctor's other board checks, and keeps doctor's own contract: errors block a launch,
warnings do not. This is an error, because an unusable threshold produces a silent green for the whole task.
