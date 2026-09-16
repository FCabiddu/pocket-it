# PI-41 — verify.sh must tell a defect the PR introduced from one it inherited

**Status**: Done
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: M
**Budget**: 200
**Risk**: high
**Depends on**: none
**Wave**: 1
**Files**: bin/verify.sh, bin/verify.test.sh
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**: task/pi-41-verify-base-red-attribution
**PR**:

## Goal
`bin/verify.sh` reports `verify: RED` whenever any check fails, with no way for the caller to
tell **who broke it**. Twice now a check went red on a branch whose own diff was clean, because
a defect had landed on the base branch underneath it; both times a reviewer spent a full
needs-work round diagnosing it by hand, re-checking out the base tip in a separate worktree to
prove the failure was already there. The retrospective of 2026-09-15 recorded `base-moved` as a
repeated review cause and proposed exactly this fix.

When a check fails, `verify.sh` must find out for itself whether that same check already fails
on the tip of the base branch, and say which of the two it is. The reviewer must be able to act
on the verdict without re-deriving it.

## Acceptance criteria
- [x] AC1 — Given a branch whose diff introduces a failing check, when `verify.sh` runs, then it
      reports the failure as the branch's own and exits with the code that already means "the
      branch is red" today. Nothing about the existing own-diff-red path changes.
- [x] AC2 — Given a branch whose checks fail **and** whose failure is already present at the tip
      of `origin/{base}`, when `verify.sh` runs, then the output names that check as pre-existing
      on the base and the overall verdict is distinguishable from AC1's **by a caller that reads
      only the exit code**, not only by a human reading the prose. State in the report which
      encoding you chose and why a reader cannot confuse the two.
- [x] AC3 — Given a run where some checks fail on the branch only and others fail on the base
      too, when `verify.sh` runs, then each failing check is attributed individually and the
      overall verdict is the **worse** of the two (a branch that introduces its own defect is not
      excused by also inheriting one).
- [x] AC4 — Given any run in which every check passes, when `verify.sh` runs, then no base
      re-check happens at all: the second worktree is never created and the elapsed cost of a
      green run is unchanged. Only checks that actually failed are re-run against the base, at
      most once each.
- [x] AC5 — Given the base re-check, when it runs, then it obeys every invariant the existing
      run already obeys — it happens in a throwaway worktree under `<repo>/.claude/worktrees/`
      and never in `/tmp`; the `guard` that refuses to run anything outside that worktree covers
      it too; the signal traps clean up **both** worktrees on INT/TERM/HUP/EXIT, leaving none
      behind. Prove the trap case by sending a real signal mid-run, not by reading the code.
- [x] AC6 — Given the base re-check cannot be performed at all (base ref unfetchable, worktree
      creation refused, the check itself erroring in a way distinct from failing), when that
      happens, then `verify.sh` says the attribution is unknown and falls back to today's plain
      red — it never reports "pre-existing on base" on the strength of a re-check that did not
      actually run.

## Tests expected
One test per criterion in `bin/verify.test.sh`, each against a disposable git repo the test
builds and removes. Fixtures needed: a base that is green with a branch that breaks a check; a
base that is already broken with a branch that changes nothing relevant; a branch that does both.
Prove the attribution by mutation — make the base green again and the same run must flip from
"pre-existing" to the branch's own red, and back.

## Notes
Damage to prevent, stated as damage: **a reviewer must never be made to diagnose, by hand, whose
defect a red check is** — and the inverse damage matters just as much: a branch's own failure
must never be excused as inherited. Both directions have a test.

Cost is part of the contract, not an afterthought: a green run is the common case and must not
pay anything for this feature (AC4), and a red run pays for the failing checks only.

Same family as PI-39 and PI-40: a signal read out of a shared artefact without establishing where
it came from. Here the missing step is provenance, not anchoring.

The retro's own words, for the record: "when an assertion is RED, re-run it against a clean
worktree of origin/{base}'s tip before reporting; if already red there, report it distinctly from
an own-diff RED."
