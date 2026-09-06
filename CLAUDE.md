# pocket-it — Agent Maintenance Guide

This file is for working on the agents themselves. The rules the *orchestrator* follows when running the pipeline on a target project live in `~/.claude/CLAUDE.md`; the rules the *implementing agents* share live in `.claude/agents/shared/implementing-common.md`. Edit each thing in one place.

---

## Agent format

Each agent is a Markdown file in `.claude/agents/` with YAML frontmatter:

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

The body is Markdown. `{{ARGUMENTS}}` appears once, near the top. Agents are invoked as native `subagent_type`s (the skill launchers in `.claude/skills/` only forward `$ARGUMENTS` to them). Agents never call `AskUserQuestion`: as subagents the call fails, so every agent resolves unknowns from `.pocket-it.json`, records `[ASSUMPTION]`s and reports open questions for the orchestrator to relay.

---

## Agent roster

| File | Model | maxTurns | Role |
|---|---|---|---|
| `business-analyst.md` | Opus | — | BAD from a feature description. No questions; assumptions listed in §10 |
| `ux-ui-designer.md` | Opus | — | (A) audits a static site, (B) static design direction, (C) enterprise Design Spec from a BAD → `design-specs/` |
| `tech-architect.md` | Opus | — | TAD from BAD (+ Design Spec). Fixed section numbering. Writes/updates `best-practices/` per tech group |
| `implementation-planner.md` | Sonnet | 80 | **Board**: one self-contained task file per task in `tasks/`, `tasks/INDEX.md`, `DEPS.json` with waves, short IPD. No Linear |
| `developer.md` | Sonnet | 120 | One task + its unit tests, task branch, draft PR |
| `devops-engineer.md` | Sonnet | 100 | One infra task; CI only if `pipeline: true` |
| `qa-engineer.md` | Sonnet | 150 | Integration, E2E, a11y tests for QA tasks; files bug tasks |
| `reviewer.md` | **Opus** | 60 | Diff review vs task criteria, TAD, best practices; conflicts; CI routing; comments + labels (no GitHub approvals — own-PR restriction) |
| `documentation-agent.md` | Sonnet | 60 | README, API reference, architecture overview; draft PR |
| `mvp-builder.md` | Sonnet | — | Static site from a brief → `~/Desktop/clients/{slug}/` |
| `../legal-advisor.md` (Desktop/agents root) | Opus | — | Privacy/cookie/terms for client sites |

Model rationale: Sonnet for producers of code, Opus where judgement dominates — architecture, design, and the **reviewer**, which is the only quality gate when hosted CI is off (the default).

### Shared files

- `shared/design-compass.md` — visual language for `mvp-builder` and `ux-ui-designer` (read at runtime; never inline).
- `shared/implementing-common.md` — config, board helpers, read discipline, test scoping, shared-machine rules, branch/PR flow, stop conditions for the four implementing agents (read at runtime; never inline). Anything that used to be a 140-line block copied into three agents lives here once.
- `bin/tasks-index.sh` — regenerates `tasks/INDEX.md` from the task files (tolerates both header forms; works from a worktree). Nobody edits INDEX.md by hand.
- **Worktree agents see only committed files.** `isolation: worktree` checks out HEAD: `.pocket-it.json`, the planning documents and the `tasks/` board must be committed on the base branch before developer/devops/qa are launched, or they report a missing task file and stop.
- `.claude/hooks/guard.sh` — PreToolUse hook registered in `~/.claude/settings.json`: blocks `gh pr merge`, pushes to main, `pkill/killall`, `APP_STATUS → prod`, `sleep N &&` chains. Hard rules live here, not in prompts.
- `templates/pocket-it.json` — per-project config template.

### Accessibility floor — WCAG 2.1 AA (mandatory)

Defined once in the compass; the Design Spec adds depth; TAD §7.6 never says `N/A`; `developer` implements it; `qa-engineer` tests it (axe + keyboard); `reviewer` gates on it. No per-project switch.

---

## Per-project config — `.pocket-it.json`

Copy `templates/pocket-it.json` to the target repo root. Every agent reads it instead of asking.

| Key | Default | Used by |
|---|---|---|
| `scope` | `medium` | business-analyst, tech-architect, implementation-planner (output depth) |
| `automerge` | `false` | implementing agents (apply `Auto-merge` label) |
| `pipeline` | `false` | tech-architect (§9.3 wording), devops-engineer (may create workflows), reviewer (CI gate) |
| `baseBranch` | `main` | branch base and PR target |
| `branching` | `flat` | `epic` = orchestrator passes `Base: epic/...` to each task |
| `testCommand` | auto | affected-tests entry point |
| `tests` | `unit: required`, `integration: on-demand`, `e2e: on-demand` | test policy (see below) |
| `ticketPrefix` | `T` | bug task ids (`T-BUG-n`) |
| `teamSize` | `1` | planner waves, TAD delivery context |

