# PI-46 — Derive package-script names in the verify sandbox, and name the borrowed-node_modules limit

**Status**: Needs Work
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/verify.sh, bin/verify.test.sh
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**:
**PR**:

## Goal
Two loose ends left open by PI-41, both about a check that can pass while proving nothing.

(a) `bin/verify.sh:111` and `:279` symlink the main checkout's `node_modules` into both the branch tree and
the base tree, so the two runs share one directory. A branch check that writes into it — a generated client,
a cache, a compiled artifact — changes the base re-run's inputs as well, and the base can then go red for a
reason that has nothing to do with the base. Exit 3 ("inherited") is then reported for a failure the base
does not actually have. Measured on 2026-09-16: with the write, exit 3; the base tree run alone, exit 0;
the control without the write, exit 1. The script's threat-model comment at `:139-141` lists what it
deliberately does not settle, and this is missing from that list. Nothing in an exit code can settle it
either, so the fix is the sentence, not a guard.

(b) `bin/verify.test.sh:528` hand-types the package scripts the sandbox declares
(`lint`, `type-check`, `typecheck`, `test:affected`, `test`). Every other dimension of that sandbox is
already derived from the producers' own commands — `:562-563` creates the paths each command names,
`:569` creates the binaries it names — so a producer added tomorrow that names a script not on that typed
list makes `base_blockers` answer "script not declared here" and the assertion passes for the wrong reason:
green because the tree is wrong, not because the rule works.

## Acceptance criteria
- [ ] AC1 — Given the set of producers the test enumerates, when the `full` sandbox is built, then every
      package script any producer names is declared in its `package.json`, derived from the commands
      themselves; adding a producer that names a script never seen before needs no edit to the sandbox.
- [ ] AC2 — Given a producer whose command invokes a package manager (`npm`, `pnpm`, `yarn`, `bun`) with a
      `run` subcommand or in the bare `<pm> <script>` form those managers accept, when the script name is
      derived, then the name taken is the script and never the subcommand, a flag, or an argument that
      follows it. State in the report how you established the derivation covers the whole class of
      invocation shapes the producers can emit, not the shapes that happen to exist today.
- [ ] AC3 — Given the `marked` sandbox, whose purpose is to be the `full` one MINUS the package scripts and
      minus every named file, when AC1's derivation lands, then that subtraction still holds — `marked` must
      not inherit the derived scripts. A green run of the existing assertions is not evidence for this on its
      own: show the mutation that proves `marked` still answers "not declared".
- [ ] AC4 — Given `bin/verify.sh`'s "Not covered, deliberately" list at `:139-141`, when it is read, then it
      names the shared-`node_modules` case in the same register as the entries already there: what the script
      cannot settle and why, never a cause it has not established and never a promise to fix it.
- [ ] AC5 — Given the full `bin/verify.test.sh` suite, when it runs, then it is green, and the count of
      assertions is not lower than before this change.

## Tests expected
The change to `bin/verify.test.sh` is itself the test for AC1–AC3; AC3 asks for an executed mutation, not a
claim. AC4 is prose in a comment and needs no test. Integration/E2E: not needed.

## Notes
The invariant behind both halves: **a check must not be able to pass for a reason other than the one it
asserts.** (b) is that rule inside the test — a sandbox missing a script makes the check answer the right
word for the wrong reason. (a) is the rule at the script's own boundary — exit 3 says "the base is red too",
and when the two trees share a mutable directory that sentence can be true without the base being at fault.
Where the rule cannot be enforced, it must be written down as not enforced.

Do not widen this into a fix for (a). The vector needs the branch's own check to have run and written; the
hand re-run rule already in `reviewer.md` covers it, and isolating the two trees' dependencies means paying
a full install per verify run. The deliberate decision is to name the limit, not to buy it out.
