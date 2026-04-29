# Claude Code — pocket-it Pipeline

This file is the runtime context for the pocket-it agent pipeline. Copy it to `~/.claude/CLAUDE.md` so Claude has pipeline context in every project where the agents are installed.

---

## Pipeline

| Step | Command | What it does | Output |
|------|---------|--------------|--------|
| 1 | `/business-analyst` | Turns a feature description into a structured Business Analysis Document | `business-analysis/{NAME}_BUSINESS_ANALYSIS.md` |
| 2 | `/tech-architect` | Turns the BAD into a full Technical Architecture Document | `tech-analysis/{NAME}_TECH_ANALYSIS.md` |
| 3 | `/implementation-planner` | Breaks the TAD into Epics, Stories, and Tasks; pushes issues to Linear; writes a dependency graph | `implementation-plans/{NAME}_IMPLEMENTATION_PLAN.md`, `implementation-plans/{NAME}_DEPS.json` |
| 4 | `/scaffold` | Initialises the project skeleton from the TAD (installs deps, creates folder structure, commits) | project files in the working directory |
| 5 | `/develop` | Full dev cycle — surveys Linear, dispatches developer agents, runs contract validation, reviewer, QA, and documentation | merged PRs on main, docs PR |

Each step reads the output of the previous one. Do not skip steps — `/develop` requires the TAD, IPD, deps JSON, and a scaffolded project.

---

## `/develop` internal flow

| Step | What happens |
|------|--------------|
| 0 | Verify project is scaffolded (manifest file check) |
| 1 | Locate TAD + IPD |
| 2 | Survey Linear board — confirm project match with user |
| 3 | Load dependency graph from `*_DEPS.json`; fall back to IPD Section 5 text |
| 4 | Present per-issue dispatch plan (branch names, blockers) — user confirms |
| 5 | Dispatch one developer agent per issue (parallel where unblocked) |
| 5.5 | Contract validation (only if both Backend + Frontend dispatched) |
| 6 | Reviewer pass — 1 fix round if needed |
| 6.5 | Human review gate — merge / skip / fix per PR; Auto-merge label bypasses |
| 7 | QA agent (runs on main; skipped if no QA issues exist) |
| 8 | QA loop-back — up to 2 fix rounds; reviewer checks fix PRs before auto-merge |
| 8.5 | Documentation agent — README, docs/API.md, docs/ARCHITECTURE.md |
| 9 | Final report |

---

## Key conventions

- **Branch names**: `feat/{issue-id-lower}-{title-slug}` (e.g. `feat/lin-42-user-auth-api`)
- **QA fix branches**: `fix/{bug-ticket-id-lower}-{slug}`
- **Docs branch**: `docs/{project-slug}-{YYYY-MM-DD}`
- **Auto-merge label**: slate `#94a3b8` — apply in Linear to skip the human review gate at Step 6.5
- **Dependency file**: `implementation-plans/{NAME}_DEPS.json` — explicit Linear identifier + UUID pairs; authoritative source for Step 3
- **Native Linear blocking arrows**: set automatically if the `LINEAR_API_TOKEN` env var is present when `/implementation-planner` runs

---

## Agents

| File | Model | Role |
|------|-------|------|
| `business-analyst` | Sonnet | Writes BAD |
| `tech-architect` | Opus | Writes TAD |
| `implementation-planner` | Sonnet | Writes IPD, pushes Linear issues, writes deps JSON |
| `scaffold` | Sonnet | Initialises project skeleton |
| `develop` | Sonnet | Orchestrator |
| `backend-developer` | Opus | Implements one Backend issue, opens PR |
| `frontend-developer` | Opus | Implements one Frontend issue, opens PR |
| `devops-engineer` | Sonnet | Implements one DevOps issue, opens PR |
| `qa-engineer` | Opus | Implements full test suite, commits to main |
| `reviewer` | Opus | Checks acceptance criteria + TAD constraints against PR diffs |
| `contract-validator` | Sonnet | Diffs API contract: TAD spec vs backend routes vs frontend calls |
| `documentation-agent` | Opus | Writes README, API reference, architecture overview |
| `mvp-builder` | Opus | Builds a full-stack MVP from a plain-English description; no TAD/Linear required |
