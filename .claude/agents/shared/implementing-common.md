# Implementing agents — shared rules

Read once at start by `developer`, `qa-engineer`, `reviewer`. Edit here, never copy into an agent file.

## 1. Project config — never ask, read `.pocket-it.json`

```bash
CFG=$(cat .pocket-it.json 2>/dev/null || echo '{}')
```

| Key | Default | Meaning |
|---|---|---|
| `scope` | `medium` | simple / medium / full — output depth for planning agents |
| `automerge` | `true` | apply the `Auto-merge` label to PRs; the orchestrator merges approved PRs (`false` = review only, the user merges) |
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

- **Zeroth, the method lessons:** `~/.claude/agents/pocket-it/.claude/agents/shared/lessons.md` (≤ 40 one-line lessons, stack-independent, written by the retro across projects). They apply to you whatever the project; a `provisional` one is still followed.
- **First, the facts other agents paid for.** `awk '/^## Fatti/{f=1;next} /^## /{f=0} f && /^- /' docs/SESSION_HANDOFF.md 2>/dev/null` — the whole facts section, up to the cap of 100 one-line facts: invariants, gotchas and decisions written by previous agents (a `cache()` that is a pass-through in tests, a route that must be listed in a census test, a token that must not be redefined). Reading them is how the pipeline learns; if one of them is wrong today, fix it with `handoff.sh fact` and say so in the report.
- Read the task file, then only the TAD sections it references. Extract a section by number, never the whole document:
  `awk '/^## 5\. /,/^## 6\. /' tech-analysis/X_TECH_ANALYSIS.md`
  When the task cites `PROJECT §… · DELTA §…`, the delta (`tech-analysis/{NAME}_TECH_DELTA.md`) overrides the project TAD (`tech-analysis/PROJECT_TECH_ANALYSIS.md`) for those sections.
- If the task cites a `**Contract**:` file, read it in full: it is the agreed API shape between backend and frontend and it is not yours to change without saying so in the PR.
- Do not read the IPD. The task file is self-contained; if it is not, that is a planner bug to report, not a reason to read 800 lines.
- Read a source file **once**. After an `Edit`, do not re-`Read` the whole file; the Edit result already confirmed the change. Re-read a range only when you need lines you have not seen.
- Cap command output: `| head -60`, `--reporter=dot`, `--silent=passed-only`, `2>&1 | tail -40` on compilers. Never dump a whole log.
- Best-practices files: `find . -type d -name best-practices | head -1`, then read only the file(s) for your label. Binding, not advisory — if the task cannot be done without violating one, stop and report the conflict; do not decide alone.

## 4. Tests — unit done well by default, the rest only when it earns its place

**Default policy (overridable per project in `.pocket-it.json` → `tests`):**

| Layer | Default | Who | When |
|---|---|---|---|
| Unit + component | `required` | developer, in the same PR as the code | every task that adds or changes behaviour |
| Integration (a real disposable DB, §9 / real API) | `on-demand` | qa-engineer, as its own QA task | only when the planner justified it: money, auth, data integrity, a contract several clients depend on, or a bug that unit tests could not have caught |
| E2E (browser) | `on-demand` | qa-engineer, as its own QA task | only the 1–3 journeys the product cannot ship broken (checkout, login, the core flow) — never one per screen |
| Accessibility | `required` (floor) | developer (axe on the component), qa if E2E exists | every frontend task |

"Done well" for unit tests means: one behaviour per test named as scenario + outcome; happy path, the edge cases the acceptance criteria imply, and the error paths; behaviour, not implementation; deterministic, independent, factories over inline literals; coverage of the code you wrote, not of the repo. A task whose "Tests expected" section is empty and that changes behaviour is a planner defect — write the tests anyway and say so. A test that asserts an absence (no error, no match, no duplicate) has a sibling test whose input does contain the thing and asserts it is found; run that sibling once with the reading step broken (wrong path, empty input) and see it go red before trusting the absence test — an input never read passes the absence test the same way a clean one does.

`tests.integration` / `tests.e2e` values: `off` (never, even if asked by a task — report instead), `on-demand` (default), `on` (the planner adds a QA task per story). Unit tests cannot be turned off.

**Which tests to run** — the dependency graph, never the whole suite. Resolution order, stop at the first hit: (1) `testCommand` from config or a `test:affected` script in `package.json`; (2) the runner's own selector on the files git says you changed — `vitest related --run <files>`, `jest --findRelatedTests <files>`, `pytest <module>`, `go test ./pkg/...`, `cargo test -p <crate>`; (3) naming convention, and say in the report that scope was heuristic. Changed files, against the remote base — §6 branches from `origin/$BASE`, not a local checkout of it, so compare against the same ref or the list widens or empties depending on how stale the local one is:

