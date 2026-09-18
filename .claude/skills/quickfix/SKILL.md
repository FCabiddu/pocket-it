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
**Budget**: 45 min | 90 min | 150 min   ← wall clock, from the estimate; the unit goes **in the value**, never only in this comment; custom (and say why in Notes) for work that cannot be split, e.g. "run the suite, fix the reds"
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
One Agent call: `subagent_type: developer`, `isolation: worktree` (only when the session cwd is this project's repo — otherwise create the worktree with `WT=$(bash ~/.claude/agents/pocket-it/bin/worktree.sh <project-path> task/QF-{n}-{slug})`, omit `isolation` and add `Worktree: $WT` to the prompt), `model`: your explicit choice for this launch (see "Model choice" below), motivated in one line in the prompt — `Risk` alone is not the decision, prompt:

```
Issue: QF-{n} — {title}
Label: {label}
```

**Model choice**: yours to make at every launch, not `Risk` alone. Bigger model (opus): irreversible or destructive work, security or permission boundaries, open-ended reasoning (diagnosis, design, root-cause analysis, and their review), a wide surface to keep coherent. Smaller model (sonnet): mechanical, well-specified work, or prose only. The `model` in an agent's frontmatter stays as the floor — no subagent has a default model, so one launched without an explicit model inherits the session's, the most expensive; never omit it. Never change the model as a reaction to a failed round: find the cause first (Step 4), and raise the model only if the analysis itself names the model as the cause.

When it reports, one Agent call: `subagent_type: reviewer`, prompt `Tasks: QF-{n}` plus `Draft: yes` when config `automerge` is `false` or the user's request contains `draft`.

**Retro trigger — after every review, first round and any delta re-review alike.** `bash ~/.claude/agents/pocket-it/bin/retro-due.sh`. Exit 0 (`retro-due: nothing`) → continue. Exit 2 is a script or environment error, not a "no signals" answer: fix it, do not treat it as nothing. Exit 10 (`RETRO DUE: …`) → first `gh pr list --state open --json headRefName --jq '.[].headRefName' | grep -q '^retro/'`: a match means a retro triggered earlier on this same QF is already open and unmerged — do not launch a second one, note it and move on. No match → launch the `retro` agent right now, in background — `subagent_type: retro`, `run_in_background: true`, prompt `Signals:` followed by the script's signal lines verbatim (the exact input `retro.md` declares for this trigger) — never asking, never waiting for the epic to close.

### 4. Close
- APPROVED: merge it — `POCKET_IT_USER_MERGE=1 gh pr merge {m} --squash --delete-branch` (the hook's authorised form; the prefix is the audit trail that the merge is covered by the `automerge: true` default). Skip the merge only when config `automerge` is `false` or the user's request contains `draft`: then report the PR as ready for the user to merge. After a merge, `git pull --ff-only` the base branch and make sure `tasks/QF-{n}-*.md` says `**Status**: Done` (set it if the developer left it otherwise).
- NEEDS WORK: read the cause and its destination straight from the reviewer's Step 6 report line — `cause: {…} — fix at: {…}` — never from the PR comment or the diff. Apply the fix at the place the cause names, before relaunching:
  - **example-not-class** (the task or finding named one or two cases of a class, bypassed by a third case): rewrite the acceptance criterion in `tasks/QF-{n}-*.md` to enumerate the whole class, on the base branch, and paste the corrected criterion into the relaunch prompt directly.
  - **base-moved** (main changed while it waited; branch tests were green against the old state): the relaunch prompt says, as its first instruction, to merge/rebase onto the current base and rerun the scoped tests before touching anything else.
  - **verification-reintroduced** (a report or check written to prove something absent contains that same thing): the fix belongs in `shared/implementing-common.md`'s report-writing rules and in `reviewer.md`'s own check wording — name that as the destination, do not restate its content here.
  - **other: …**: apply the cause exactly where the reviewer's `fix at:` points.

  **When a cause's fix lives in a pocket-it file** (`shared/implementing-common.md`, an agent template, this skill, `verify.sh`, a hook) rather than in the project: that correction goes through a `/quickfix` on pocket-it (mechanism only, no project data) — never an edit made here directly. Name it in the closing report.

  Then a developer round with `Branch: … ALREADY EXISTS` and `PR: {m}` plus the reviewer's findings verbatim, the cause, and the fix already applied or the instruction to apply it first. This prompt — and any later resume prompt to the same PR through more than one round — carries every finding still open across **all** rounds so far, not only this round's, and never narrows scope with language like "no other changes" or "only fix the above" (same rule as `run-wave` Step 4, same cause behind it); the report it asks for follows `implementing-common.md` §9 "Resume report format", cited here rather than restated. Every launch and resume prompt here — the first one in Step 3 included — follows `run-wave` Step 4 "Writing a launch or resume prompt" (invariants as damage, no outcome that breaks an invariant, one home for terms split across PRs, a threat model for a guard) and its fresh-launch rule from a PR's third developer round, cited by name rather than restated. Then one more reviewer call with `Mode: delta` — and the same retro trigger above, again, once it reports. Park the PR only when the analysis concludes its cause is outside what the pipeline can reach — never on a round count, and never because the same cause came back once already (that means the earlier fix landed in the wrong place, which is a new cause, not grounds to stop) — `gh pr comment {m} --body "⏸ parked — {reason}"`, `gh label create parked --color eab308 2>/dev/null || true; gh pr edit {m} --add-label parked`, leave the task `Needs Work`. Never merge a `needs-work` PR without that re-review, even for a one-command fix.
- Then `bash ~/.claude/agents/pocket-it/bin/tasks-index.sh`, `bash ~/.claude/agents/pocket-it/bin/handoff.sh log "QF-{n} PR #{m} {merged|approved, awaiting user merge|needs-work} — {title}"` — `needs-work` hyphenated (the label's own spelling), never the reviewer's two-word "needs work": `bin/retro-due.sh` (PI-35) anchors its needs-work signal on that exact two-word form immediately after `PR #<n>`, and this closing line would otherwise double it into a second round on top of the reviewer's own — commit the task file, the index and the handoff fragment (`git add docs/handoff`) on the base branch, `POCKET_IT_ORCHESTRATOR_PUSH=1 git push` (the hook's authorized form for a push to the base branch, same audit-prefix shape as the merge above).
- Then `bash ~/.claude/agents/pocket-it/bin/cleanup-merged.sh`: removes the worktree and local branch of the merged PR (dirty, locked and unmerged ones are kept and listed). Report its summary line (`cleanup-merged: N worktrees removed, … freed X MB`). The delete-branch outcome of the merge command above is not reliable (it can silently leave the local or the remote branch alive depending on where it ran): this step is what actually closes the branch, local and remote, without depending on `gh`'s exit code.
- **Then reinstall the shared checkout, if the merged PR touched a lockfile.** The merge changes what the repository declares; nothing changes what is *installed* in this checkout, and every later verification borrows its `node_modules` from here — so every later run measures the previous versions and stays green about code nobody ships. `bash ~/.claude/agents/pocket-it/bin/install-drift.sh reinstall . --except {the merged branch}` — it reinstalls only when the installed tree really disagrees with the lockfile, and it runs the lockfile's own frozen install (`npm ci`, or the pnpm/yarn/bun equivalent). **This bullet is AFTER `cleanup-merged.sh` on purpose, and `--except` names the merged branch for the same reason**: while that PR's own worktree is still registered here, an earlier reinstall would spend every run deferring on the very branch it was called to finish. Add `--running "{what you launched, in your words}"` whenever a developer, reviewer or QA agent you started is still working against this checkout: **no reinstall while anything is running against it** — it would swap the installed code under a run in progress and corrupt what that run measured (the script also looks for live processes in this checkout and its worktrees, and defers on its own when it finds any, or when it cannot read what is running). Put its last line in the closing report (`REINSTALLED …`, `SKIP …`, `DEFERRED …`, `note …`). Exit 4 is a deferral, not a failure: it has already recorded it with `handoff.sh log` — unless it printed `NOT LOGGED`, and then the deferral lives only in your report, so carry it there yourself — and the same command is run once those agents report. Exit 3 means it cannot tell (a package manager it does not drift-check): re-run it with `--since {the base commit before the merge}` so the merged diff decides.
- Report: PR URL, review outcome, merged or awaiting the user (draft). If a NEEDS WORK round happened, add `Decided on its own: {cause found, where the fix went}` — the owner sees it even though nothing was asked of them. Then what is next.
