# PI-52 — handoff.sh: refuse a write from a branch that is not the base, and offer a structural check to verify.sh

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: high
**Depends on**: PI-51
**Wave**: 1
**Files**: bin/handoff.sh, bin/handoff.test.sh, bin/verify.sh, bin/verify.test.sh
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**: 
**PR**: 

## Goal
`shared/implementing-common.md` §6 case (1) tells an agent whose worktree becomes a PR to write the shared handoff file and commit it in that PR. A project whose memory file must not be written from a task branch can only state that as a fact, and a project fact does not beat a template an agent reads at Step 0: the same defect was measured 13 times, the last one hiding 26 log lines from `handoff.sh recent` behind a duplicated `## Log` heading while the file still looked plausible. The deviation must live in the mechanism that refuses the write, not in a fourth document. Two guards, both in `bin/handoff.sh`: (A) `log`/`fact` refuse to write from a non-base branch and hand back the line already formatted for the agent's report; (B) a read-only `handoff.sh check` that `verify.sh` runs, so a hand-written, structurally broken file goes red on the developer's own gate instead of reaching review.

## Acceptance criteria
- [ ] AC1 — Given a repo with `.pocket-it.json` and HEAD on a branch other than `baseBranch`, when `handoff.sh log "…"` or `fact "…"` runs, then it exits **4**, touches nothing on disk (`git status --porcelain` byte-identical before and after) and prints to stderr the line already in report form — a `## Handoff` heading plus `- log: \`…\`` / `- fact: \`…\`` — naming the escape hatch `POCKET_IT_HANDOFF_ON_BRANCH=1`.
- [ ] AC2 — Given HEAD on the base branch, or `POCKET_IT_HANDOFF_ON_BRANCH=1` set, or a detached HEAD, or no `.pocket-it.json` (default `main`), or a non-git directory, when `log`/`fact` runs, then today's behaviour is unchanged, byte for byte.
- [ ] AC3 — Given a handoff file with two `## Log` headings (or two `## Fatti che non scadono` / two of whichever facts heading the file uses), or a `- ` line inside the Log section that does not start with a date, when `handoff.sh check` runs, then it exits **5** naming file, line number and defect; on a healthy file it exits 0 and writes nothing (a pure reader, like `facts|show|recent|grep`).
- [ ] AC4 — Given `check --against <ref>`, when the readable facts or log lines are **fewer** than in `<ref>`, then it exits 5 quoting both counts (the measured case: 95 against 121 log lines, 54 against 55 facts).
- [ ] AC5 — Given a branch whose diff touches the handoff file, when `verify.sh` runs, then `check --against <base>` is one of its steps and its red is a red of `verify.sh`; given a branch that does not touch it, behaviour is unchanged.
- [ ] AC6 — Given a write (`log` or `fact`) that the filesystem refuses — the target directory or file not writable, the disk full, the file replaced by a directory — when the command runs, then it exits **non-zero**, says on stderr which file it could not write and why, and **never prints the success line**. Measured twice on 2026-09-17: a read-only `docs/` made the write raise, the line never reached the file, and the command still printed `handoff: logged — …` and exited **0**, so every caller downstream believed the diary had been written. The class is "a write that did not happen reports as if it had", not the read-only case alone: every path that prints a success line must be reached only after the write it claims has succeeded.
- [ ] AC7 (mutation, both directions) — A file carrying the measured defect (two `## Log`, a fact bulleted inside the Log) makes `check` red; the same file restored from the base makes it green. Removing guard (A) makes an AC1 test red; removing the `check` step from `verify.sh` makes an AC5 test red; restoring the unchecked write path makes an AC6 test red.

## Tests expected
`bin/handoff.test.sh`: fixture repos for every branch of AC1/AC2 (on base, off base, env override, detached HEAD, no config, non-git) and every defect of AC3/AC4; for AC6 a fixture whose target directory is `chmod`-ed unwritable (restored in the teardown, so a failing run cannot leave the tree read-only). `bin/verify.test.sh`: the AC5 wiring, both with and without the handoff file in the diff. Integration/E2E: not needed.

## Notes
- `handoff.sh` already anchors sections by heading (PI-40); `check` reads through the same anchor, so a file whose heading is duplicated must not be "repaired" silently — `check` reports, it never writes.
- Exit codes: 4 for a refused write, 5 for a failed check — keep them distinct from the existing ones.
- Depends on PI-51: that task also edits `bin/verify.sh` and `bin/verify.test.sh`. Start from a base that already has it merged, to avoid resolving the same file twice. **PI-51 is merged as of 2026-09-17**; the remaining contention is PI-16, which edits `bin/handoff.sh` — start from a base that has it too.
- AC6 was added on 2026-09-17 from a defect measured during another task's review, not from a separate report: the silent-success write lives in the same file and the same exit-code table as guards (A) and (B), so it is folded in here rather than opened as a fourth task on `bin/handoff.sh`. Consequence for the whole task: any early return added by (A) or (B) is subject to AC6 as well — a guard that refuses a write must not print a success line either.
- pocket-it is public: mechanism only, no consumer-project names, paths or anecdotes in code, tests, comments, commits or PR text.
