# pocket-it — Agent Maintenance Guide

This file is for working on the agents themselves. If you are using the agents in a target project, see `CLAUDE.template.md` — copy that file to `~/.claude/CLAUDE.md` instead.

---

## Agent format

Each agent is a Markdown file in `.claude/agents/` with a YAML frontmatter block:

```yaml
---
name: agent-name          # matches the filename without .md
description: ...          # shown in the agent picker; also used by the orchestrator
model: claude-sonnet-4-6  # or claude-opus-4-7 / claude-haiku-4-5-20251001
model_settings:
  thinking:
    type: enabled
    budget_tokens: 5000   # omit entirely if thinking is not needed
tools:
  - Read
  - Write
  - ...
---
```

The body is plain Markdown. Use `{{ARGUMENTS}}` once, near the top, to receive whatever the caller passed.

---

## Agent roster

| File | Model | Role |
|------|-------|------|
| `business-analyst.md` | Sonnet | Writes BAD from a feature description |
| `ux-designer.md` | Sonnet | Writes Design Spec from the BAD — colors, typography, motion, screen wireframes, components |
| `tech-architect.md` | Opus | Writes TAD from the BAD + Design Spec |
| `implementation-planner.md` | Sonnet | Writes IPD, pushes Linear issues, writes deps JSON |
| `scaffold.md` | Sonnet | Initialises project skeleton from the TAD |
| `developer.md` | Sonnet | Implements one Backend or Frontend issue (branches on `Label:` in arguments), opens PR |
| `devops-engineer.md` | Sonnet | Implements one DevOps issue, opens PR |
| `qa-engineer.md` | Sonnet | Implements full test suite, commits to main |
| `reviewer.md` | Sonnet | Checks acceptance criteria + TAD constraints against PR diffs |
| `documentation-agent.md` | Sonnet | Writes README, API reference, architecture overview |
| `mvp-builder.md` | Sonnet | Builds a full-stack MVP from a plain-English description; no TAD/Linear required |
| `css-animator.md` | Sonnet | CSS animation specialist — matches requests to Animate.css catalogue or searches the web for custom keyframes |

Model rationale: all agents run on Sonnet (Pro subscription — optimising for token budget). Upgrade individual agents to Opus if quality gaps appear in practice.

---

## Output folders

| Folder | Created by | Read by |
|--------|-----------|---------|
| `business-analysis/` | `business-analyst` | `tech-architect`, `ux-designer` |
| `design-specs/` | `ux-designer` | `tech-architect`, `developer` |
| `tech-analysis/` | `tech-architect` | all developer agents |
| `best-practices/` | `tech-architect` (Step 7) | `developer`, `devops-engineer`, `qa-engineer` |
| `implementation-plans/` | `implementation-planner` | all developer agents |

Developer agents check for `best-practices/` at Step 2. If present they read the relevant files instead of web-searching; if absent they fall back to web searches. This makes them fully standalone while saving tokens in the full pipeline.

---

## TAD section map

Agents reference TAD sections by number. These are fixed — if the tech-architect template changes section order, all downstream agents break.

| Section | Content |
|---------|---------|
| 3 | Stack Matrix (language, framework, package manager, runtime version) |
| 3.1 | Database config (connection strings, pool settings) |
| 4 | Data Architecture (ERD, schema, data flow) — NOT folder structure |
| 5.1 | API style (REST / GraphQL / tRPC) |
| 5.2 | API contract (endpoint shapes, request/response schemas) |
| 6.1 | Auth secrets (JWT_SECRET, token TTLs) |
| 6.2 | Security Controls Checklist (OWASP table) — NOT env vars |
| 7.1 | Frontend Application Structure (directory tree) |
| 7.2 | State management + data fetching |
| 7.3 | Routing strategy |
| 7.4 | CSS approach + component library |
| 7.5 | Performance budget |
| 7.6 | Rendering strategy (SSR/SSG/ISR/CSR) + accessibility target |
| 8.1 | Backend Application Layer Structure (directory tree) |
| 9.4 | Container configuration + runtime environment variables |
| 11.1 | Testing Pyramid (unit/component/integration/E2E tools) |
| 11.2 | Test environment strategy (isolation, factories, mocking) |
| 11.3 | Quality gates + coverage targets |

---

## Arguments protocol

Pass arguments to skills as plain text when invoking them. Recommended formats:

**`/developer`**
```
Issue: {issue_id} — {issue_title}
Label: Backend | Frontend
Branch: {branch-name}
```

**`/devops-engineer`**
```
Issue: {issue_id} — {issue_title}
Branch: {branch-name}
```

**`/qa-engineer`** — pass a project description or `"all non-Done QA tasks"`

**`/reviewer`** — pass PR numbers: `Review the following open PRs: 12, 13`

**`/documentation-agent`** — pass a project slug or leave empty to auto-detect

---

## Adding a new agent

1. Create `.claude/agents/{name}.md` with the frontmatter above.
2. Add it to the roster table in this file.
3. Create a matching skill in `.claude/skills/{name}/SKILL.md` so it is user-invocable.
4. If it reads the TAD, verify it references the correct section numbers from the table above.
5. Update `CLAUDE.template.md` if the new agent affects the user-facing pipeline flow.

## Adding a new skill

Skills are user-invocable launchers (`/skill-name`) that spawn an agent. Each skill lives in its own directory:

```
.claude/skills/{name}/SKILL.md
```

The `SKILL.md` content follows this pattern:

```markdown
## Launcher

Your only job is to spawn an isolated agent. Follow these steps exactly:

1. Use the Read tool to read `~/.claude/agents/{name}.md`
2. In the content you just read, replace every occurrence of `{{ARGUMENTS}}` with this exact value: $ARGUMENTS
3. Call the Agent tool with:
   - `subagent_type`: `general-purpose`
   - `model`: `sonnet` or `opus`
   - `description`: `{Human-readable description}`
   - `run_in_background`: `false`
   - `prompt`: the modified content from step 2

Do not do any research, analysis, or writing yourself. Everything happens inside the spawned agent.
```

Note: `.claude/commands/` is the legacy format — it still works but `.claude/skills/` is the current recommended format.
