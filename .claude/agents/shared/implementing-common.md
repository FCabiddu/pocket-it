# Implementing agents — shared rules

Read once at start by `developer`, `devops-engineer`, `qa-engineer`, `reviewer`. Edit here, never copy into an agent file.

## 1. Project config — never ask, read `.pocket-it.json`

```bash
CFG=$(cat .pocket-it.json 2>/dev/null || echo '{}')
```

| Key | Default | Meaning |
|---|---|---|
| `scope` | `medium` | simple / medium / full — output depth for planning agents |
| `automerge` | `false` | apply the `Auto-merge` label to PRs |
| `pipeline` | `false` | hosted CI/CD wanted (GitHub Actions + `APP_STATUS`) |
| `baseBranch` | `main` | branch tasks fork from and PRs target (an epic branch if `branching: epic`) |
| `branching` | `flat` | `flat` = task branches off `baseBranch`; `epic` = `epic/...` branches, orchestrator passes `Base:` |
| `testCommand` | auto | project's affected-tests entry point, e.g. `pnpm test:affected` |
| `tests` | `{unit: required, integration: on-demand, e2e: on-demand}` | test policy — see §4 |
| `ticketPrefix` | `T` | task id prefix used by the board |

Rules: a value passed in your arguments (`Base:`, `Label:`, `PR:`) wins over the file; the file wins over the default. If you run in an isolated worktree (`pwd` contains `/.claude/worktrees/` or `/.worktrees/`) you see only **committed** files: a missing `.pocket-it.json`, `tasks/` or TAD there means the orchestrator did not commit them — report that in one line and stop, do not go looking elsewhere. **Never call `AskUserQuestion`**: you run as a subagent and the call fails. If something is genuinely blocking, stop, state the assumption you would need, and report. Missing file = defaults, say so in the report.

## 2. Local board — `tasks/`

One file per task, `tasks/{ID}-{slug}.md`. Header fields are `**Key**: value` (tolerate `**Key:** value` in older projects). Canonical statuses: `Todo`, `In Progress`, `Done`, `Needs Work`.

```bash
TASK_FILE=$(ls ./tasks/{ID}-*.md 2>/dev/null | head -1)
set_status() { sed -i.bak -E "s/^\*\*Status\*\*:.*|^\*\*Status:\*\*.*/**Status**: $1/" "$TASK_FILE" && rm -f "$TASK_FILE.bak"; }
set_field()  { grep -qE "^\*\*$1(\*\*:|:\*\*)" "$TASK_FILE" && sed -i.bak -E "s#^\*\*$1(\*\*:|:\*\*).*#**$1**: $2#" "$TASK_FILE" || printf '**%s**: %s\n' "$1" "$2" >> "$TASK_FILE"; rm -f "$TASK_FILE.bak"; }
```

Use `set_status "In Progress"` before code, `set_status Done` after checks pass, `set_field PR "$PR_URL"`, `set_field Branch "$BRANCH"`. Never edit `tasks/INDEX.md` by hand — it is regenerated with `bash ~/.claude/agents/pocket-it/bin/tasks-index.sh` by whoever needs it up to date (planner, reviewer, orchestrator).

## 3. Read discipline — the cost is what you read back

- Read the task file, then only the TAD sections it references. Extract a section by number, never the whole document:
  `awk '/^## 5\. /,/^## 6\. /' tech-analysis/X_TECH_ANALYSIS.md`
- Do not read the IPD. The task file is self-contained; if it is not, that is a planner bug to report, not a reason to read 800 lines.
- Read a source file **once**. After an `Edit`, do not re-`Read` the whole file; the Edit result already confirmed the change. Re-read a range only when you need lines you have not seen.
- Cap command output: `| head -60`, `--reporter=dot`, `--silent=passed-only`, `2>&1 | tail -40` on compilers. Never dump a whole log.
- Best-practices files: `find . -type d -name best-practices | head -1`, then read only the file(s) for your label. Binding, not advisory — if the task cannot be done without violating one, stop and report the conflict; do not decide alone.

## 4. Tests — unit done well by default, the rest only when it earns its place

