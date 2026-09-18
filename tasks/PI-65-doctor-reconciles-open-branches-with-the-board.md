# PI-65 — doctor reconciles the open branches with the board

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: M
**Budget**: 150 min
**Risk**: low
**Depends on**: PI-64
**Wave**: 1
**Files**: bin/doctor.sh, bin/doctor.test.sh
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**:
**PR**:

## Goal
No script in the toolbox looks at the **branches**. `next-wave.sh` reads the board, `cleanup-merged.sh` reads
merged PRs, `doctor.sh` reads task files, config and the base branch — so three states are invisible today,
each of them measured:

1. **Committed work that nobody can see.** A branch carrying a WIP commit, its worktree still registered and
   no PR opened, stays that way indefinitely: no script names it, and the orchestrator's turn-start read does
   not either. The work is safe on disk and lost to the pipeline.
2. **Two branches editing one file.** Nothing compares what a branch actually changed with what another one
   changes, so two tasks whose `**Files**` lines are disjoint can be rewriting the same file all wave and the
   first evidence arrives as a merge conflict, or as a silent semantic clash that merges clean.
3. **`Files` as prose.** A task's `**Files**` line is never compared with the diff of its own branch, and the
   Notes of one task describing another's file set are not compared with anything at all. On this board right
   now, `tasks/PI-64`'s Notes say PI-48 "restructures the self-mutation gate in this same file" — its own file
   being `bin/doctor.test.sh` — while `tasks/PI-48`'s `**Files**` line declares `bin/cleanup-merged.test.sh`.
   One of the two statements is wrong; nothing in the toolbox can say which, and a wave can be launched on
   either reading.

`doctor.sh` is the host because it is the one script the orchestrator must run before every launch, which is
exactly the moment all three matter, and because it already has a warning channel that does not block.

## Acceptance criteria
- [ ] AC1 — Given a repo with branches, when `doctor.sh` runs, then it derives the open set from git alone:
      every local **and** remote branch other than the base that holds at least one commit not contained in
      `origin/{baseBranch}`, with its tip sha, the age of that tip, its task id when the branch name carries
      one, its open PR number, and whether a worktree is registered for it. The board is never the source of
      this list — a branch with no task file must still appear.
- [ ] AC2 — Given that set, when doctor decides what to report, then exactly this table holds, each row
      exercised by its own case: (a) own commits + open PR → silent; (b) own commits + merged PR → silent, it
      is `cleanup-merged.sh`'s business; (c) own commits + no PR + tip newer than 24 h → silent, work in
      flight; (d) own commits + no PR + tip 24 h or older → **WARNING**, naming branch, task id or `no task
      file`, tip age and worktree state; (e) no commits of its own → silent; (f) the base branch itself →
      never reported, under any name it carries in config.
- [ ] AC3 — Given two branches of the open set whose changed files intersect, when doctor runs, then it emits
      one warning naming both branches and **every** shared path. The changed set of a branch comes from
      `git diff --name-only $(git merge-base origin/{base} <tip>) <tip>`, never from a `**Files**` line; two
      branches that declare disjoint files and touch the same one is the case this exists for, so a check
      built on the declarations would be green on it.
- [ ] AC4 — Given a branch of the open set whose name carries a task id with a task file, when doctor runs,
      then every path it changed that the task's `**Files**` line does not list is reported as a warning
      (`{ID}: touches {path}, not in **Files**`). A declared path not yet touched is not reported — partial
      work is normal. `docs/handoff/**`, `docs/reports/**` and `tasks/INDEX.md` are excluded, and the
      exclusion list is in one named place in the code, not spread through the checks.
- [ ] AC5 — Given all four checks, when any of them fires, then doctor's **exit code is unchanged**: these are
      warnings, never errors. Measured, not asserted: a fixture that fires every new warning at once still
      exits 0 when nothing else is wrong.
- [ ] AC6 — Given `gh` missing, failing or returning output that cannot be read, when doctor needs a PR state,
      then it says the state is **unknown** for that branch and never reports it as "no PR" — the distinction
      this project already learned the hard way in `cleanup-merged.sh` (unknown is not a no). A branch of
      unknown PR state is reported once, in its own line, and never counted into row (d).
- [ ] AC7 — Given a case for each row of AC2 plus AC3, AC4 and AC6, when the suite runs, then each case
      asserts a **witness that its scenario really happened** (`implementing-common.md` §4): a row whose
      expected outcome is "silent" is paired with the same fixture made to fire, so a case that never built
      its branch cannot pass as a silence. Every new case is mutation-tested once and its red pasted in the PR.
- [ ] AC8 — Given this repo's own checkout, when doctor runs before and after the change, then the report
      states the measured added wall-clock time and the number of branches it walked. If the added work is
      more than a few seconds on a repo of this size, cap it and say what the cap drops.

## Tests expected
A new block at the end of `bin/doctor.test.sh` with its own fixtures (a throwaway repo per case, as the file
already does elsewhere). Integration/E2E: not needed.

## Notes
- `bin/doctor.test.sh` is also edited by `tasks/PI-64`, which is why this task depends on it: two branches on
  that file at once is precisely the state AC3 exists to detect, and the board should not be the first place
  to demonstrate it.
- The `**Files**` discrepancy in the Goal is a live example, not a task to fix here — do not edit PI-48 or
  PI-64 from this branch. Read both files and re-measure before quoting it; if it has been corrected by the
  time you start, say so in the report and keep the criterion.
- Warnings only, everywhere. A check that blocks a launch on work in flight will be switched off, and a check
  that is switched off protects nothing.
