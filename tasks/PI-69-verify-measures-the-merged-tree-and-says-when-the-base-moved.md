# PI-69 — `verify.sh` measures the merged tree, and says when the base moved under the run

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: S
**Budget**: 45 min
**Risk**: medium
**Depends on**: none
**Wave**: 1
**Files**: bin/verify.sh, bin/verify.test.sh
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**:
**PR**:

## Goal
`verify.sh` pins the base commit at the start of the run and measures the **branch**. Two things follow that
nothing in the toolbox reports today. First, a base that advances while a review is in flight leaves a green
that was true about a tree nobody will ever merge: measured in one window, two reviews were running when the
base moved, one of them on a root file inside the scope of the very check under review, and the only reason
anybody noticed was a person watching. Second, any check that walks the repository tree rather than the diff
takes its result from files the branch never touched — such a check is routinely green on the branch and red
one merge later, with git reporting no conflict at all.

## Acceptance criteria
- [ ] AC1 — Given a branch behind its base, when `verify.sh` runs, then the checks are executed on the
      **merged** tree (base merged into the branch inside the throwaway worktree), and the first line says so,
      naming both commits. A merge that conflicts is not a red of the branch: it exits with its own code and a
      line saying the tree could not be built, and nothing is reported as measured.
- [ ] AC2 — Given the base advances between the start and the end of the run, when the run finishes, then the
      last line states it and names the two base commits, whatever the verdict was — a green measured against
      a base that has moved is stale and the reader must see it without re-deriving it.
- [ ] AC3 — Given a branch already up to date with its base, when `verify.sh` runs, then behaviour and exit
      codes are exactly the ones documented today (0 green, 1 own red, 2 could not run, 3 inherited red), and
      the attribution logic keeps comparing against the same base tip it pins now.
- [ ] AC4 — Given `bin/verify.test.sh`, when it runs, then it covers: branch behind the base with a clean
      merge, branch behind with a conflicting merge, base moving mid-run, and branch up to date. Each case is
      proved by a mutation: remove the new step and show the case reports the old, misleading result.

## Tests expected
`bin/verify.test.sh` against disposable local repositories created and removed by the test. No pushes, no
remote, no shared checkout touched.

## Notes
The merge happens only inside the throwaway worktree and is never pushed; the worktree is swept by the traps
already armed at the top of the script. Exit codes are a contract other agents read — AC3 is the guard on it.
