# PI-51 — Reinstall the shared checkout after a lockfile merge, and fail verify on a stale install

**Status**: Done
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: M
**Budget**: 200
**Risk**: high
**Depends on**: none
**Wave**: 1
**Files**: bin/verify.sh, bin/verify.test.sh, .claude/skills/quickfix/SKILL.md, .claude/skills/run-wave/SKILL.md, possibly a new bin/install-drift.sh + bin/install-drift.test.sh (add it to `testCommand` in .pocket-it.json if created)
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**: task/pi-51-reinstall-shared-checkout
**PR**: https://github.com/FCabiddu/pocket-it/pull/96

## Goal
Agent worktrees under `.claude/worktrees/` have no `node_modules` of their own: Node resolves the main checkout's, and `bin/verify.sh` (lines ~110–112) symlinks the main checkout's `node_modules` whenever the branch did not change the lockfile. After a PR that bumps dependencies is merged, nothing reinstalls the main checkout, so every later test run and every `verify.sh` silently runs on the versions installed before the bump — green, but on the wrong code. Observed in a consumer project: a framework was two minor versions behind its lockfile for two days, across several merged PRs, without any red. Expected: (1) the closing step of `/quickfix` and `/run-wave` reinstalls the shared checkout after merging a PR that touched a lockfile, when no agent is running on it; (2) `verify.sh` detects an installed tree that disagrees with the lockfile and fails with an explicit message instead of passing.

## Acceptance criteria
- [ ] AC1 — Given a merged PR whose diff touches any lockfile (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lockb`), when `/quickfix` Step 4 or `/run-wave` closing step runs after `git pull --ff-only`, then the skill runs the lockfile's own frozen install (`npm ci` / `pnpm install --frozen-lockfile` / `yarn install --frozen-lockfile` or `--immutable` / `bun install --frozen-lockfile`) in the main checkout, and reports it in the closing line.
- [ ] AC2 — Given the same merge while another agent is still running against the shared checkout (a background developer/reviewer/qa launched this session, or a worktree under `.claude/worktrees/` that is not the merged PR's), when the closing step runs, then it does NOT reinstall (a reinstall under a running test run corrupts that run's measurements); it logs a deferred reinstall with `bin/handoff.sh log` and the skill says to run it when those agents report. The rule must name the harm ("no reinstall under a running agent"), not a place.
- [ ] AC3 — Given a checkout whose installed package versions differ from the lockfile (at least: any top-level dependency in `node_modules/<name>/package.json` whose `version` differs from the lockfile entry), when `bin/verify.sh` runs — on the branch worktree AND on the symlinked-from-main path — then it exits non-zero with a message naming the package, the installed version, the locked version and the install command to run. Test it for the whole class: npm lockfile v2/v3; pnpm, yarn and bun either handled the same way or explicitly reported as "drift check not supported for <pm>" (never a silent pass).
- [ ] AC4 — Given an install that matches the lockfile, or a project with no lockfile / no `node_modules` (non-JS project), when `verify.sh` runs, then behaviour is unchanged (no new failure, no measurable slowdown beyond reading package.json files).
- [ ] AC5 — Mutation-proven: removing the drift check makes the AC3 test red; loosening it to ignore scoped packages (`@scope/name`) makes a scoped-package test red.

## Tests expected
`bin/verify.test.sh` (or a new `bin/install-drift.test.sh`): fixture directories with a lockfile and a fake `node_modules` — matching, drifted, drifted scoped package, no lockfile, non-npm lockfile. Skill text changes are checked by the reviewer against AC1/AC2. Integration/E2E: not needed.

## Notes
- `verify.sh` already contains the "reuse the main checkout's node_modules when the lockfile is unchanged" branch (around line 110) and a comment about the borrowed-node_modules limit from PI-46 — the drift check belongs next to it.
- Closing steps to edit: `.claude/skills/quickfix/SKILL.md` Step 4 (after `git pull --ff-only`, before `cleanup-merged.sh`) and `.claude/skills/run-wave/SKILL.md` around line 72.
- Repo is public: no consumer-project names, paths or anecdotes in code, comments, tests or PR text.
