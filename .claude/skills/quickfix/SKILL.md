## Quickfix — the fast lane for small changes

For a bug, a copy change, a small UI fix or a chore that fits in one PR and needs no design document. Runs in the main session; spawns only `developer` and `reviewer`. **Never** run business-analyst, tech-architect or implementation-planner from here.

Arguments: a plain-language description of the change: `$ARGUMENTS`

### 1. Sanity
`cat .pocket-it.json 2>/dev/null` (defaults if missing). `git status --short | head` — if the working tree is dirty on tracked files, note it in the report and continue: the developer works in its own worktree off the base branch, so the dirty files never reach it; nothing here is a reason to stop the launch.

If the request is clearly not small (new screens + new tables + new endpoints, or "add a feature that…"), say so in one line and offer `/intake` → pipeline instead. Do not stretch the quickfix lane.

### 2. Write the task file (the whole spec — a developer sees nothing else)
ID: `QF-{n}` where n = 1 + the highest existing `QF-` number in `tasks/` (start at 1). File `tasks/QF-{n}-{slug}.md`:

```markdown
# QF-{n} — {imperative title}

**Status**: Todo
**Label**: Backend | Frontend | DevOps   ← infer from the description
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: XS | S | M
**Budget**: 60 | 120 | 200   ← turns from the estimate; custom (and say why in Notes) for work that cannot be split, e.g. "run the suite, fix the reds"
**Risk**: low | high   ← high if it touches auth, money, migrations, deletion
**Depends on**: none
**Wave**: 1
**Files**: {the files you expect it to touch — look them up with grep/ls now, do not guess}
**TAD**: {PROJECT §… if a TAD exists, else "none — follow existing conventions"}
**Contract**: none
**Branch**: 
**PR**: 

## Goal
{the user's request, rephrased precisely, 2–3 sentences; include the current wrong behaviour and the expected one}

## Acceptance criteria
- [ ] AC1 — Given …, when …, then …
- [ ] AC2 — Given {the regression to avoid}, when …, then {still works}

## Tests expected
{one unit/component test per criterion; "Integration/E2E: not needed"}

## Notes
{where the bug lives if you found it, related files, anything the developer would otherwise hunt for}
```

Spend one or two `grep`/`ls` calls to fill **Files** and **Notes** with real paths. Then commit the task file:

```bash
git add tasks/QF-{n}-*.md && git commit -q -m "task: QF-{n} {title}" && POCKET_IT_ORCHESTRATOR_PUSH=1 git push -q
```

(Committed so a worktree-isolated developer can see it. The prefix is the hook's authorized form for a push to the base branch — see `/quickfix` §4.)

### 3. Launch
One Agent call: `subagent_type: developer`, `isolation: worktree` (only when the session cwd is this project's repo — otherwise create the worktree with `WT=$(bash ~/.claude/agents/pocket-it/bin/worktree.sh <project-path> task/QF-{n}-{slug})`, omit `isolation` and add `Worktree: $WT` to the prompt), `model: opus` only if Risk is high, prompt:

```
Issue: QF-{n} — {title}
Label: {label}
```

When it reports, one Agent call: `subagent_type: reviewer`, prompt `Tasks: QF-{n}` plus `Draft: yes` when config `automerge` is `false` or the user's request contains `draft`.

### 4. Close
- APPROVED: merge it — `POCKET_IT_USER_MERGE=1 gh pr merge {m} --squash --delete-branch` (the hook's authorised form; the prefix is the audit trail that the merge is covered by the `automerge: true` default). Skip the merge only when config `automerge` is `false` or the user's request contains `draft`: then report the PR as ready for the user to merge. After a merge, `git pull --ff-only` the base branch and make sure `tasks/QF-{n}-*.md` says `**Status**: Done` (set it if the developer left it otherwise).
- NEEDS WORK: read the cause and its destination straight from the reviewer's Step 6 report line — `cause: {…} — fix at: {…}` — never from the PR comment or the diff. Apply the fix at the place the cause names, before relaunching:
  - **example-not-class** (the task or finding named one or two cases of a class, bypassed by a third case): rewrite the acceptance criterion in `tasks/QF-{n}-*.md` to enumerate the whole class, on the base branch, and paste the corrected criterion into the relaunch prompt directly.
  - **base-moved** (main changed while it waited; branch tests were green against the old state): the relaunch prompt says, as its first instruction, to merge/rebase onto the current base and rerun the scoped tests before touching anything else.
  - **verification-reintroduced** (a report or check written to prove something absent contains that same thing): the fix belongs in `shared/implementing-common.md`'s report-writing rules and in `reviewer.md`'s own check wording — name that as the destination, do not restate its content here.
  - **other: …**: apply the cause exactly where the reviewer's `fix at:` points.

  Log it: `bash ~/.claude/agents/pocket-it/bin/handoff.sh log "ROUND QF-{n} PR #{m} round {k} — cause: {cause} — fix at: {path}"` (`k` starting at 2 for the first NEEDS WORK) — the retro reads `ROUND` lines the same way it reads `BUDGET`/`STALL`.

  Then a developer round with `Branch: … ALREADY EXISTS` and `PR: {m}` plus the reviewer's findings verbatim, the cause, and the fix already applied or the instruction to apply it first. Then one more reviewer call with `Mode: delta`. Park the PR only when the analysis concludes its cause is outside what the pipeline can reach — never on a round count, and never because the same cause came back once already (that means the earlier fix landed in the wrong place, which is a new cause, not grounds to stop) — `gh pr comment {m} --body "⏸ parked — {reason}"`, `gh label create parked --color eab308 2>/dev/null || true; gh pr edit {m} --add-label parked`, leave the task `Needs Work`. Never merge a `needs-work` PR without that re-review, even for a one-command fix.
- Then `bash ~/.claude/agents/pocket-it/bin/tasks-index.sh`, `bash ~/.claude/agents/pocket-it/bin/handoff.sh log "QF-{n} PR #{m} {merged|approved, awaiting user merge|needs work} — {title}"`, commit the task file, the index and the handoff on the base branch, `POCKET_IT_ORCHESTRATOR_PUSH=1 git push` (the hook's authorized form for a push to the base branch, same audit-prefix shape as the merge above).
- Then `bash ~/.claude/agents/pocket-it/bin/cleanup-merged.sh`: removes the worktree and local branch of the merged PR (dirty, locked and unmerged ones are kept and listed). Report its summary line (`cleanup-merged: N worktrees removed, … freed X MB`).
- Report: PR URL, review outcome, merged or awaiting the user (draft). If a NEEDS WORK round happened, add `Decided on its own: {cause found, where the fix went}` — the owner sees it even though nothing was asked of them. Then what is next.
