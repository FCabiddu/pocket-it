# PI-4 — guard.sh: block a bare `git push` (no refspec) when the current branch is main/master

**Status**: Done
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: XS
**Budget**: 60
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: `.claude/hooks/guard.sh`, `.claude/hooks/guard.test.sh`
**TAD**: none
**Contract**: none
**Branch**: task/PI-4-guard-bare-push
**PR**: https://github.com/FCabiddu/pocket-it/pull/19

## Goal
The PreToolUse hook blocks `git push origin main` but not `git push`, `git push origin HEAD` or `git push -u origin HEAD` run while the checkout is on `main`. On 2026-09-09 the orchestrator pushed a commit straight to main this way by accident (a `cd` had failed and the command ran in the main checkout). The hook must resolve the branch the push would update and block it when it is `main` or `master`.

## Acceptance criteria
- [ ] AC1 — Given the cwd is a git repo on branch `main`, when the command is `git push`, `git push origin HEAD`, `git push -u origin HEAD`, `git push -q origin HEAD:main` or `git push origin HEAD:refs/heads/main`, then the hook exits 2 with the existing "never push to main" message (extended with "current branch is main — use a branch and a PR").
- [ ] AC2 — Given the cwd is on branch `feat/x`, when the same commands run, then they pass (exit 0) — including `git push origin HEAD` and `git push -u origin feat/x`.
- [ ] AC3 — Given a compound command (`cd /some/repo && git push origin HEAD`, `git -C /path push origin HEAD`), when the hook runs, then it resolves the branch of THAT repo (`cd` target or `-C` path) rather than the hook's cwd; if the path cannot be resolved, it falls back to the hook's cwd; if that is not a git repo, the command passes.
- [ ] AC4 — Given `git push --force`/`-f` to any ref of main/master by name or by current branch, when the hook runs, then it is blocked as today.
- [ ] AC5 — Given `.claude/hooks/guard.test.sh`, when it runs, then AC1–AC4 are covered with temporary git repos on the two branches (the existing tests are string-only — add a small fixture helper), `ok`/`FAIL` per case, exit 1 on FAIL; all existing cases still pass; `guard.heredoc.test.sh` still passes.

## Non-goals
No change to the other guard rules (merge prefix, pkill, APP_STATUS, sleep). No blocking of pushes to other branches.

## Tests expected
Extended `guard.test.sh`. Integration/E2E: not needed.

## Notes
The hook receives the command as JSON on stdin (see the top of `guard.sh` for how `CMD` is extracted); the hook's cwd is the session cwd. Keep the branch resolution cheap: `git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null`. Read `guard.test.sh` first to reuse its `expect_block`/`expect_pass` helpers.