**Default policy (overridable per project in `.pocket-it.json` → `tests`):**

| Layer | Default | Who | When |
|---|---|---|---|
| Unit + component | `required` | developer, in the same PR as the code | every task that adds or changes behaviour |
| Integration (real DB / real API) | `on-demand` | qa-engineer, as its own QA task | only when the planner justified it: money, auth, data integrity, a contract several clients depend on, or a bug that unit tests could not have caught |
| E2E (browser) | `on-demand` | qa-engineer, as its own QA task | only the 1–3 journeys the product cannot ship broken (checkout, login, the core flow) — never one per screen |
| Accessibility | `required` (floor) | developer (axe on the component), qa if E2E exists | every frontend task |

"Done well" for unit tests means: one behaviour per test named as scenario + outcome; happy path, the edge cases the acceptance criteria imply, and the error paths; behaviour, not implementation; deterministic, independent, factories over inline literals; coverage of the code you wrote, not of the repo. A task whose "Tests expected" section is empty and that changes behaviour is a planner defect — write the tests anyway and say so.

`tests.integration` / `tests.e2e` values: `off` (never, even if asked by a task — report instead), `on-demand` (default), `on` (the planner adds a QA task per story). Unit tests cannot be turned off.

**Which tests to run** — the dependency graph, never the whole suite. Resolution order, stop at the first hit: (1) `testCommand` from config or a `test:affected` script in `package.json`; (2) the runner's own selector on the files git says you changed — `vitest related --run <files>`, `jest --findRelatedTests <files>`, `pytest <module>`, `go test ./pkg/...`, `cargo test -p <crate>`; (3) naming convention, and say in the report that scope was heuristic. Changed files:

```bash
git diff --name-only $(git merge-base $BASE HEAD) HEAD; git status --porcelain --untracked-files=all
```

Full suite at most once, as the gate before the PR, and not at all if hosted CI runs it. Integration (live DB) and browser E2E only if the change touches their surface. Type-check is project-wide by nature; run it after a batch of edits, not after every edit — three consecutive failing type-check rounds on the same error means stop, re-read the error, and change approach.

## 5. Shared machine and worktrees

Other agents and the user's app share this machine. Never `pkill`/`killall` (a hook blocks them anyway): stop your own process by PID or by the port you chose (`lsof -nP -iTCP:3100 -sTCP:LISTEN -t | xargs -r kill`). Port 3000 is the user's. Stay inside your worktree; never edit the main checkout or another worktree. Never use `sleep N && …` to wait — it is blocked; use `gh pr checks N --watch` or a bounded `until` loop. Admit any breach in the report.

## 6. Branch, commit, PR

```bash
BASE={Base: from args, else baseBranch}
git fetch origin && git checkout "$BASE" && git pull --ff-only origin "$BASE"
git checkout -b {branch}            # or: git checkout {branch} && git pull origin {branch}  if "ALREADY EXISTS"
```

Commit early and often (a killed agent loses uncommitted work). Before `git add -A`, check `git status --short` for `.env`/credentials and gitignore them. Commit trailer: `Co-Authored-By: Claude <noreply@anthropic.com>`. Push, then open a **draft** PR against `$BASE` with `gh pr create --draft --base "$BASE" …`. Never `gh pr merge`, never push to `main` directly (hooks block both). If `automerge` is true: `gh label create Auto-merge --color 94a3b8 2>/dev/null || true; gh pr edit $PR_NUM --add-label Auto-merge`. Record `$PR_URL` in the task file. If `docs/SESSION_HANDOFF.md` exists, prepend a 1–3 line entry (ID, PR "(draft)", what/why); never create it.

**CI-fix mode** (`CI Failure:` in arguments): do not touch task status, do not open a new PR; commit on the existing branch and `gh pr comment $PR "🔧 CI fix — {what}"`.

## 7. Stop conditions

You have a turn budget. Stop early and report partial progress, with the branch pushed, when: the same error survives three fix attempts; the task needs a decision only the user can make; a best-practice conflict appears; or the scope turns out to be several tasks. A clean partial report is cheaper than a runaway.
