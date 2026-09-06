# pocket-it — Agent Maintenance Guide

This file is for working on the agents themselves. The rules the *orchestrator* follows on a target project live in `~/.claude/CLAUDE.md`; the rules the *implementing agents* share live in `.claude/agents/shared/implementing-common.md`. Edit each thing in one place.

---

## The pipeline in one picture (v2, 2026-09-06)

```
/intake (main session, asks the user once) ─▶ BRIEF.md + .pocket-it.json
   └▶ business-analyst ─▶ BAD (stories with Given/When/Then, examples, non-goals)
        └▶ [ux-ui-designer ─▶ Design Spec]  (Production scope)
             └▶ tech-architect ─▶ PROJECT TAD once, then a DELTA per feature + best-practices/
                  └▶ implementation-planner ─▶ tasks/*.md · INDEX.md · DEPS.json (waves, contract-first, risk)
                       └▶ 👤 board gate (the one human review)
                            └▶ /run-wave ×N: doctor → next-wave → developers in worktrees (opus if risk high) → one reviewer (verify.sh first) → 👤 merge
                                 └▶ [qa-engineer only for justified QA tasks] ─▶ [documentation-agent] ─▶ retro
Small change? ─▶ /quickfix: task file → developer → reviewer. No documents.
```

Scripts do everything that does not need judgement: `doctor` (pre-flight), `next-wave` (what is ready), `verify` (lint/type/tests on a PR), `tasks-index`, `usage-report` (where the tokens went), `guard.sh` (hook).

---

## Agent format

```yaml
---
name: agent-name          # matches the filename
description: ...          # shown in the agent picker; used by the orchestrator to route
model: sonnet             # alias: sonnet / opus / haiku / fable / inherit
effort: high              # optional: low / medium / high / xhigh / max — overrides the session effort
maxTurns: 120             # hard cap on turns — every implementing agent has one; output comes back "partial" and is resumable
# NOT supported (verified 2026-09-06 on Claude Code 2.1.263): model_settings / thinking budget —
# extended thinking is inherited from the session; there is no per-agent setting.
tools: [Read, Write, ...]
---
```

`{{ARGUMENTS}}` appears once, near the top. Agents are native `subagent_type`s; the launchers in `.claude/skills/` forward `$ARGUMENTS`. Agents never call `AskUserQuestion` (it fails in a subagent): unknowns come from `.pocket-it.json` and `business-analysis/BRIEF.md`, are recorded as `[ASSUMPTION]`, and reach the user through the report.

---

## Roster

| File | Model | maxTurns | Role |
|---|---|---|---|
| `business-analyst.md` | Opus | — | BAD from BRIEF/description: stories with Given/When/Then criteria, examples table, non-goals. No questions |
| `ux-ui-designer.md` | Opus | — | (A) audits a static site, (B) static direction, (C) enterprise Design Spec → `design-specs/` |
| `tech-architect.md` | Opus | — | First feature: `PROJECT_TECH_ANALYSIS.md` (fixed numbering). Later features: `{NAME}_TECH_DELTA.md` with only the changed sections. Writes/updates `best-practices/` per tech group |
| `implementation-planner.md` | Sonnet | 80 | Board: self-contained task files (Files, TAD §, Contract, Risk, AC1…n as Given/When/Then, Non-goals), `INDEX.md`, `DEPS.json` with waves; contract-first tasks so backend and frontend run in the same wave; runs `doctor.sh`. No Linear |
| `developer.md` | Sonnet (Opus when `Risk: high`) | 120 | One task — **Backend, Frontend or DevOps** — with its unit tests, task branch, draft PR whose body maps AC→test |
| `qa-engineer.md` | Sonnet | 150 | Integration/E2E only for QA tasks the planner justified; files bug tasks |
| `reviewer.md` | Opus | 60 | `verify.sh` first (red = needs work), then diff vs criteria, contract, TAD, best practices; comments + labels; conflicts; CI routing to `developer` |
| `retro.md` | Opus | 60 | End of epic: repeated findings → best-practices rules (PR) + proposed template/heuristic lines for pocket-it |
| `documentation-agent.md` | Sonnet | 60 | Optional, on request: README, API reference, architecture overview |
| `mvp-builder.md` | Sonnet | — | Static site from a brief |
| `../legal-advisor.md` | Opus | — | Privacy/cookie/terms for client sites |

