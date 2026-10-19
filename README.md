# pocket-it

An agent system for [Claude Code](https://claude.com/claude-code) that takes a feature from the request to `main` through dedicated agents, each with one job: **analyst**, **architect**, **task-writer**, **developer**, **reviewer**, **security**, **tester**. Hooks stop an agent before it does harm, scripts enforce the gates (pre-merge checks, security sign-off, end-to-end tests), and the rules stay short because whatever can be enforced by a script is not written as a rule.

**Why it exists.** One session that does everything loses context, skips steps and merges code nobody checked. Here every agent gets only the instructions of its own work, runs in its own git worktree, and every claim in a pull request comes with the command that proves it. The main session launches agents, carries their questions to the user, merges and reports; during a wave it writes no code.

**How it is laid out.** This folder is installed as `~/.claude/agents` (a symlink). Claude Code loads every agent from `~/.claude/agents/**/.claude/agents/*.md`, so the checkout stays on `main` and the agents are read when a session starts.

| Folder | What |
|---|---|
| `lite/` | The software-delivery flow, explained below |
| `mvp-builder/` | Builds static sites (no framework, no build step) with its `design-compass.md` |
| `legal-advisor/` | Privacy policy, cookie policy, terms and conditions for a client site (EU/Italy) |
| `legal-check/` | Legal audit of one's own products (card games, board games, online role-playing games with a game master): rights and licences, privacy, payments, marketing, product safety, AI, third-party disclaimers. Writes a report, never touches the product |
| `link-skills.sh` | Rebuilds `~/.claude/skills` from every `*/.claude/skills/*/` folder |

## Design choices

- **One job per agent, short instructions.** Every agent file is 20–45 lines. An agent that knows less about the rest of the flow makes fewer assumptions about it.
- **Proof in the PR, not trust.** Every acceptance criterion has a command and a tolerance; the developer pastes the runs in the PR body, the reviewer reads them without rerunning, `pre-merge.sh` reruns the fast checks before the merge.
- **Gates are scripts, not sentences.** Pushes to `main`, force pushes, edits outside a worktree, costly commands and writes to the global memory are stopped by hooks with their own test cases. A rule is written only when no script can enforce it.
- **Isolation by default.** Each agent works in its own git worktree; the agents' Bash runs inside the Claude Code sandbox (project only, GitHub and npm only, no `.env`).
- **Errors are sorted, not collected.** Damage gets a recap that ends in a removed instruction, a new hook or, last, a rule. Friction gets one line, and only the third occurrence is worth a fix.

## Install

```bash
git clone https://github.com/FCabiddu/pocket-it.git ~/Desktop/agents
ln -s ~/Desktop/agents ~/.claude/agents     # Claude Code loads */.claude/agents/*.md from here
cp ~/Desktop/agents/lite/CLAUDE.md ~/.claude/CLAUDE.md
~/Desktop/agents/link-skills.sh             # rebuilds ~/.claude/skills
```

Then wire the hooks in `~/.claude/settings.json`, each as `bash ~/Desktop/agents/lite/hooks/<name>.sh`:

| Event | Matcher | Hooks |
|---|---|---|
| PreToolUse | `Bash` | `guard.sh`, `comandi-costosi.sh`, `cd-principale.sh`, `memoria-globale.sh` |
| PreToolUse | `Edit\|Write\|NotebookEdit` | `reviewer-edit.sh`, `memoria-globale.sh` |
| PreToolUse | `Read\|Bash` | `read-limit.sh` |
| PermissionDenied, PostToolUseFailure | — | `log-errors.sh` |
| SubagentStart, SubagentStop, PreCompact | — | `log-lanci.sh` |

In a project, run `lite/bin/progetto-pronto.sh` once. Requirements: macOS or Linux, bash, python3, git, `gh` logged in.

## Run the tests

Every hook and script has a `<name>-cases.sh` file next to it: temporary folders, `PASS`/`FAIL` per case, exit 1 if one fails.

```bash
for f in lite/hooks/*-cases.sh lite/bin/*-cases.sh; do bash "$f" >/dev/null && echo "ok   $f" || echo "FAIL $f"; done
```

## lite

`lite/CLAUDE.md` holds the global rules: install them by copying the file to `~/.claude/CLAUDE.md`. The flow, in three diagrams, is in [`lite/FLUSSO.md`](lite/FLUSSO.md).

### Who does what

- **Main session**: launches the agents, carries their questions to the user, merges and reports. Writes no code during a wave.
- **`analyst`**: turns the request into verifiable requirements (`docs/features/<slug>/requisiti.md`) and says what is feasible on today's code. The requirements are the only document the user approves.
- **`architect`**: chooses the technical solution and writes the design: an index `design-tecnico.md` plus one file per topic in `design-tecnico/`, at most 150 lines each; discarded alternatives and parts already merged go to `archivio/`, which no task cites. Keeps the project's directives (stack, patterns, tests, invariants) up to date and checks the tasks before they start.
- **`task-writer`**: splits the design into small tasks, one PR each with its acceptance criteria and their command, grouped into waves; for every wave it also writes the tester's task `E2E-<n>`.
- **`developer`**: does one task in its own worktree, runs the fast tests (unit, lint, typecheck), opens the PR with the results and fixes what the reviewer asks.
- **`reviewer`**: reads the code and the results reported in the PR, without running tests, against the task and the directives; answers `APPROVED` or `CHANGES`. Never merges.
- **`security`**: looks at the project the way an attacker would, with the principles in `lite/docs/sicurezza.md`. Once, at the start, it audits the whole project; at the end of every wave, in parallel with the tester, it looks for the holes the wave's diff opened. Without its sign-off (`sicurezza-ok.sh`) `merge-pr.sh` does not take the wave to `main`. Writes no code.
- **`tester`**: at the end of a wave, on the wave branch, writes the end-to-end tests and runs them once together with the existing ones that cover the changed files. Every red becomes either a fix to its own test, a flaky test, or an app bug that goes to a developer as a task.

**Wave**: a group of independent tasks that run in parallel on a branch `onda/<slug>-<n>`. It reaches `main` only with green E2E and the security sign-off, and the next wave starts from there.

### Scripts (`lite/bin/`)

| Script | When | What it does |
|---|---|---|
| `worktree-new.sh <branch> [base]` | before launching an agent | Creates the agent's worktree (with `NOTE.md`, the agent's progress notes, kept out of git); `--review <PR>` for the reviewer's |
| `design-check.sh` | the architect, when checking tasks | Flags design files over 150 lines, references to headings that do not exist or to the archive, tasks without a «Da leggere» (reading list) section |
| `progetto-pronto.sh [--prova]` | once, at the start of a project | Checks that the project has its directives, the `E2E:`, `Deploy da main:` and `Comandi solo con ok:` lines in `CLAUDE.md`, `scripts/pre-merge.sh`, `scripts/e2e.sh`, `scripts/e2e-scelta.sh` and a `.claude/settings.json` with the sandbox (keys and types); whatever is missing, the architect creates from the templates |
| `merge-pr.sh <PR>` | once a PR is approved | Checks the plan `tasks/<slug>/INDEX.md` if the PR touches `tasks/` (`piano.sh`), runs the project's `scripts/pre-merge.sh` (without it, no merge), for a wave going to `main` requires the security sign-off, merges into the PR's base and removes worktree and branch |
| `sicurezza-ok.sh <PR>` | after the security agent's `SICUREZZA OK` | Marks the head commit of the wave PR (status «security»); a commit added later asks for a new check |
| `stop-worktree-procs.sh <dir>` | inside `merge-pr.sh` | Stops the processes still running in a worktree (servers, watchers) before removing it |
| `errori.sh --onda <slug>-<n> [--regole v7]` | at the end of a wave | Shows the errors logged since the previous run and a summary of the agent launches (how many per type, durations, turns, tokens, outcomes, who is near the turn limit, who compacted, who left without finishing); with `--onda` it appends the wave's row to the project's board `docs/recap/metriche.md` (tasks, PRs, review rounds, reruns, launches, duration, tokens; `danni` and `attriti` are filled in by the reader) |
| `pulisci-onda.sh <slug> <onda> <PR>` | at the end of a wave, after the error check | Removes the wave's tasks from `main` with a PR it merges by itself (on the last wave also `tasks/<slug>` and `docs/features/<slug>`); `--prova` is a dry run |

