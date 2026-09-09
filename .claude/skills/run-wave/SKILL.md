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
- `isolation`: `worktree`
- `run_in_background`: `true`
- `description`: `{issue} {label}`
- `prompt`: `Issue: {issue} — {title from tasks/}\nLabel: {label}` plus `Base: {epic branch}` when config `branching` is `epic`.

Then stop and wait for the task notifications. Do not poll, do not read files while waiting.

### 3. Collect
When all notifications are in: list per task the branch, PR and one-line outcome from each report. A task that stopped early (partial / maxTurns / blocker) is **resumed** with SendMessage to the same agent when the blocker is something you can answer from the reports; otherwise it is reported to the user, never relaunched from scratch.

### 4. Review — one reviewer for the wave
One Agent call: `subagent_type: reviewer`, prompt `Tasks: {all task IDs that opened a PR}` plus `Draft: yes` when config `automerge` is `false` or the user's request / `$ARGUMENTS` contain `draft`. Wait.

NEEDS WORK items → one developer each, in one message, background, prompt `Issue: {id} — {title}\nLabel: {label}\nBranch: {branch} ALREADY EXISTS\nPR: {n}` plus the reviewer's findings verbatim. Then one more reviewer call for those PRs only. At most two review rounds per wave; what is still red after that goes to the user.

### 5. Close the wave
- APPROVED PRs: merge them, one by one — `POCKET_IT_USER_MERGE=1 gh pr merge {n} --squash --delete-branch` (the hook's authorised form; the prefix is the audit trail that the merge is covered by the `automerge: true` default). Skip the merge only when config `automerge` is `false` or the user's request / `$ARGUMENTS` contain `draft`: then list the approved PRs for the user, who merges. Never open or merge the epic→main PR of a deployed project here — that is a deploy, done only on explicit instruction.
- `git pull --ff-only` the base branch, then `bash ~/.claude/agents/pocket-it/bin/tasks-index.sh` and `bash ~/.claude/agents/pocket-it/bin/handoff.sh log "wave {n} closed — {merged}/{launched} merged, {approved-draft} awaiting user merge, {needs-work} needs work"`, commit `tasks/` and `docs/` on the base branch, push.
- Then `bash ~/.claude/agents/pocket-it/bin/cleanup-merged.sh`: removes the worktrees and local branches of the merged PRs (dirty, locked and unmerged ones are kept and listed). Report its summary line (`cleanup-merged: N worktrees removed, … freed X MB`).
- **Learning hooks.** Read the wave's `BUDGET` and `STALL` lines from the handoff log (`grep -E "^- .*(BUDGET|STALL) " docs/SESSION_HANDOFF.md | head`) and list them in the report: they are the raw material of the retro. If `next-wave.sh` now reports everything Done (the board is complete), launch the retro **now**, before reporting: one Agent call `subagent_type: retro`, prompt `{epic id or "board completed {date}"}`, wait, and include its summary — nobody else will launch it once the session closes.
- **Session hygiene.** Count the `wave … closed` lines logged today by this session. After the **second** closed wave, end the report with: "Due wave in questa sessione: prima della prossima, `/compact` (o una sessione nuova) — lo stato è su disco, non si perde nulla." Do not launch a third wave in the same session without it.
- Report in ≤ 15 lines: launched / merged (or approved, awaiting the user in draft mode) / needs work / blocked, PR links, BUDGET/STALL lines, open questions from agent reports. Then stop — the next wave is a new `/run-wave`, when the user says "vai" (in draft mode, after the user has merged).
