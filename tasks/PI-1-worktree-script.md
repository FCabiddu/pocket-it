# PI-1 — bin/worktree.sh: create an isolated worktree for an agent from any cwd

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: `bin/worktree.sh`, `bin/worktree.test.sh`, `bin/cleanup-merged.sh`, `bin/cleanup-merged.test.sh`
**TAD**: none — follow the style of `bin/cleanup-merged.sh` and `bin/verify.sh`
**Contract**: none
**Branch**: 
**PR**: 

## Goal
The Agent tool's `isolation: worktree` only works when the session cwd is the target repo. Jarvis runs from a hub folder and governs several projects, so today the orchestrator created worktrees by hand four times. Provide `bash bin/worktree.sh <repo-path> <branch> [base]` that does it deterministically and prints the worktree path on stdout, so a launcher can pass `Worktree: <path>` to a developer.

## Acceptance criteria
- [ ] AC1 — Given a repo path and a new branch name, when the script runs with `[base]` omitted, then a worktree exists at `<repo>/.claude/worktrees/<branch-with-slashes-replaced-by-dashes>` on a new branch created from `origin/<baseBranch from .pocket-it.json, default main>` after `git fetch`, and the script prints only the absolute worktree path on stdout (everything else on stderr).
- [ ] AC2 — Given an existing branch (`origin/<branch>` exists), when the script runs, then the worktree checks that branch out tracking origin instead of creating a new one, and prints the path.
- [ ] AC3 — Given the worktree already exists for that branch, when the script runs again, then it is idempotent: prints the same path, exit 0, no error.
- [ ] AC4 — Given `<repo>/.git/info/exclude`, when the script runs, then it contains the line `.claude/worktrees/` (added once, never duplicated), so the worktree directory never shows as untracked in the main checkout.
- [ ] AC5 — Given a path that is not a git repo, or a branch name with spaces, when the script runs, then it exits 2 with a one-line error on stderr and creates nothing.
- [ ] AC6 — Given `bin/cleanup-merged.sh`, when a worktree created by this script has its branch squash-merged (PR merged on GitHub), then `cleanup-merged.sh` removes it: extend its worktree discovery to `<repo>/.claude/worktrees/*` (not only `agent-*`) and add a case to `bin/cleanup-merged.test.sh`.
- [ ] AC7 — Given `bin/worktree.test.sh`, when it runs, then it covers AC1–AC5 with a temporary bare "origin" repo like `cleanup-merged.test.sh` does, prints `ok`/`FAIL` per case, exit 1 on any FAIL; all existing tests in `testCommand` still pass.

## Non-goals
No changes to agent prompt files or skills (the orchestrator wires `Worktree:` into launchers separately). No removal logic beyond AC6.

## Tests expected
`bin/worktree.test.sh` (AC7) plus the new cleanup case. Integration/E2E: not needed.

## Notes
Read `bin/cleanup-merged.sh` first: reuse its `g()` helper style and its test harness pattern (temporary origin, `gh` stubbed via a fake `gh` on PATH). Worktree dir naming must match what `cleanup-merged.sh` will look for. Keep the script under 60 lines.
