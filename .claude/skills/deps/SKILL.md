## Deps — the monthly dependency lane

Dependabot opens one PR per bump and nobody validates them on projects without hosted CI; they pile up (nine open for three weeks on one project). This lane folds them into **one** validated PR a month. Runs in the main session; spawns only `developer` and `reviewer`.

Arguments (optional): `$ARGUMENTS` — `dry-run` (list only), `majors` (include major bumps, default excluded).

### 1. Inventory (zero tokens)
```bash
gh pr list --author app/dependabot --state open --json number,title,headRefName --jq '.[] | "#\(.number) \(.headRefName) \(.title)"'
```
Split into **minor/patch** (default scope) and **majors** (title says `from X.` to `Y.` with a different first number, or the branch is a `*-major-*` group). Majors are excluded unless `majors` was passed: they get their own `/quickfix` task each, with the changelog link in Notes. `dry-run` → print the two lists and stop.

### 2. Task file
Write `tasks/QF-{n}-deps-rollup-{YYYY-MM}.md` with the quickfix template (`Label: DevOps`, `Estimate: S`, `Budget: 120`, `Risk: low`). Goal: one branch that merges every listed dependabot branch, lockfile regenerated once, **full** test suite green once (this lane is the one exception to "affected tests only"), type-check and lint clean. Acceptance criteria: AC1 every listed PR's bump is present in `package.json`/lockfile; AC2 full suite, type-check, lint green with output tails in the PR body; AC3 no source change outside `package.json`, the lockfile and files a codemod had to touch (listed and justified). Notes: the PR numbers and branch names; the command `git merge origin/<branch>` per PR, resolving lockfile conflicts by regenerating it, never by hand. Commit and push the task file (worktree rule from `/quickfix` §3).

### 3. Launch, review, close
Same as `/quickfix` §3–§4 (developer → reviewer with `verify.sh` → merge with the audit prefix). After the merge: close every folded dependabot PR with `gh pr close {n} --comment "Folded into #{m}"` and `gh pr list --author app/dependabot --state open` must be empty except majors. Log: `handoff.sh log "deps {YYYY-MM}: {k} bumps folded into PR #{m}, {j} majors left as tasks"`.

### 4. Reduce the noise at the source (once per project)
If `.github/dependabot.yml` has `schedule.interval: weekly` and no `groups`, that scheduling is a pipeline setting, not a business one: edit it yourself (monthly + grouped form — one group for minor/patch, majors ungrouped), commit it on the base branch, and report the change made — not a line for the user to approve first.
