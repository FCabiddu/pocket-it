## Run-wave — launch everything that is ready, review it once, stop

Runs in the main session. The decision of *what* to launch is made by a script, not by you; your job is to turn its output into Agent calls, wait, run one review, and report. Keep the session thin: no reading of task files, TADs or diffs here — that is the agents' work.

Arguments (optional): `$ARGUMENTS` — e.g. `dry-run`, `draft` (review only, no merge), or `only T-3.1.1, T-3.2.1`.

### 1. Pre-flight (zero tokens)
```bash
bash ~/.claude/agents/pocket-it/bin/doctor.sh && bash ~/.claude/agents/pocket-it/bin/next-wave.sh
```
Any `ERROR` from doctor → stop and show it; do not launch. `next-wave` prints one JSON line per ready task (`issue`, `label`, `agent`, `model`, `risk`, `files`). Zero ready and some `in progress` → say which are running and stop. Zero ready and zero in progress and not everything Done → show the blocked list; the user decides.

`dry-run` → print the launch plan and stop.

### 2. Launch — all ready tasks in ONE message
For every JSON line, one Agent call in the same message:
- `subagent_type`: the `agent` field (`developer` or `qa-engineer`) — **never `general-purpose`**: it has no rules, no budget and no read discipline; a task that fits no named agent is a missing agent, not a reason to improvise a prompt
- `model`: the `model` field (`opus` only for `risk: high`)
- `isolation`: `worktree` — **only if the session cwd is the project repo** (`git rev-parse --show-toplevel` = the project). From any other folder (the orchestrator running from a hub outside the project) the Agent tool would create a worktree of the wrong repo: instead run `WT=$(bash ~/.claude/agents/pocket-it/bin/worktree.sh <project-path> task/{issue}-{slug})` first, omit `isolation`, and add `Worktree: $WT` to the prompt (the agent `cd`s there; shared rules §5).
- `run_in_background`: `true`
- `description`: `{issue} {label}`
- `prompt`: `Issue: {issue} — {title from tasks/}\nLabel: {label}` plus `Base: {epic branch}` when config `branching` is `epic`.

Then stop and wait for the task notifications. Do not poll, do not read files while waiting.

### 3. Collect
When all notifications are in: list per task the branch, PR and one-line outcome from each report. A task that stopped early (partial / maxTurns / blocker) is **resumed** with SendMessage to the same agent when the blocker is something you can answer from the reports; otherwise it is reported to the user, never relaunched from scratch.

### 4. Review — one reviewer for the wave
One Agent call: `subagent_type: reviewer`, prompt `Tasks: {all task IDs that opened a PR}` plus `Draft: yes` when config `automerge` is `false` or the user's request / `$ARGUMENTS` contain `draft`. Wait.

NEEDS WORK items → one developer each, in one message, background, prompt `Issue: {id} — {title}\nLabel: {label}\nBranch: {branch} ALREADY EXISTS\nPR: {n}` plus the reviewer's findings verbatim. Then one more reviewer call for those PRs only with `Mode: delta` (reads only the fix commits — cheap). At most two review rounds per wave; what is still red after that goes to the user. **Never merge a PR that carries `needs-work` without that delta re-review**, however small the fix: the reviewer swaps the labels, and a merged PR left with `needs-work` corrupts the retro's numbers.

### 5. Close the wave
- APPROVED PRs: merge them, one by one — `POCKET_IT_USER_MERGE=1 gh pr merge {n} --squash --delete-branch` (the hook's authorised form; the prefix is the audit trail that the merge is covered by the `automerge: true` default). Skip the merge only when config `automerge` is `false` or the user's request / `$ARGUMENTS` contain `draft`: then list the approved PRs for the user, who merges. Never open or merge the epic→main PR of a deployed project here — that is a deploy, done only on explicit instruction.
- `git pull --ff-only` the base branch, then `bash ~/.claude/agents/pocket-it/bin/tasks-index.sh` and `bash ~/.claude/agents/pocket-it/bin/handoff.sh log "wave {n} closed — {merged}/{launched} merged, {approved-draft} awaiting user merge, {needs-work} needs work"`, commit `tasks/` and `docs/` on the base branch, `POCKET_IT_ORCHESTRATOR_PUSH=1 git push` (the hook's authorized form for a push to the base branch, same audit-prefix shape as the merge above).
- Then `bash ~/.claude/agents/pocket-it/bin/cleanup-merged.sh`: removes the worktrees and local branches of the merged PRs (dirty, locked and unmerged ones are kept and listed). Report its summary line (`cleanup-merged: N worktrees removed, … freed X MB`).
- **Learning hooks.** Read the wave's `BUDGET` and `STALL` lines from the handoff log (`grep -E "^- .*(BUDGET|STALL) " docs/SESSION_HANDOFF.md | head`) and list them in the report: they are the raw material of the retro. If `next-wave.sh` now reports everything Done (the board is complete), launch the retro **now**, before reporting: one Agent call `subagent_type: retro`, prompt `{epic id or "board completed {date}"}`, wait, and include its summary — nobody else will launch it once the session closes.
- **Session hygiene.** The call to compact is yours, not the user's — it is not a question to put to them. You cannot make it happen from here either: no tool, hook or command starts a compaction, and the running session cannot read its own context usage — that stays with the runtime, never with you. What is yours is the call and the moment, and any **one** of these signals, counted only from what **you** have launched and reviewed in this conversation since it started or was last compacted (not from the handoff log in general — another session can log a wave the same day, and its lines carry no marker of who wrote them), is enough on its own to make the call: a second wave you have closed in this session, a wave that needed a second review round (NEEDS WORK → delta), or an agent you resumed after a stop. Do not wait for a fixed count or for more than one signal to line up — one is enough, because a compaction taken one wave early costs a few seconds and one taken late costs a session's worth of decisions made on degraded judgment. The moment any signal fires, end the report with a statement, not a question, naming it, e.g.: "Seconda wave chiusa in questa sessione: prima della prossima la sessione va compattata — lo stato è su disco, non si perde nulla." The user presses `/compact` because the tool needs a human keystroke, not because their opinion was being asked. Do not launch another wave in the same session before that happens.
- Report in ≤ 15 lines: launched / merged (or approved, awaiting the user in draft mode) / needs work / blocked, PR links, BUDGET/STALL lines, open questions from agent reports. Then stop — the next wave is a new `/run-wave`, when the user says "vai" (in draft mode, after the user has merged).