Removed in v2: `devops-engineer` (7 launches in two months vs 250 for developer) — its rulebook is the DevOps section of `developer.md`, `Label: DevOps`.

### Skills that are not launchers (run in the main session)

| Skill | What it does |
|---|---|
| `/intake` | The only place questions are asked. One `AskUserQuestion`, writes `.pocket-it.json` + `business-analysis/BRIEF.md`, commits, hands off to business-analyst |
| `/quickfix {sentence}` | Fast lane: writes and commits `tasks/QF-n-*.md` with real file paths and Given/When/Then criteria, launches developer (worktree) then reviewer. No documents |
| `/run-wave` | `doctor` → `next-wave` → all ready tasks in one message (worktree, background, opus if high risk) → one reviewer → at most two fix rounds → index + report. Next wave = next call |
| `/retro EPIC-n` | launcher for the retro agent |

### Scripts (`bin/`, zero tokens)

| Script | Use |
|---|---|
| `doctor.sh [--wave N]` | pre-flight: config valid and committed, task files complete and committed, DEPS.json consistent, no shared files in a wave, TAD numbering, hygiene. Exit 1 on errors |
| `next-wave.sh` | prints one JSON line per launchable task (deps Done, no file overlap with tasks launched in the same call, model by risk) + a blocked list |
| `verify.sh <PR|branch>` | lint, type-check, affected tests on the PR branch in a throwaway worktree, ≤ 40 lines. The reviewer runs it before reading |
| `tasks-index.sh` | regenerates `tasks/INDEX.md` |
| `usage-report.py [--days N] [project]` | token/cost report from the transcripts: sessions, subagents by type, runaways, failure signatures. Run it weekly |
| `.claude/hooks/guard.sh` | PreToolUse hook: blocks `gh pr merge` (unless `POCKET_IT_USER_MERGE=1` on explicit user instruction), pushes to main, `pkill/killall`, `APP_STATUS → prod`, `sleep N &&`. Tests: `guard.test.sh`, `guard.heredoc.test.sh` |

### Shared files

- `shared/design-compass.md` — visual language for `mvp-builder` and `ux-ui-designer` (read at runtime).
- `shared/implementing-common.md` — config, board helpers, read discipline (task + cited TAD sections + contract, never the IPD), test policy, shared-machine rules, branch/PR flow, stop conditions. Read once by developer, qa-engineer, reviewer.
- **Worktree agents see only committed files.** `.pocket-it.json`, the documents and `tasks/` must be committed on the base branch before launching; `doctor.sh` checks it.

### Accessibility floor — WCAG 2.1 AA (mandatory)

Defined once in the compass; the Design Spec adds depth; TAD §7.6 never says `N/A`; `developer` implements it and adds an axe check per component; `reviewer` gates on it.

---

## Per-project config — `.pocket-it.json`

Written by `/intake` (or copied from `templates/pocket-it.json`). Every agent reads it instead of asking.

| Key | Default | Used by |
|---|---|---|
| `scope` | `medium` | business-analyst, tech-architect, planner (output depth) |
| `automerge` | `false` | run-wave and implementing agents (`Auto-merge` label, orchestrator merge) |
| `pipeline` | `false` | tech-architect (§9.3 wording), developer DevOps (may create workflows), reviewer (CI gate) |
| `baseBranch` / `branching` | `main` / `flat` | branch base and PR target; `epic` = orchestrator passes `Base:` |
| `testCommand` | auto | affected-tests entry point |
| `tests` | `unit: required`, `integration: on-demand`, `e2e: on-demand` | test policy — planner creates QA tasks only with a one-line justification; `off` / `on` override |
| `ticketPrefix` / `teamSize` | `T` / `1` | ids, planner waves |

---

## Output folders and contracts

