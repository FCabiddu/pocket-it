# PI-47 — The bare `<pm> <script>` form must not clear a script that shares a subcommand's name

**Status**: Done
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: PI-46
**Wave**: 1
**Files**: bin/verify.sh, bin/verify.test.sh
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**: task/pi-47-bare-form-clears-scripts
**PR**: https://github.com/FCabiddu/pocket-it/pull/94

## Goal
`base_blockers` in `bin/verify.sh` keeps a list of package-manager subcommands (`pmsub`) so that a command
like `npm install` is not mistaken for a package script. In the **bare** form the managers accept —
`<pm> <script>`, with no `run` — that list is applied to a token that may well be a real script name.
Measured by the PI-46 review on 2026-09-16, against a tree declaring **no** scripts at all: `npm pack`,
`npm publish`, `npm version` and `npm update` are all **cleared** — `base_blockers` returns no blocker, so
the base run is treated as a comparable check — while `npm run pack` is correctly refused. `pack`,
`publish`, `version` and `update` are ordinary package-script names.

The damage is the one direction the guard exists to prevent: a project whose `testCommand` uses the bare
form gets **exit 3, "inherited"** — the branch's failure attributed to the base — for a red the branch owns.
A wrong green is the failure mode that costs; a wrong red only costs a re-run.

Pre-existing behaviour from PI-41, surfaced by PI-46's review, not introduced by it.

## Acceptance criteria
- [x] AC1 — Given a command in the bare `<pm> <script>` form whose token is also a package-manager
      subcommand, and a base tree that does not declare that script, when `base_blockers` runs, then it
      returns a blocker. The check must not depend on which words are on the list today.
- [x] AC2 — Given a command in the bare form whose token is unambiguously a manager subcommand in a tree
      that declares no such script (`npm install`, `npm ci`), when `base_blockers` runs, then the behaviour
      is unchanged from today. State in the report how the two cases in AC1 and AC2 are told apart, and what
      evidence the distinction rests on — a token's spelling alone cannot carry it.
- [x] AC3 — Given the ambiguity cannot be resolved from the token, when the script must choose, then it
      chooses the blocker: an unproven "the base is red too" is the failure this task exists to remove, and
      an extra blocker costs only a branch-attributed red. Show the case where the choice is forced and name
      which way it goes.
- [x] AC4 — Given `bin/verify.test.sh`, when it runs, then the four measured cases (`pack`, `publish`,
      `version`, `update` in the bare form, against a tree declaring no scripts) are asserted by name, and
      the assertion is derived from the class rather than from those four words. Prove the assertion can
      fail: mutate the fix away and show the named reds.
- [x] AC5 — Given the full `bin/verify.test.sh` suite, when it runs, then it is green and the `ok` count is
      not lower than before this change.

## Tests expected
Unit assertions in `bin/verify.test.sh` alongside the existing `base_blockers` probes. Integration/E2E: not needed.

## Notes
Starting points only, not the boundary of the work: `bin/verify.sh:149` declares `pmsub`; the bare-form
branch is the one that consults it without a preceding `run`. The rule this task serves is the one
`base_blockers` was built for in PI-41: **exit 3 may only be reported on positive evidence that the base
runs the same check.** Anything the script has not established degrades to the branch's own red.

Do not fold this into a change of the `pmsub` list's contents. Adding or removing words moves which
projects are hurt, not whether the form can be told apart from a script name; PI-46 separately anchors that
list against the test so it can no longer drift unnoticed.
