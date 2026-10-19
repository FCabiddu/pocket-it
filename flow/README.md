# flow — reference

The details of the flow: who does what, the scripts, the project templates and the hooks. The flow itself, in three diagrams, is in [`FLOW.md`](FLOW.md); the global rules are in [`CLAUDE.md`](CLAUDE.md).

## Who does what

- **Main session**: launches the agents, carries their questions to the user, merges and reports. Writes no code during a wave.
- **`analyst`**: turns the request into verifiable requirements (`docs/features/<slug>/requirements.md`) and says what is feasible on today's code. The requirements are the only document the user approves.
- **`architect`**: chooses the technical solution and writes the design: an index `technical-design.md` plus one file per topic in `technical-design/`, at most 150 lines each; discarded alternatives and parts already merged go to `archive/`, which no task cites. Keeps the project's directives (stack, patterns, tests, invariants) up to date and checks the tasks before they start.
- **`task-writer`**: splits the design into small tasks, one PR each with its acceptance criteria and their command, grouped into waves; for every wave it also writes the tester's task `E2E-<n>`.
- **`developer`**: does one task in its own worktree, runs the fast tests (unit, lint, typecheck), opens the PR with the results and fixes what the reviewer asks.
- **`reviewer`**: reads the code and the results reported in the PR, without running tests, against the task and the directives; answers `APPROVED` or `CHANGES`. Never merges.
- **`security`**: looks at the project the way an attacker would, with the principles in `flow/docs/security.md`. Once, at the start, it audits the whole project; at the end of every wave, in parallel with the tester, it looks for the holes the wave's diff opened. Without its sign-off (`security-ok.sh`) `merge-pr.sh` does not take the wave to `main`. Writes no code.
- **`tester`**: at the end of a wave, on the wave branch, writes the end-to-end tests and runs them once together with the existing ones that cover the changed files. Every red becomes either a fix to its own test, a flaky test, or an app bug that goes to a developer as a task.

**Wave**: a group of independent tasks that run in parallel on a branch `wave/<slug>-<n>`. It reaches `main` only with green E2E and the security sign-off, and the next wave starts from there.

## Scripts (`flow/bin/`)

| Script | When | What it does |
|---|---|---|
| `worktree-new.sh <branch> [base]` | before launching an agent | Creates the agent's worktree (with `NOTE.md`, the agent's progress notes, kept out of git); `--review <PR>` for the reviewer's |
| `design-check.sh` | the architect, when checking tasks | Flags design files over 150 lines, references to headings that do not exist or to the archive, tasks without a «To read» (reading list) section |
| `project-ready.sh [--dry-run]` | once, at the start of a project | Checks that the project has its directives, the `E2E:`, `Deploy from main:` and `Commands only with approval:` lines in `CLAUDE.md`, `scripts/pre-merge.sh`, `scripts/e2e.sh`, `scripts/e2e-select.sh` and a `.claude/settings.json` with the sandbox (keys and types); whatever is missing, the architect creates from the templates |
| `merge-pr.sh <PR>` | once a PR is approved | Checks the plan `tasks/<slug>/INDEX.md` if the PR touches `tasks/` (`plan.sh`), runs the project's `scripts/pre-merge.sh` (without it, no merge), for a wave going to `main` requires the security sign-off, merges into the PR's base and removes worktree and branch |
| `security-ok.sh <PR>` | after the security agent's `SECURITY OK` | Marks the head commit of the wave PR (status «security»); a commit added later asks for a new check |
| `stop-worktree-procs.sh <dir>` | inside `merge-pr.sh` | Stops the processes still running in a worktree (servers, watchers) before removing it |
| `errors.sh --wave <slug>-<n> [--rules v7]` | at the end of a wave | Shows the errors logged since the previous run and a summary of the agent launches (how many per type, durations, turns, tokens, outcomes, who is near the turn limit, who compacted, who left without finishing); with `--wave` it appends the wave's row to the project's board `docs/recap/metrics.md` (tasks, PRs, review rounds, reruns, launches, duration, tokens; `damage` and `friction` are filled in by the reader) |
| `clean-wave.sh <slug> <wave> <PR>` | at the end of a wave, after the error check | Removes the wave's tasks from `main` with a PR it merges by itself (on the last wave also `tasks/<slug>` and `docs/features/<slug>`), and the worktrees and branches left over from the wave (`wave-worktrees.sh`); `--dry-run` shows what it would do |
| `wave-worktrees.sh <slug> <wave\|all> [<PR>...]` | inside `clean-wave.sh` | Removes the `sec/`, `test/`, `tasks/` worktrees and branches of a finished wave and the `rev-<PR>` ones; skips a worktree with uncommitted changes |