The old `/tmp/{repo}-automerge` and `/tmp/{repo}-pipeline` files are gone: they were lost on reboot and blocked under worktree isolation.

---

## Output folders

| Folder | Created by | Read by |
|---|---|---|
| `business-analysis/` | business-analyst | ux-ui-designer, tech-architect |
| `design-specs/` | ux-ui-designer (C) | tech-architect (§7), developer (Frontend) |
| `tech-analysis/` | tech-architect | all — **by section**, never whole (`awk '/^## 5\. /,/^## 6\. /'`) |
| `tech-analysis/best-practices/` | tech-architect | developer, devops, qa, reviewer — one file per tech group, updated in place |
| `implementation-plans/` | implementation-planner | orchestrator (`DEPS.json` waves); agents do **not** read the IPD |
| `tasks/` | implementation-planner (+ qa bug tasks) | developer, devops, qa, reviewer, orchestrator |

### Task file contract

`tasks/T-{e}.{s}.{t}-{slug}.md`, header `**Key**: value` lines in this order: Status, Label, Epic, Story, Priority, Estimate, Depends on, Wave, Files, TAD, Branch, PR; then `## Goal`, `## Acceptance criteria`, `## Tests expected`, `## Notes`. Statuses: `Todo | In Progress | Done | Needs Work`. The agents' sed helpers tolerate the older `**Key:** value` form found in existing projects. A developer must be able to implement from the task file plus the cited TAD sections alone — if not, that is a planner defect to report.

---

## TAD section map (contract — never renumber)

| § | Content |
|---|---|
| 3 / 3.1 | Stack matrix / DB config |
| 4.3 | Schema definitions |
| 5.1 / 5.2 / 5.3 | API style + auth / endpoints / rate limits |
| 6.1 / 6.2 | Auth secrets / OWASP controls |
| 7.1–7.6 | Frontend: structure, state, routing, CSS + component lib (Design Spec is authoritative), perf budget, rendering + a11y (never N/A) |
| 8.1–8.4 | Backend: structure, patterns, jobs, caching |
| 9.1–9.6 | Infra: diagram, env matrix, CI/CD (`APP_STATUS`-gated, no deploy), containers + env vars, observability, DR |
| 10.1 | Scaling |
| 11.1–11.3 | Testing pyramid, environment strategy, quality gates |

Skipped sections keep their heading with a one-line `N/A`.

---

## Pipeline conventions

| Convention | Value |
|---|---|
| Task branch | `task/{id-lower}-{slug}` off `baseBranch` (or off `epic/...` when `branching: epic`) |
| QA branch | `task/{id-lower}-qa-{slug}` |
| Docs branch | `docs/{slug}-{YYYY-MM-DD}` |
| PRs | always **draft**, always against the base; approval = `gh pr ready` + comment + `approved` label; rejection = comment + `needs-work` label + task status `Needs Work` |
| Merge | user-triggered only (hook-enforced). `automerge: true` adds the label; the orchestrator merges approved labelled PRs |
| Hosted CI | opt-in via `pipeline: true`; `APP_STATUS` starts `dev`; only a human flips it to `prod` (hook-enforced) |
| History log | `docs/SESSION_HANDOFF.md`, opt-in per project; implementing agents prepend, reviewer updates, orchestrator finalises |

### Cost rules (from the 2026-09 audit)

- Agents read the task file + cited TAD sections, never the IPD or the whole TAD. Source files are read once; edits are not followed by full re-reads. Command output is capped.
- **Test policy (default since 2026-09-06):** unit and component tests are required and ship with each task, written well (scenario-named, edge and error paths, behaviour not implementation, axe on components). Integration and E2E are **on-demand**: the planner creates a QA task only with a one-line justification (money, auth, data integrity, shared contract, the 1–3 journeys that cannot ship broken); `tech-architect` §11.1 names those flows or writes N/A; `qa-engineer` runs only when such tasks exist. Override per project via `tests` in `.pocket-it.json` (`off` / `on-demand` / `on`). Scoped test runs only; full suite at most once before the PR.
- `maxTurns` on every implementing agent; stop conditions in the shared rules — a clean partial report beats a runaway.
- Reviewer is launched once per wave/batch with `PRs:` or `Tasks:` listed, not once per PR; it never guesses PR numbers.

---

## Adding an agent / skill

1. `.claude/agents/{name}.md` with the frontmatter above; implementing agents read `shared/implementing-common.md` at Step 0.
2. Roster row here; README if user-facing.
3. `.claude/skills/{name}/SKILL.md`:

```markdown
## Launcher

Spawn the native agent. Call the Agent tool immediately with:
- `subagent_type`: `{name}`
- `description`: `{short}`
- `run_in_background`: `false`
- `prompt`: exactly the text below

---

$ARGUMENTS
```

4. If it reads the TAD, cite section numbers from the map and extract by section.