| Folder | Created by | Read by |
|---|---|---|
| `business-analysis/BRIEF.md` | `/intake` | business-analyst (facts, not assumptions) |
| `business-analysis/` | business-analyst | ux-ui-designer, tech-architect |
| `design-specs/` | ux-ui-designer (C) | tech-architect (§7), developer (Frontend) |
| `tech-analysis/PROJECT_TECH_ANALYSIS.md` | tech-architect, once | everyone — **by section** (`awk '/^## 5\. /,/^## 6\. /'`) |
| `tech-analysis/{NAME}_TECH_DELTA.md` | tech-architect, per feature | planner, developer — overrides the project TAD for the cited sections |
| `tech-analysis/best-practices/` | tech-architect (+ retro) | developer, qa, reviewer — one file per tech group, updated in place |
| `implementation-plans/{NAME}_DEPS.json` | planner | `next-wave.sh`, `doctor.sh` |
| `tasks/` | planner, `/quickfix`, qa bug tasks | developer, qa, reviewer, scripts |
| `src/contracts/…` (or the project's equivalent) | the story's Contract task | backend and frontend tasks of that story, reviewer |

### Task file contract

`tasks/{ID}-{slug}.md`, header `**Key**: value` lines: Status, Label, Epic, Story, Priority, Estimate, **Risk**, Depends on, Wave, Files, TAD, **Contract**, Branch, PR; then `## Goal`, `## Acceptance criteria` (AC1…n, Given/When/Then), `## Non-goals`, `## Tests expected`, `## Notes`. Statuses: `Todo | In Progress | Done | Needs Work`. Helpers tolerate the older `**Key:** value` form. A developer must be able to implement from the task file plus the cited sections alone.

### TAD section map (contract — never renumber)

| § | Content |
|---|---|
| 3 / 3.1 | Stack matrix / DB config |
| 4.3 | Schema definitions |
| 5.1 / 5.2 / 5.3 | API style + auth / endpoints / rate limits |
| 6.1 / 6.2 | Auth secrets / OWASP controls |
| 7.1–7.6 | Frontend: structure, state, routing, CSS + component lib, perf budget, rendering + a11y |
| 8.1–8.4 | Backend: structure, patterns, jobs, caching |
| 9.1–9.6 | Infra: diagram, env matrix, CI/CD (`APP_STATUS`-gated, no deploy), containers + env vars, observability, DR |
| 10.1 | Scaling |
| 11.1–11.3 | Testing pyramid (unit/component required; integration/E2E with justification or N/A), environment, gates |

Skipped sections keep their heading with a one-line `N/A`. A delta uses the same numbers and marks untouched sections `unchanged`.

---

## Conventions

| Convention | Value |
|---|---|
| Task branch | `task/{id-lower}-{slug}` off `baseBranch` (or `epic/...` when `branching: epic`) |
| PRs | always draft, against the base; approval = `gh pr ready` + comment + `approved` label; rejection = comment + `needs-work` + task `Needs Work` |
| Merge | user-triggered (hook-enforced); the orchestrator merges only with `automerge: true` or an explicit instruction, using the `POCKET_IT_USER_MERGE=1` prefix |
| Hosted CI | opt-in via `pipeline: true`; `APP_STATUS` starts `dev`; only a human flips it to `prod` |
| History log | `docs/SESSION_HANDOFF.md`, opt-in; agents prepend, reviewer updates |
| Cost rules | task file + cited sections only; read once; capped output; `maxTurns`; one reviewer per wave; resume partial agents, never relaunch; one session per epic on a standard-context model |

---

## Adding an agent / skill

1. `.claude/agents/{name}.md` with the frontmatter above; implementing agents read `shared/implementing-common.md` at Step 0.
2. Roster row here; README if user-facing.
3. Launcher `.claude/skills/{name}/SKILL.md` (`subagent_type: {name}`, forward `$ARGUMENTS`). A skill that must talk to the user is written as main-session instructions instead (see `intake`, `quickfix`, `run-wave`).
4. If it reads the TAD, cite section numbers and extract by section.
5. Run `bash .claude/hooks/guard.test.sh` if you touched the hook.