### Project templates (`lite/templates/`)

The agents are the same for every project; what changes lives in a few project scripts with a fixed contract: `pre-merge.sh` (fast checks before a merge), `e2e.sh` (one E2E run at a time, with a queue and a log), `e2e-scelta.sh` with `spec-per-cartella.txt` (which specs to run given the changed files). On a new project the architect copies them from here and adapts only the «DA ADATTARE» (to adapt) block. What each must do: [`lite/templates/README.md`](lite/templates/README.md).

At the end of a wave, errors are split into **damage** (lost work, data touched without consent, money spent, a push to `main`, wrong code on `main`, a task stuck with no way out: a recap is written) and **friction** (everything else: one line in `docs/recap/attriti.md`; the third occurrence becomes damage).

### Hooks (`lite/hooks/`)

Every hook has its own test file `<name>-cases.sh`, run after every change.

- **`guard.sh`**: blocks pushes to `main` and force pushes, ignoring text inside heredocs and quotes; overridden with `ALLOW_MAIN_PUSH=1`.
- **`reviewer-edit.sh`** (PreToolUse on `Edit|Write|NotebookEdit`): agents write only inside `.claude/worktrees/`.
- **`cd-principale.sh`** (PreToolUse on `Bash`): the main session does not `cd` or `pushd` into `.claude/worktrees/`, because the shell would stay there; `git -C`, absolute paths and `(cd <worktree> && …)` pass. Agents, in turn, do not run state-changing git commands (`merge`, `checkout`, `reset`, `commit`…) in the main checkout, even after a failed `cd`.
- **`read-limit.sh`** (PreToolUse on `Read|Bash`): developer, reviewer and tester read at most 300 lines of a file at a time, with Read, `cat` or `sed -n`.
- **`memoria-globale.sh`** (PreToolUse on `Edit|Write|NotebookEdit|Bash`): nothing about a project enters the global memory (`~/.claude/projects/<home>/memory/`). It blocks `type: project` memories and any memory that names a project (a git repo under `~/Desktop` or a folder with a memory of its own); every other write there, even from Bash, asks the user.
- **`comandi-costosi.sh`** (PreToolUse on `Bash`): stops a subagent that runs a command listed in the `Comandi solo con ok:` line of the project's `CLAUDE.md` (deploys, databases with real data, paid calls) and tells it to ask in its report; the main session passes (`lite/templates/README.md`).
- **`log-errors.sh`**: logs denied permissions and failed commands to `~/.claude/logs/errori/`, which `errori.sh` reads.
- **`log-lanci.sh`** (SubagentStart, SubagentStop, PreCompact): logs every agent launch to `~/.claude/logs/lanci/` (type, outcome read from the first lines of the report, turns, tokens and model from the subagent's transcript, compactions), which `errori.sh` summarises. Entries expire after 30 days; it never blocks anything.

Every agent carries only the instructions of its own job. A new rule is approved by the owner.

Script names, protocol words (`APPROVED`, `CHANGES`, `SICUREZZA OK`, `E2E VERDE`, `RIGIRA`) and the project files the flow expects are in Italian: they are literals checked by the scripts and hooks.
