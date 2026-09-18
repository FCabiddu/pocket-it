# PI-62 — doctor fails when tasks/INDEX.md no longer matches the task files

**Status**: Done
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: S
**Budget**: 90 min
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: `bin/doctor.sh`, `bin/tasks-index.sh`, `bin/doctor.test.sh`
**TAD**: none — follow the conventions already in `bin/doctor.sh`
**Contract**: none
**Branch**: task/PI-62-doctor-catches-a-stale-board-index
**PR**:

## Goal
`tasks/INDEX.md` is generated from the task files by `bin/tasks-index.sh`, and every lane is supposed to
re-run that script after a merge. Nothing checks that it happened. When the step is skipped the board
index keeps the pre-merge row — a task the file itself already marks `Done` still reads `Todo`, with no
PR link — and `bin/status.sh`, which reads the index, then reports that false state to the next session:
the orchestrator opens on a state that disagrees with the disk it claims to trust. This has happened in a
real project, and it went unnoticed precisely because no check covers the invariant.

Close it where the state is verified rather than where it is written: `bin/doctor.sh` regenerates the index
in memory and **errors** (exit 1, not a warning) when it differs from the committed `tasks/INDEX.md`.
Wrong behaviour today: `doctor.sh` prints `0 error(s)` on a board whose index is stale. Expected: it names
the rows that disagree and prints the one command that fixes it.

The generation logic must not be duplicated: `bin/tasks-index.sh` gains a mode that prints the index to
stdout instead of writing it, and `doctor.sh` calls that. Two implementations of the same table would drift
apart and the check would then report differences that are its own.

## Acceptance criteria
- [ ] AC1 — Given a board whose `tasks/INDEX.md` matches what `tasks-index.sh` generates, when `doctor.sh`
      runs, then no error and no warning is emitted about the index and the exit code is unchanged.
- [ ] AC2 — Given a task file whose `**Status**` (or `**PR**`) was changed without re-running
      `tasks-index.sh`, when `doctor.sh` runs, then it emits an **error** (counted in the `N error(s)`
      line, exit 1) that names the task IDs of the differing rows and prints the exact command to fix it
      (`bash <absolute path to>/bin/tasks-index.sh`), following the self-contained-one-liner convention the
      rest of `doctor.sh` already uses for the commands it prints.
- [ ] AC3 — Given a task file added or deleted without re-running `tasks-index.sh`, when `doctor.sh` runs,
      then the same error fires and names the added/removed ID (a row present on one side only is drift too,
      not only a changed cell).
- [ ] AC4 — Given `tasks-index.sh` is invoked in its new stdout mode, when it runs, then it writes the index
      to stdout and does **not** touch `tasks/INDEX.md`; invoked as before (no new flag) it keeps writing the
      file and printing its existing `tasks-index: wrote …` line unchanged — every existing caller
      (`/quickfix`, `/run-wave`, the agents' closing steps) keeps working with no edit.
- [ ] AC5 — Given a project with no `tasks/` directory at all, when `doctor.sh` runs, then the new check is
      silently skipped, exactly like the board checks around it (regression: doctor must stay usable on a
      repo that has no board).

## Tests expected
In `bin/doctor.test.sh`, in the style of the cases already there (temporary repo fixture, assert on
doctor's output and exit code), one case per criterion:
- index in sync → no index error, and the pre-existing assertions on that fixture still hold (AC1);
- `**Status**: Todo` → `Done` in a task file, index untouched → error naming that ID (AC2);
- a task file added, and a second case with one deleted, index untouched → error naming that ID (AC3);
- `tasks-index.sh` stdout mode → nothing written to `tasks/INDEX.md` (compare the file's mtime/contents
  before and after) and the same bytes on stdout as the written form produces (AC4);
- no `tasks/` directory → no index error (AC5).
Integration/E2E: not needed.

## Notes
- `bin/doctor.sh` is a bash wrapper around one `python3` heredoc; the board checks live in the `# 2. board`
  section (around line 196) and `# 2c` (the `PI-37 CHECK BEGIN/END` block, line 250) is the closest
  precedent — it covers the neighbouring gap (a merged PR left on a non-`Done` task) and shows the house
  style for a check that must skip in silence when its inputs are missing.
- `bin/tasks-index.sh` (48 lines) builds the table inside a `{ … } > "$DIR/INDEX.md"` group; the stdout mode
  is a redirect change, not a rewrite. Keep `$DIR` resolution and the `field()` tolerance for both header
  forms exactly as they are.
- Watch the failure mode that would make the check useless: a repo whose commit hooks reformat markdown
  (prettier and friends) could make a byte comparison disagree on formatting alone. Compare the generated
  content against the file, and when they differ, report the **task rows** that differ — an error whose
  message is a formatting diff nobody can act on is worse than no check. If a formatting-only difference is
  the only one found, say so in the message and still point at `tasks-index.sh`.
- Do not add the check to `bin/next-wave.sh` as well: one home for the invariant, and `doctor.sh` is the
  gate every lane already runs before launching.