## Project templates (`flow/templates/`)

The agents are the same for every project; what changes lives in a few project scripts with a fixed contract: `pre-merge.sh` (fast checks before a merge), `e2e.sh` (one E2E run at a time, with a queue and a log), `e2e-select.sh` with `spec-per-folder.txt` (which specs to run given the changed files). On a new project the architect copies them from here and adapts only the «TO ADAPT» (to adapt) block. What each must do: [`flow/templates/README.md`](flow/templates/README.md).

At the end of a wave, errors are split into **damage** (lost work, data touched without consent, money spent, a push to `main`, wrong code on `main`, a task stuck with no way out: a recap is written) and **friction** (everything else: one line in `docs/recap/friction.md`; the third occurrence becomes damage).

## Hooks (`flow/hooks/`)

Every hook has its own test file `<name>-cases.sh`, run after every change.

- **`guard.sh`**: blocks pushes to `main` and force pushes, ignoring text inside heredocs and quotes; overridden with `ALLOW_MAIN_PUSH=1`.
- **`reviewer-edit.sh`** (PreToolUse on `Edit|Write|NotebookEdit`): agents write only inside `.claude/worktrees/`.
- **`cd-main.sh`** (PreToolUse on `Bash`): the main session does not `cd` or `pushd` into `.claude/worktrees/`, because the shell would stay there; `git -C`, absolute paths and `(cd <worktree> && …)` pass. Agents, in turn, do not run state-changing git commands (`merge`, `checkout`, `reset`, `commit`…) in the main checkout, even after a failed `cd`.
- **`read-limit.sh`** (PreToolUse on `Read|Bash`): developer, reviewer and tester read at most 300 lines of a file at a time, with Read, `cat` or `sed -n`.
- **`global-memory.sh`** (PreToolUse on `Edit|Write|NotebookEdit|Bash`): nothing about a project enters the global memory (`~/.claude/projects/<home>/memory/`). It blocks `type: project` memories and any memory that names a project (a git repo under `~/Desktop` or a folder with a memory of its own); every other write there, even from Bash, asks the user.
- **`costly-commands.sh`** (PreToolUse on `Bash`): stops a subagent that runs a command listed in the `Commands only with approval:` line of the project's `CLAUDE.md` (deploys, databases with real data, paid calls) and tells it to ask in its report; the main session passes (`flow/templates/README.md`).
- **`log-errors.sh`**: logs denied permissions and failed commands to `~/.claude/logs/errors/`, which `errors.sh` reads.
- **`log-launches.sh`** (SubagentStart, SubagentStop, PreCompact): logs every agent launch to `~/.claude/logs/launches/` (type, outcome read from the first lines of the report, turns, tokens and model from the subagent's transcript, compactions), which `errors.sh` summarises. Entries expire after 30 days; it never blocks anything.

Every agent carries only the instructions of its own job. A new rule is approved by the owner.

Protocol words (`APPROVED`, `CHANGES`, `SECURITY OK`, `E2E GREEN`, `RERUN`) and the project files the flow expects are literals checked by the scripts and hooks: change one, and its cases file goes red.

## Hook wiring

Wire the hooks in `~/.claude/settings.json`, each as `bash ~/Desktop/agents/flow/hooks/<name>.sh`:

| Event | Matcher | Hooks |
|---|---|---|
| PreToolUse | `Bash` | `guard.sh`, `costly-commands.sh`, `cd-main.sh`, `global-memory.sh` |
| PreToolUse | `Edit\|Write\|NotebookEdit` | `reviewer-edit.sh`, `global-memory.sh` |
| PreToolUse | `Read\|Bash` | `read-limit.sh` |
| PermissionDenied, PostToolUseFailure | — | `log-errors.sh` |
| SubagentStart, SubagentStop, PreCompact | — | `log-launches.sh` |

## Run the tests

Every hook and script has a `<name>-cases.sh` file next to it: temporary folders, `PASS`/`FAIL` per case, exit 1 if one fails. From `flow/`:

```bash
for f in hooks/*-cases.sh bin/*-cases.sh; do bash "$f" >/dev/null && echo "ok   $f" || echo "FAIL $f"; done
```
