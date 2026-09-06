## Run-wave — launch everything that is ready, review it once, stop

Runs in the main session. The decision of *what* to launch is made by a script, not by you; your job is to turn its output into Agent calls, wait, run one review, and report. Keep the session thin: no reading of task files, TADs or diffs here — that is the agents' work.

Arguments (optional): `$ARGUMENTS` — e.g. `dry-run`, or `only T-3.1.1, T-3.2.1`.

### 1. Pre-flight (zero tokens)
```bash
bash ~/.claude/agents/pocket-it/bin/doctor.sh && bash ~/.claude/agents/pocket-it/bin/next-wave.sh
```
Any `ERROR` from doctor → stop and show it; do not launch. `next-wave` prints one JSON line per ready task (`issue`, `label`, `agent`, `model`, `risk`, `files`). Zero ready and some `in progress` → say which are running and stop. Zero ready and zero in progress and not everything Done → show the blocked list; the user decides.

`dry-run` → print the launch plan and stop.

### 2. Launch — all ready tasks in ONE message
For every JSON line, one Agent call in the same message:
- `subagent_type`: the `agent` field (`developer` or `qa-engineer`)
- `model`: the `model` field (`opus` only for `risk: high`)
- `isolation`: `worktree`
- `run_in_background`: `true`
- `description`: `{issue} {label}`
- `prompt`: `Issue: {issue} — {title from tasks/}\nLabel: {label}` plus `Base: {epic branch}` when config `branching` is `epic`.

Then stop and wait for the task notifications. Do not poll, do not read files while waiting.

### 3. Collect
When all notifications are in: list per task the branch, PR and one-line outcome from each report. A task that stopped early (partial / maxTurns / blocker) is **resumed** with SendMessage to the same agent when the blocker is something you can answer from the reports; otherwise it is reported to the user, never relaunched from scratch.

### 4. Review — one reviewer for the wave
One Agent call: `subagent_type: reviewer`, prompt `Tasks: {all task IDs that opened a PR}`. Wait.

NEEDS WORK items → one developer each, in one message, background, prompt `Issue: {id} — {title}\nLabel: {label}\nBranch: {branch} ALREADY EXISTS\nPR: {n}` plus the reviewer's findings verbatim. Then one more reviewer call for those PRs only. At most two review rounds per wave; what is still red after that goes to the user.

### 5. Close the wave
- APPROVED PRs: merge only if config `automerge` is true (`POCKET_IT_USER_MERGE=1 gh pr merge {n} --squash --delete-branch`, the hook's authorised form); otherwise list them for the user.
- `bash ~/.claude/agents/pocket-it/bin/tasks-index.sh` and `bash ~/.claude/agents/pocket-it/bin/handoff.sh log "wave {n} closed — {approved}/{launched} approved, {needs-work} needs work"`, commit `tasks/` and `docs/` on the base branch, push.
- Report in ≤ 15 lines: launched / approved / needs work / blocked, PR links, open questions from agent reports. Then stop — the next wave is a new `/run-wave`, after the user has merged.
