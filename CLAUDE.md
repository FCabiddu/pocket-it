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
| `tech-architect.md` | Opus | Writes TAD from the BAD |
| `implementation-planner.md` | Sonnet | Writes IPD, pushes Linear issues, writes deps JSON |
| `scaffold.md` | Sonnet | Initialises project skeleton from the TAD |
| `develop.md` | Sonnet | Orchestrator — surveys Linear, dispatches developer agents |
| `backend-developer.md` | Opus | Implements one Backend issue, opens PR |
| `frontend-developer.md` | Opus | Implements one Frontend issue, opens PR |
| `devops-engineer.md` | Sonnet | Implements one DevOps issue, opens PR |
| `qa-engineer.md` | Opus | Implements full test suite, commits to main |
| `reviewer.md` | Opus | Checks acceptance criteria + TAD constraints against PR diffs |
| `contract-validator.md` | Sonnet | Diffs API contract: TAD spec vs backend routes vs frontend calls |
| `documentation-agent.md` | Opus | Writes README, API reference, architecture overview |

Model rationale: Opus for open-ended reasoning over an unknown codebase; Sonnet for structured execution from a defined template.

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

The orchestrator (`develop.md`) passes arguments to developer agents in this format:

```
Issue: {issue_id} — {issue_title}
Branch: {branch-name}
[ALREADY EXISTS]        ← present only if the branch was created by a prior phase
```

QA and documentation agents receive simpler strings (`"all non-Done QA tasks"`, project slug, etc.). Check the relevant spawn call in `develop.md` for the exact format.

---

## Adding a new agent

1. Create `.claude/agents/{name}.md` with the frontmatter above.
2. Add it to the roster table in this file.
3. If it is spawned by the orchestrator, add the spawn call to `develop.md` at the right step.
4. If it reads the TAD, verify it references the correct section numbers from the table above.
5. Update `CLAUDE.template.md` if the new agent affects the user-facing pipeline flow.
