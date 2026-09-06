## Quickfix — the fast lane for small changes

For a bug, a copy change, a small UI fix or a chore that fits in one PR and needs no design document. Runs in the main session; spawns only `developer` and `reviewer`. **Never** run business-analyst, tech-architect or implementation-planner from here.

Arguments: a plain-language description of the change: `$ARGUMENTS`

### 1. Sanity
`cat .pocket-it.json 2>/dev/null` (defaults if missing). `git status --short | head` — if the working tree is dirty on tracked files, say so and stop: the developer branches off the base branch and nothing is lost, but the user should know.

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
**Estimate**: XS | S
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
git add tasks/QF-{n}-*.md && git commit -q -m "task: QF-{n} {title}" && git push -q
```

(Committed so a worktree-isolated developer can see it.)

### 3. Launch
One Agent call: `subagent_type: developer`, `isolation: worktree`, `model: opus` only if Risk is high, prompt:

```
Issue: QF-{n} — {title}
Label: {label}
```

When it reports, one Agent call: `subagent_type: reviewer`, prompt `Tasks: QF-{n}`.

### 4. Close
Report: PR URL, review outcome, what to do next (merge if approved; a second developer round with `Branch: … ALREADY EXISTS` and `PR: n` if NEEDS WORK). Then `bash ~/.claude/agents/pocket-it/bin/tasks-index.sh` and commit the index if the project keeps one.
