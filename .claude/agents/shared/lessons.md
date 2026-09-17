# Lessons — method, independent of the stack

The third layer of memory. Project truths live in each project's facts (read via `handoff.sh facts`); stack rules live in each project's `best-practices/`; **this file holds what we are still learning about how to work**, valid on every project. Read at Step 0 by developer, qa-engineer, reviewer and implementation-planner, together with the shared rules. Written by `retro` (a PR on this repo that it merges itself — text only) and by humans.

Form — one lesson, one line, **at most 300 bytes**, evidence cited by number and never narrated. Bytes, not eyeballed characters: the `·` separators and the dashes are multi-byte, so a line that reads as 294 characters is already 300. The measure is the one the guard runs — `awk '/^- 20/{if (length($0) > 300) print NR, length($0)}' .claude/agents/shared/lessons.md` must print nothing (`tasks/PI-53`).

`- {date} · {status} · WHERE {destination} · WHEN {situation} · DO {action} · BECAUSE {evidence, one clause}`

Rules of the file:

- **`WHERE` is decided when the lesson is written, not when it is promoted.** It names the file — and section — an agent reads at start, where the rule will bind: `shared/implementing-common.md §N`, an agent template, a skill. When only a mechanical check can enforce it, `WHERE` is `bin/…` and the promotion opens a `tasks/PI-n` instead of writing prose.
- **A lesson enters as `provisional`.** The retro that sees it hold on a second project or epic promotes it **in that same PR**: it writes the rule at its `WHERE` and **deletes the line from here**. A `confirmed` line left in this file is a defect, not a state — there is no queue and no human step between a lesson and its rule.
- **A lesson whose rule already exists somewhere an agent reads is deleted**, not kept as a copy: every line here is read at every launch, so a duplicate is paid for on each one.
- A lesson the evidence contradicts is deleted, with the reason in the PR.
- Over the cap means two lessons: split it, or cut the narration. The line is measured in the unit the check counts, never in the one it looked like while writing — five lines of this very file went out 1 to 6 bytes over on the pass that introduced the cap, measured in characters by their author and in bytes by its reader.
- The cap of 40 lines is a symptom that must never be reached: reaching it means promotions stopped happening.
- Nothing here names a client or a project — write "project A".

## Lessons

- 2026-09-09 · provisional · WHERE shared/implementing-common.md §2 · WHEN commits pile up on a branch with no task file · DO stop and write the task file before the next commit · BECAUSE 23 such commits arrived as one 96-file review of ten features, with criteria for a fifth of it
- 2026-09-09 · provisional · WHERE shared/implementing-common.md §1 · WHEN a pipeline default changes · DO re-read the per-project config at session start and let it win · BECAUSE a project pinning `automerge: false` the day the default flipped left reviewer and orchestrator disagreeing
- 2026-09-09 · provisional · WHERE bin/cleanup-merged.sh · WHEN deciding a branch is merged · DO ask its PR state, never infer from ancestry or from a vanished remote branch · BECAUSE squash-merge rewrites the sha and leaves the branch on origin: a cleanup recognised 0 of 100 merged branches
- 2026-09-09 · provisional · WHERE bin/doctor.sh · WHEN a task file is written · DO always give it a `**Status**` line · BECAUSE a file without one is invisible to the wave picker yet counted as open by the index — 56 such files on one board, six of them launchable
- 2026-09-11 · provisional · WHERE shared/implementing-common.md §4 · WHEN the affected-test selector reports "no test files found" for the changed file · DO treat it as a red: the behaviour is unproven · BECAUSE inverting the only new gate left the suite green and cost a round
- 2026-09-11 · provisional · WHERE shared/implementing-common.md §7 · WHEN a number goes into a report or a criterion · DO produce it with the tool that owns it, from the main checkout, and name that tool · BECAUSE a grep once stood in for the runner, which then counted 25016 files against 229
- 2026-09-11 · provisional · WHERE skills/run-wave/SKILL.md §3 · WHEN two agents disagree on a number or on what a red means · DO have each re-execute the other's measurement instead of arguing · BECAUSE four such disagreements settled that way, each side right about half the time
- 2026-09-12 · provisional · WHERE shared/implementing-common.md §9 · WHEN a bug task names the files where an intermittent failure shows · DO reproduce the trigger first and let a cause found outside it win · BECAUSE a flaky suite was a cross-process deadlock, not a defect in those files
- 2026-09-12 · provisional · WHERE implementation-planner.md §3 · WHEN estimating a change to a default or shared helper that tests consume · DO count the consuming test files and past ten split their migration into its own task in the same wave · BECAUSE such a task took twice its budget
- 2026-09-16 · provisional · WHERE implementation-planner.md §3 · WHEN a class of cases is visible only in what the program prints · DO write the criterion as the effect on the world, and give "produces nothing" its own row · BECAUSE a count-equals-count AC stayed green on a silent path
- 2026-09-17 · provisional · WHERE shared/implementing-common.md §7 · WHEN a report offers a full classification as completeness evidence · DO mark each row ran or read, and run the rows where the invariant's own nouns change kind · BECAUSE 3 of 43 rows filed as handled routed through nothing
- 2026-09-17 · provisional · WHERE bin/ (a refusing guard, as a task) · WHEN a project must derogate from a template rule · DO put the derogation in the mechanism that refuses and let the gate go red · BECAUSE the same defect returned 13 times while the derogation sat readable in a fact
