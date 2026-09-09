# PI-3 — doctor.sh: warn when an EPIC/STORY summary file's Status contradicts its children

**Status**: Done
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: XS
**Budget**: 60
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: `bin/doctor.sh`, `bin/doctor.test.sh`
**TAD**: none
**Contract**: none
**Branch**: task/PI-3-doctor-summary-status
**PR**: https://github.com/FCabiddu/pocket-it/pull/17

## Goal
Legacy nested boards (`tasks/EPIC-n-slug/EPIC.md`, `tasks/EPIC-n-slug/STORY-n.m.md`, children `T-n.m.k*.md`) have summary files nobody updates: today three said "Not Started" while every child was Done. `doctor.sh` already skips these files as non-tasks; it should additionally warn on the mismatch so the retro fixes it.

## Acceptance criteria
- [x] AC1 — Given a folder `tasks/EPIC-*/` whose `EPIC.md` Status is not `Done` and whose every `T-*.md` child has Status starting with `Done`, when doctor runs, then it prints `warn  tasks/EPIC-…/EPIC.md: says "<status>" but all N children are Done — update the summary`.
- [x] AC2 — Given a `STORY-n.m.md` in that folder whose children `T-n.m.*.md` are all Done and whose own Status is not Done, when doctor runs, then the same warning form is printed for the story.
- [x] AC3 — Given a summary whose children are not all Done, or a folder with no children, when doctor runs, then no warning is printed for it.
- [x] AC4 — Given a flat board (no `tasks/EPIC-*/` folders), when doctor runs, then output is unchanged and exit code unchanged.
- [x] AC5 — Given `bin/doctor.test.sh` (new), when it runs on temporary boards built in a temp git repo, then it covers AC1–AC4, `ok`/`FAIL` per case, exit 1 on FAIL; add it to `testCommand`.

## Non-goals
No roll-up automation, no edits to summary files, no change to error/exit semantics (warnings never fail doctor).

## Tests expected
`bin/doctor.test.sh`. Integration/E2E: not needed.

## Notes
`doctor.sh` is a bash wrapper around a python heredoc; the file list is built with `glob.glob("tasks/**/*.md", recursive=True)` and summaries are excluded by a regex — put the new check after the task loop, reading the summaries separately. Status lines are `**Status**: X` or `**Status:** X`.