```bash
git diff --name-only $(git merge-base "origin/$BASE" HEAD) HEAD; git status --porcelain --untracked-files=all
```

Full suite at most once, as the gate before the PR, and not at all if hosted CI runs it. Integration (a real disposable DB, §9) and browser E2E only if the change touches their surface. Type-check is project-wide by nature; run it after a batch of edits, not after every edit — three consecutive failing type-check rounds on the same error means stop, re-read the error, and change approach.

## 5. Shared machine and worktrees

Other agents and the user's app share this machine. Never `pkill`/`killall` (a hook blocks them anyway): stop your own process by PID or by the port you chose (`lsof -nP -iTCP:3100 -sTCP:LISTEN -t | xargs -r kill`). Port 3000 is the user's. Never use `sleep N && …` to wait — it is blocked; use `gh pr checks N --watch` or a bounded `until` loop. Admit any breach in the report.

**Worktree handed to you.** If your arguments carry `Worktree: <path>` (the orchestrator created it with `bin/worktree.sh` because its session runs from another folder), `cd` there first and stay there: you are already on your branch, never run `git checkout <base>`.

**Worktree gone — stop, never fall back.** Applies whenever you work in a worktree (`Worktree:` given, `isolation: worktree`, or `pwd` under `/.claude/worktrees/` or `/.worktrees/`). The shell's working directory resets between commands to where the session started — usually the project's main checkout — and a worktree can vanish under a running agent (a cleanup after someone else's merge, a manual prune). So:

1. **First command:** `cd '<Worktree: path, if given>' && git rev-parse --show-toplevel`; note the output as `WT`. If it is the project's main checkout although you were meant to be in a worktree, stop here.
2. **Every shell command starts with `cd '<WT>' && …`** — `&&`, never `;`, so nothing runs when the path is gone.
3. **Once, when the branch is yours:** right after §6 creates or checks out your branch — or in the first command, when it was already checked out for you (`Worktree:` given) — note `git branch --show-current` as `BR`.
4. **Every commit carries the branch check:** `cd '<WT>' && [ "$(git branch --show-current)" = '<BR>' ] && git commit …`. Nothing is checked before a file edit: an edit on a vanished path fails by itself, and the next shell command or commit catches the loss before anything is committed.
5. **When a `cd '<WT>'` fails, the branch check fails, or a file tool reports that a path under `<WT>` no longer exists: stop and report** — `WT`, `BR`, the last commit you pushed, what was left uncommitted. Do not recreate the worktree, do not check the branch out elsewhere, and **do not continue in the main checkout or in any other directory** — not for a one-line edit, not for a test run, not for `handoff.sh`. A change made there lands in the tree every other session and every hook reads, with no branch, no review and no PR; lost uncommitted work is recoverable, an unreviewed edit to the shared tree may not be noticed at all. Commit early: uncommitted work is exactly what a vanished worktree takes with it.

**Paths in a worktree.** `<WT>` is the only tree you may touch. Shell commands, after their `cd '<WT>'`, use paths **relative to it** (`tasks/…`, `src/…`, `docs/…`); file tools (`Read`, `Edit`, `Write`) accept only absolute paths, so they get `<WT>/…` and nothing else. Never a path into the project's main checkout (`…/<project>/src/…`) or another worktree (`…/.worktrees/other/…`), never `cd` into another checkout, never `git -C <other path>`. The harness blocks such commands and each block costs a turn; in the 2026-09-06 session it cost 34. If a task file or the orchestrator hands you an absolute path, strip it to the repo-relative part.

## 6. Branch, commit, PR

```bash
BASE={Base: from args, else baseBranch}
git fetch origin
git checkout --no-track -b {branch} "origin/$BASE"   # or: git checkout {branch} && git pull origin {branch}  if "ALREADY EXISTS"
```

Branch straight from `origin/$BASE`: no local checkout of the base, which a worktree cannot do while the base is checked out elsewhere. Skip the block when `Worktree:` was given — you are already on your branch. Right after it, note `BR` (§5, step 3).

Commit early and often (a killed agent loses uncommitted work). Before `git add -A`, check `git status --short` for `.env`/credentials and gitignore them. Commit trailer: `Co-Authored-By: Claude <noreply@anthropic.com>`. Push, then open a **draft** PR against `$BASE` with `gh pr create --draft --base "$BASE" …`. Never `gh pr merge` (the orchestrator merges after the review), never push to `main` directly (hooks block both). If `automerge` is true: `gh label create Auto-merge --color 94a3b8 2>/dev/null || true; gh pr edit $PR_NUM --add-label Auto-merge`. Record `$PR_URL` in the task file. Then log the event — this is the project's memory across sessions, and it is mandatory:

```bash
bash ~/.claude/agents/pocket-it/bin/handoff.sh log "{ID} PR #{n} draft — {what, six words} — {tests added}"
```

`handoff.sh` creates `docs/SESSION_HANDOFF.md` if missing and keeps the log to 40 lines. Use `handoff.sh fact "…"` **only** for something the next agent would otherwise rediscover the hard way (an invariant, a gotcha, a decision and its why) — never for progress. Commit the file with your task file.

**CI-fix mode** (`CI Failure:` in arguments): do not touch task status, do not open a new PR; commit on the existing branch and `gh pr comment $PR "🔧 CI fix — {what}"`.

## 7. Report — the long version on disk, eight lines back

The orchestrator's context is the most expensive thing in the pipeline, so what you return is short and what you write down is complete. Before your final message, write `docs/reports/{ID}-{YYYY-MM-DD}.md` (≤ 40 lines: what changed and why, tests ↔ criteria, deviations, checks run with their result, turns used, anything the next agent needs) and commit it with your task file so it travels in the PR. Then return **at most 8 lines**: ID and status · branch and PR URL · tests added and scoped-run result · turns vs budget and whether `BUDGET`/`STALL` was logged · blockers or deviations in one line · `Report: docs/reports/{ID}-{date}.md`. No prose, no explanations — they are in the file.

## 7b. Write only what belongs to the repo you are in

Every repo you may be launched in falls into one of two kinds, and what you may write down differs.

**A project repo** (the usual case): write freely about that project. Its own names, paths, ids and code are what the task is about.

**This tooling repo** (`pocket-it`): **nothing from any project it works on may appear here — ever, relevant or not.** It is public and the projects are not. Not the project's name, not its product or domain vocabulary, not its file paths, not its PR or issue numbers, not excerpts of its code, documents or data, not a narration of the session it came from. This binds every artefact you produce: the task file, the report, commit messages, the PR title and body, `shared/lessons.md`, `docs/SESSION_HANDOFF.md`.

A tooling bug is almost always found while working on a project. Describe it by its **mechanism** only: the line that breaks, the shape of input that triggers it, the expected behaviour, how to reproduce it from nothing. If you cannot write the diagnosis without naming a project, the diagnosis belongs in that project's report and only the mechanism comes here.

The id shapes this repo defines itself — `T-{e}.{s}.{t}`, `T-BUG-{n}`, `QF-{n}`, `PI-{n}` — are its own conventions, not project data: they stay usable as examples and as test fixtures.

The same care applies to what reaches you: a launch prompt may carry project context because whoever wrote it had that context in mind. Strip it. Nothing obliges you to repeat it, and being told it is not permission to write it down.

## 8. Budget and stop conditions — stop on stall, not on size

Every task carries `**Budget**: N` turns, set by the planner from its estimate (XS 60 · S 120 · M 200 · L 300, or a custom value for work that cannot be split, e.g. "run the whole suite and fix the reds"). Missing → assume 120. The budget is an **expectation, not a wall**: it is there so that a task that costs twice its budget teaches the planner to estimate better, not to interrupt you while you are getting things done.

Two different signals, two different actions:

- **Budget exceeded while progressing** (commits landing, tests turning green): keep going. Log once — `bash ~/.claude/agents/pocket-it/bin/handoff.sh log "BUDGET {ID} ~{turns} turns vs {budget} — progressing: {commits} commits, {tests} tests green — {why bigger than estimated}"` — and finish. The retro reads these lines to correct the estimates.
- **Stall**: no new commit and no additional passing test in the last ~30 turns, or the same error surviving three fix attempts. Stop: commit what is coherent, push, log `handoff.sh log "STALL {ID} ~{turns} turns — {what is stuck, one line}"` and report. A clean partial report is cheaper than a runaway.

Also stop, with the branch pushed, when the task needs a decision only the user can make, a best-practice conflict appears, or the scope turns out to be several tasks (say which). The agent's `maxTurns` (300) is a safety net far above any budget, never the plan; if you hit it, something above already went wrong.

## 9. Rules from real incidents

### Database terms — real, shared, disposable

**Shared** is any database that this run did not create, that is still there when this run ends, or that anything outside this run actually reads or writes while you use it — a person, another agent, another run, or a program that neither you nor a process you started launched. Whatever only carries this run's own reads and writes — the database server or engine that hosts it (already running or started by you, in a container or not), the container runtime, a connection pooler or proxy, the operating system — is part of the path to the database, not something outside this run. Shared examples: an already-running server's own databases, the persistent development database, a staging or production instance, a database a config file points at that you did not create yourself, a container or a file you leave behind for the next run. That something else *could* open it — a port on this machine, a file in a temporary directory — does not make it shared; something outside this run opening it does. **Disposable** is every other database, without exception — exactly the ones this run created, removed before it ends, and nothing outside this run read or wrote in between: a container you start and remove, a file you create and delete, a database you `createdb` and `dropdb`, an in-memory database (a real engine's own in-memory mode, or a stand-in such as pg-mem, H2 or any other fake) that exists only for the process you started — even when a config file such as `.env.test` or a test compose file points at it. Who created it, whether it is gone before this run ends, and whether anything outside this run actually read or wrote it meanwhile decide — those three and nothing else; a config file never does, the engine never does, and the server that hosts it never does. **Real** is a separate axis, engine not lifecycle: the project's own database engine running real queries — Postgres, MySQL, SQLite, on disk or in the engine's own in-memory mode — never a mock, a stub or a stand-in engine (pg-mem, H2, any other fake) standing in for it. Real decides whether a `real DB` requirement is satisfied; it never decides whether you may write — a disposable mock is as writable as a disposable Postgres container, and a real engine does not make a shared instance safe to write to. *This run* is your agent run, from launch to your final report. Every `real DB` / `live DB` mention elsewhere in this file, and every disposable database asked for as proof — an integration test, a migration or a backfill, a query or migration a reviewer's correction is run against — means *real-and-disposable*: a genuine engine created for the run, isolated per rollback/truncate, never the shared one; that is also what `qa-engineer.md`'s integration tests run against. **Realistic data**, for whoever verifies a fix, means realistic rows seeded on a disposable database — never a write, rolled back or not, to a shared one (rules below). If a task needs a `real` disposable database and you cannot create one here (no container runtime, the project only configures a shared instance) — a mock does not satisfy that requirement, and the shared instance is never a substitute for it: stop, push what you have, and report `blocked — no disposable real database: {why}` (§8).

As a check, not a rule of its own: an in-memory SQLite database your test runner opens is disposable, whatever `real` says about it; pg-mem or H2 standing in for Postgres is disposable and not real — it was never shared, so the rules below never reached it anyway. A container this run starts and leaves running is shared, because it is not gone before the run ends; the same container stopped and removed before you finish is disposable. A database you `createdb` on an already-running server and `dropdb` before you finish is disposable — that server hosts it, it does not read it from outside this run — unless another run connects to it meanwhile; every other database on that server stays shared. An existing staging database is shared, and restoring a dump over it is a write to a shared database. A test database a config file points at that you did not create is shared; one you create and remove yourself is disposable regardless of what the config says. A SQLite file your test creates in a temporary directory and deletes before the run ends is disposable, although any other process could have opened it; the same file opened meanwhile by another agent's run is shared.

- **A check that a string is absent never writes that string into anything committed or published** — report, commit message, PR title/body/comment, handoff, or test fixture. Put the pattern in a file outside the repo and run `git grep -c -f <that file>`; write only the effect in the report ("0 occurrences of the removed name across the tree"). Repeating the string anywhere committed republishes what the check proves removed.
- **A migration or a backfill is never applied to a shared database before review and merge.** Prove it on a real disposable one; state the exact command and the target database under the PR's **Manual setup steps**, and add `after merge: apply {migration} to {database}` to your 8-line return — whoever merges cannot read the diff for it.
- **No write to a shared database, ever — insert, delete, truncate, a rolled-back transaction, none of it: not to try something out and not during review.** A transaction you intend to undo is still a write attempted on data other people depend on right now; use a disposable database instead.

### Resume report format

One line per finding, in the report: `closed — {commit}` or `open — {why}`. Never omit a finding that stayed open.

- **Resuming a branch marked `ALREADY EXISTS`: the scope is every finding in every NEEDS WORK comment on the PR (`gh pr view $PR --comments`), plus whatever the resume prompt adds — a prompt can add scope, never remove it.** Check each finding against the current branch head, not against a commit message; report it in the Resume report format above.
