# Lessons — method, independent of the stack

The third layer of memory. Project truths live in each project's `docs/SESSION_HANDOFF.md` facts; stack rules live in each project's `best-practices/`; **this file holds what we learned about how to work**, valid on every project. Read at Step 0 by developer, qa-engineer, reviewer and implementation-planner, together with the shared rules. Written by `retro` (a PR on this repo that it merges itself — text only) and by humans.

Rules of the file: one lesson = one line, in the fixed form below; ≤ 40 lessons; a lesson enters as `provisional` and becomes `confirmed` when a later retro sees it hold on a second project or epic, or is removed if it does not; a `confirmed` lesson that keeps mattering is promoted to a rule in `implementing-common.md` / the orchestrator's CLAUDE.md and deleted from here. Nothing in this file names a client or a project — write "project A".

Form: `- {date} · {status} · WHEN {situation} · DO {action} · BECAUSE {evidence, one clause}`

## Lessons

- 2026-09-09 · confirmed · WHEN a task's criterion is "make the suite pass" or "fix the reds" · DO not split it and give it a custom budget · BECAUSE the work is only discoverable by running the whole thing (project A: 249 turns, interrupted at 120 for nothing)
- 2026-09-09 · confirmed · WHEN an agent runs over its budget · DO check progress, not size: stop only if ~30 turns brought no commit and no new green test · BECAUSE a hard cap interrupts productive work and a stall wastes turns regardless of the cap
- 2026-09-09 · confirmed · WHEN backend and frontend of one story would otherwise be sequential · DO write a contract task first (types, schema, OpenAPI fragment) and put both sides in the same wave · BECAUSE every story waited a full wave for its endpoint
- 2026-09-09 · confirmed · WHEN a reviewer makes the same finding twice · DO write it as a project fact (and the retro decides if it is a rule) · BECAUSE nine good facts sat unread in project A until agents were told to read them at Step 0
- 2026-09-09 · confirmed · WHEN working inside an isolated worktree · DO use repo-relative paths only, never a path into the main checkout · BECAUSE the harness blocks each such command and every block costs a turn (34 in one session)
- 2026-09-09 · confirmed · WHEN no named agent seems to fit a piece of work · DO stop and name the missing agent, never launch `general-purpose` · BECAUSE it has no rules, no budget, no read discipline (one reached 414k of context)
- 2026-09-09 · confirmed · WHEN a session has closed two waves · DO `/compact` or open a new session before the third · BECAUSE the orchestrator's context, not the agents', was 73 % of the audited bill
- 2026-09-09 · provisional · WHEN a review is about to start · DO run the mechanical checks first and reject red PRs without reading · BECAUSE most rework was mechanical and judgement is the expensive part (rework 40 % → 15 % on project A, one epic — confirm on a second)
- 2026-09-09 · provisional · WHEN a product is developed over many features · DO keep one project document and write a delta per feature, for BAD and TAD alike · BECAUSE project A accumulated 8 TADs and 9 IPDs repeating the same stack (confirm when a second project reaches feature 3)
