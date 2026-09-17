# PI-54 — The reviewer must not edit a task file that travels on the PR branch

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
**Files**: .claude/agents/reviewer.md, possibly .claude/agents/shared/implementing-common.md
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**: 
**PR**: 

## Goal
`reviewer.md` Step 5 tells the reviewer to run `set_status "Needs Work"` on the task file. On a board where task files live in the repo and travel on the PR branch, the branch carries its own `**Status**` line — so editing the base checkout's copy writes a second, competing value for the same field, which collides at merge and silently resolves to whichever side the merge picks. Observed on a live review (the reviewer noticed the gap itself and did not write, because the base copy already read `Needs Work`): the defect did not fire, but only by coincidence. Expected: Step 5 names the condition under which the write is correct, and the alternative when it is not.

## Acceptance criteria
- [ ] AC1 — Given a task file that is part of the PR's diff, when the reviewer reaches Step 5, then the template tells it **not** to edit the base checkout's copy, and to put the status verdict in its report and PR comment instead — the branch's own copy is the one that merges. The rule names the harm ("two writers for one field, resolved by the merge"), not the place.
- [ ] AC2 — Given a task file that is **not** in the PR's diff (a board kept outside the branch), when the reviewer reaches Step 5, then today's behaviour is unchanged: it sets the status on the base checkout.
- [ ] AC3 — Given the wording added by AC1, when an agent reads it at Step 0, then it can decide which case it is in from something it can check (the PR's own file list), not from a judgement call about the project's layout.
- [ ] AC4 — Given the change, when `bin/doctor.sh` and the repo's own test command run, then both stay green: this is a template-text change, nothing mechanical depends on it yet.

## Tests expected
None — text only. The reviewer's own next run is the verification. Integration/E2E: not needed.

## Notes
- Companion gap, already covered elsewhere: `bin/handoff.sh` refusing a write from a non-base branch is `PI-52`. This task is the same class of defect (an agent writing a shared file from the wrong side) applied to the task file rather than the diary, but it is template text, not a mechanism, so it does not depend on PI-52.
- Repo is public: mechanism only, no consumer-project names, paths or anecdotes in the template, commits or PR text.
