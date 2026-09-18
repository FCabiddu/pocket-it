# PI-61 — Repo-wide structural guards scan the branch, not the checkout they run in

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: S
**Budget**: 90 min
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/handoff.test.sh, bin/verify.test.sh
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**:
**PR**:

## Goal
Three assertions enforce "one home per rule" by grepping the whole checkout:

```
bin/handoff.test.sh:1100   grep -rn "^def split_section(" "$REPO" --exclude-dir=.git   → must be 1
bin/handoff.test.sh:1104   grep -rn "^def one_line("      "$REPO" --exclude-dir=.git   → must be 1
bin/verify.test.sh:1028    grep -rniE --include='*.md' '<stale prose forms>' "$REPO_ROOT"
```

All three walk the **directory**. `bin/worktree.sh` puts every agent's worktree **inside the repo**, under `.claude/worktrees/`, and `grep -r` has no reason to skip it: `grep -rn 'exclude-dir=.claude/worktrees'` over `bin/` and `.claude/` returns **0** — not one guard excludes them. So while a wave is running, every one of these guards reads sibling branches' files as if they belonged to the branch under test. That is precisely when the suite runs most.

This is not hypothetical. Measured 2026-09-18 on a clean, correct branch:

```
grep -rn "^def split_section(" . --exclude-dir=.git
  bin/handoff_sections.py:38                                            ← the only real one
  .claude/worktrees/task-pi-48-…/bin/handoff.sh:37                      ← a parked branch's pre-migration copy
→ FAIL  "PI-16 — exactly one definition of where a section begins, in the whole repo"
```

The same tree copied without `.claude/worktrees` gives 1 definition and the assertion passes, so the branch is correct and the guard is wrong.

The cost is not the red. It is that the red **names a source file the change never touched**, and its message ("exactly one definition … in the whole repo") reads as an instruction to go and delete one. Only the shared rules' *"a check that goes red on code this change never touched is diagnosed before it is fixed, and never fixed in the source it points at"* stands between this guard and a wrong edit — and that rule is a rule, i.e. the layer this task exists to stop relying on.

## Acceptance criteria
- [ ] AC1 — Given a repo with a worktree under `.claude/worktrees/` containing a file that would satisfy the pattern, when each of the three guards runs, then it does **not** count that file. Take the file list from what the branch tracks (`git ls-files -z` piped to `grep -z`, or equivalent) rather than from a tree walk; if a tree walk is kept, the exclusion is of the worktree root and not of one named worktree.
- [ ] AC2 — Given a repo with **no** `.git` (the suite is run from an exported copy, which is how the branch was proved correct above), when the guards run, then they still work and do not error: `git ls-files` returns nothing there, so a bare switch to it trades a false red for a silent false green. State in the report which of the two mechanisms was chosen and how the other failure mode is closed.
- [ ] AC3 (mutation) — Given the fix, when a second real definition is added to a **tracked** file, then each guard goes red; when it is removed, green. The guards must keep catching the thing they were written for — proving they no longer fire on a worktree is only half.
- [ ] AC4 (mutation, the sibling that was missing) — Given the fix, when a file matching the pattern is placed **inside** `.claude/worktrees/`, then the guards stay green. Run it with a real worktree, not a hand-made directory, so the test exercises the layout `worktree.sh` actually produces.
- [ ] AC5 — Given the whole of `bin/` and `.claude/`, when the census of repo-wide `grep -r` guards is retaken, then every one of them is listed with the command that found it and marked fixed or correct-as-is — **per row, with its own count; no catch-all bucket** (shared rules §7). Three are named above; the census decides whether they are all of them.
- [ ] AC6 — Given the repo's test command and `bin/doctor.sh`, when they run with a worktree present under `.claude/worktrees/`, then both are green. That configuration is the normal one during a wave and is what the suite must be green in.

## Tests expected
Unit assertions in the two existing suites: the mutation pair of AC3/AC4 for each guard, and the no-`.git` case of AC2. Integration/E2E: not needed.

## Notes
- Do **not** touch `bin/handoff_sections.py`, `bin/handoff.sh` or any other source the red points at; the source is correct and the guard is what is being repaired. The red observed above disappears on its own the day the parked worktree is removed, which is exactly why it must not be chased there.
- Do not remove or unlock anybody's worktree to make a guard pass — they are locked while agents work.
- A guard whose file list comes from `git ls-files` also stops seeing untracked scratch files, which is a behaviour change worth one line in the report even though it is the desired one.
- pocket-it is public: mechanism only, no consumer-project names, paths or anecdotes in code, tests, commits or PR text.
