# PI-57 — The reviewer's "execute your correction before proposing it" rule must bind notes, not only findings

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
**Files**: .claude/agents/reviewer.md
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**: 
**PR**: 

## Goal
`reviewer.md` Step 4 tells the reviewer to run its own correction before proposing it — and scopes that rule to **findings**. Anything raised as a *note* therefore leaves as prose, unmeasured. Measured consequence, twice in one PR's life: a note asked a developer to rewrite an inaccurate comment; the developer's rewrite was also inaccurate; the next round's note about *that* was itself inaccurate, and only failed to propagate because the reviewer happened to run the command that time and found three surviving lines where the text claimed none. Unmeasured text keeps travelling until someone runs something.

A note costs less than a finding to raise, which is exactly why it must not cost less to prove: it ends up in the same report and, through the PR body, in the permanent squash-merge message on the base branch.

## Acceptance criteria
- [ ] AC1 — Given `reviewer.md` Step 4, when the "execute before proposing" rule is read, then it binds **every claim the reviewer hands over** — findings, notes, suggested replacement text — with no severity carve-out. A proposed replacement sentence is a claim about the code, and it ships with the command whose output shows it true.
- [ ] AC2 — Given a claim the reviewer cannot execute (it needs an environment the review does not have, or the measurement would cost more than the note is worth), when it is still worth handing over, then the rule tells it to mark the claim as unverified in the report and the PR comment, in those words. Unverified-and-labelled is allowed; unverified-and-stated-as-fact is not.
- [ ] AC3 — Given the wording added by AC1, when a reviewer reads Step 4 at Step 0, then it can tell which of its own output is covered without a judgement call about severity.
- [ ] AC4 — Given the change, when `bin/doctor.sh` and the repo's test command run, then both stay green: this is template text, nothing mechanical depends on it.

## Tests expected
None — text only. The reviewer's own next run is the verification. Integration/E2E: not needed.

## Notes
- `.claude/agents/reviewer.md` is also edited by `tasks/PI-54` (Step 5, task files that travel on the branch). Two XS text changes to the same file: whichever runs second merges the base first. They are kept apart because the rules are unrelated and each is easier to judge alone.
- The defect was found by the reviewer itself, in its own output, which is why it is worth writing rather than remembering: the discipline held on the round someone happened to run the command, and not on the two before it.
- pocket-it is public: mechanism only, no consumer-project names, paths or anecdotes in the template, commits or PR text.
