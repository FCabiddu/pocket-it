# PI-55 — A forward reference to an unbuilt mechanism must not read as a mechanism that exists

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
**Files**: .claude/agents/shared/implementing-common.md, possibly other files under .claude/agents/ and .claude/skills/
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**: 
**PR**: 

## Goal
`shared/implementing-common.md:111` ends a rule with a sentence naming a task id and describing, in the present tense, what that task does to the mechanism — as if the mechanism already existed. The task is `Todo`: nothing of it is built. An agent read that sentence at Step 0, concluded the mechanism was in place, and **wrote that conclusion into a PR body and a report as a fact**; the reviewer caught it and the round cost a re-review. The conclusion happened to be harmless, but the PR body becomes the squash-merge commit message on the base branch permanently, and `docs/reports/` is what `retro` reads later.

The defect is not the one line: it is that these files carry forward references at all, and the present tense makes an unbuilt one indistinguishable from a built one. An agent has no way to tell them apart from the text alone, and checking a task's status is not something the reading step asks for.

## Acceptance criteria
- [ ] AC1 — Given every file an agent reads at startup (`.claude/agents/**`, `.claude/skills/**`), when they are searched for references to a task id, then the report lists **all** of them with the command used, and says for each whether the task is `Done` or not — the list comes from a search, not from memory, and `implementing-common.md:111` is one entry in it, not the scope.
- [ ] AC2 — Given a reference whose task is **not** `Done`, when it is rewritten, then the sentence can no longer be read as describing something that exists: it names the state explicitly ("not built yet", "will move", or the equivalent) so that an agent reading only that sentence draws the right conclusion without looking anything up.
- [ ] AC3 — Given a reference whose task **is** `Done`, when it is reviewed, then it is left as it is: the present tense is correct there, and rewriting it would be noise. The report says which ones these are.
- [ ] AC4 — Given the rewritten text, when an agent reads the rule around it, then the rule itself still stands on its own: the forward reference is an aside, and removing or qualifying it must not weaken what the rule asks for today.
- [ ] AC5 — Given the change, when `bin/doctor.sh` and the repo's test command run, then both stay green — this is template text, nothing mechanical depends on it.

## Tests expected
None — text only. Integration/E2E: not needed.

## Notes
- Measured on 2026-09-17 during a review: the sentence at `:111` names `tasks/PI-52` and the twin at `:183` names a task that really did merge, which is why the first one is not obviously wrong when read next to it. Both are in scope for AC1/AC3.
- Consider whether the durable fix is a convention rather than six edits — for example: a forward reference always carries the task's state, or it does not name a task at all. If the developer's search finds that these references are many and keep appearing, say so in the report and propose the convention; if there are two or three, just fix them.
- pocket-it is public: mechanism only, no consumer-project names, paths or anecdotes in the template, commits or PR text.
