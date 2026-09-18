# PI-59 — A task or PR state claimed in a report or a PR body is checked against the board, and disagreement is red

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: S
**Budget**: 90
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/verify.sh, bin/verify.test.sh, possibly a new bin/ script and its test
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**: 
**PR**: 

## Goal
`shared/implementing-common.md` §9 now says that a claim a command could settle is run before it is written down, and names the cheapest case of it: **a task id or a PR number is a state you check on the board, never one you infer from the prose that cites it.** That rule is prose an agent applies to itself, which is the weakest kind of rule the pipeline has — the same shape as the `BUDGET`/`STALL` lines that were never written (`tasks/PI-58`).

This is the half of it that a machine can settle. Measured: a report and a PR body both stated that a task was merged; the task was `Status: Todo`, with no branch and no PR, and the sentence had been inferred from a rule that cited the id in the present tense. It cost a full review round, and the PR body becomes the squash-merge commit message on the base branch permanently.

## Acceptance criteria
- [ ] AC1 — Given a committed report or a PR body that states a **state** for a task id or a PR number — merged, landed, done, in review, open, closed, or the same thing said in other words — when the check runs, then it reads that state from the board (`tasks/` `**Status**`) or from the forge (`gh pr view`) and **exits non-zero when the two disagree**, naming the id, the claimed state and the measured one. Decide from the artefact, not from what this task's author guessed the wording would be.
- [ ] AC2 — Given the same artefacts containing a **mention** of an id that claims no state — a dependency, a cross-reference, a "see", a file path holding the id — when the check runs, then it stays silent and exits 0. The rule this replaces failed by being ignorable; a check that fires on ordinary cross-references will be ignored the same way. State in the report how mention and claim are told apart and what evidence the distinction rests on: a regex over an id alone cannot carry it.
- [ ] AC3 — Given the ambiguity cannot be resolved from the text, when the check must choose, then it chooses **silence** and says so in the report. This is the opposite of `bin/verify.sh`'s `base_blockers` bias and deliberately so: there, a wrong green hides a real red at no cost to anyone; here, a false alarm on every cross-reference is what makes the whole check get switched off. Show the case where the choice is forced and name which way it goes.
- [ ] AC4 — Given a claim about a PR number the check cannot resolve (no network, the forge unreachable), when it runs, then it reports that it could not measure and does **not** pass the claim as verified. A missing measurement is not a green (same failure mode as `tasks/PI-58` AC5).
- [ ] AC5 — Given where the check lives, when the developer places it, then the report argues the placement against where the data is available at that moment — `bin/verify.sh`, a closing step, or a new script — and against the cost of running it. The PR body is not on disk: say how it is read, or say plainly that only the committed artefacts are covered and the body is left to the reviewer.
- [ ] AC6 (mutation) — Given the check, when a fixture asserts a state the board contradicts, then it goes red with that id named; when the fixture is corrected, green. A check that cannot be made to fire is not installed.
- [ ] AC7 — Given the repo's own tree, when the check is run over it once as it stands, then the report lists every hit and says for each whether it is a real disagreement or a false alarm. If it fires on artefacts that are correct, AC2 is not met yet.

## Tests expected
Unit tests over fixtures: a claim that agrees with the board, one that contradicts it, a bare mention, an id inside a path, the unresolvable case of AC4, and the mutation of AC6. Integration/E2E: not needed.

## Notes
- Read the existing state-reading code before writing new: `bin/doctor.sh` and `bin/next-wave.sh` already parse `**Status**` out of `tasks/`, and `bin/cleanup-merged.sh` already asks the forge for a PR's state instead of inferring it from ancestry. Reuse, do not re-derive.
- The prose rule stays whatever this task concludes: it covers claims about code behaviour and about mutations, which no board can settle. This task narrows the gap; it does not close it.
- pocket-it is public: mechanism only, no consumer-project names, paths or anecdotes in code, tests, commits or PR text.
