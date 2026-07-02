# pocket-it — Agent Maintenance Guide

This file is for working on the agents themselves. (The old `CLAUDE.template.md` for target projects was removed from versioning together with Flow A — recover it from git history at `72bd240^` if you need it.)

---

## Agent format

Each agent is a Markdown file in `.claude/agents/` with a YAML frontmatter block:

```yaml
---
name: agent-name          # matches the filename without .md
description: ...          # shown in the agent picker; also used by the orchestrator
model: claude-sonnet-5  # or claude-opus-4-8 / claude-haiku-4-5-20251001
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

**Standalone tools**

| File | Model | Role |
|------|-------|------|
| `mvp-builder.md` | Sonnet | Builds an award-quality static site (index.html + css/ folder, vanilla JS) from a plain-English description; no TAD/Linear required. Output to `~/Desktop/clients/{slug}/` |

(The other Flow A agents — business-prospector, pitch-generator, scraper, legal-advisor, css-animator — and the Flow C creative-writing agents were removed from this repo; recover them from git history before `72bd240` if needed.)

**Flow B — Full software engineering pipeline**

| File | Model | Role |
|------|-------|------|
| `business-analyst.md` | Sonnet | Writes BAD from a feature description |
| `tech-architect.md` | Opus | Writes TAD from the BAD (reads Design Spec from `design-specs/` if present, otherwise BAD alone) |
| `implementation-planner.md` | Sonnet | Writes IPD, pushes Linear issues, writes deps JSON |
| `developer.md` | Sonnet | Implements one Backend or Frontend issue (branches on `Label:` in arguments), opens a draft PR |
| `devops-engineer.md` | Sonnet | Implements one DevOps issue, opens a draft PR |
| `qa-engineer.md` | Sonnet | Implements full test suite on a branch, opens a draft PR |
| `reviewer.md` | Sonnet | Checks acceptance criteria + TAD constraints against PR diffs |
| `documentation-agent.md` | Sonnet | Writes README, API reference, architecture overview |

Model rationale: all agents run on Sonnet (Pro subscription — optimising for token budget). Upgrade individual agents to Opus if quality gaps appear in practice.

---

## Output folders

| Folder | Created by | Read by |
|--------|-----------|---------|
| `business-analysis/` | `business-analyst` | `tech-architect` |
| `tech-analysis/` | `tech-architect` | all developer agents |
| `best-practices/` | `tech-architect` (Step 6) | `developer`, `devops-engineer`, `qa-engineer` |
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
| 4.3 | Schema Definitions (constraints, indices, foreign keys) |
| 5.1 | API style (REST / GraphQL / tRPC) + auth method |
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
| 8.2 | Backend design patterns (Repository, service layer) |
| 8.3 | Background jobs |
| 8.4 | Caching strategy |
| 9.1 | Infrastructure diagram |
| 9.2 | Environment matrix |
| 9.3 | CI/CD pipeline steps |
| 9.4 | Container configuration + runtime environment variables |
| 9.5 | Observability stack |
| 9.6 | Disaster recovery (RTO / RPO) |
| 10.1 | Scaling strategy |
| 11.1 | Testing Pyramid (unit/component/integration/E2E tools) |
| 11.2 | Test environment strategy (isolation, factories, mocking) |
| 11.3 | Quality gates + coverage targets |

The `tech-architect` template enforces this: skipped sections keep their heading with a one-line `N/A` so numbering never shifts.

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

**`/reviewer`** — pass PR numbers or branch names: `Review the following PRs: 12, 13` (or branch names if the PR isn't known yet)

**`/documentation-agent`** — pass a project slug or leave empty to auto-detect

---

## Flow B conventions

| Convention | Format | Example |
|---|---|---|
| Feature branch | `feat/{issue-id-lower}-{title-slug}` | `feat/lin-42-user-auth-api` |
| QA fix branch | `fix/{bug-ticket-id-lower}-{slug}` | `fix/lin-87-login-500` |
| Docs branch | `docs/{project-slug}-{YYYY-MM-DD}` | `docs/recipe-app-2026-05-21` |
| Auto-merge label | GitHub PR label `Auto-merge`, colour `#94a3b8` (slate); mirrored in Linear by `/implementation-planner` | Applied by implementing agents when the session preference is Auto-merge; acted on by `.github/workflows/auto-merge.yml` (created by `/devops-engineer`) |
| Dependency file | `implementation-plans/{NAME}_DEPS.json` | Written by `/implementation-planner`; read by developer agents for ordering |

### Merge gate (developer → reviewer → user)

Code reaches GitHub as a **draft PR** (so CI runs and work is backed up), but nothing lands on `main` automatically. The merge is the gate, and only the user triggers it:

1. **`/developer`** — creates a task branch, implements, commits, pushes, and opens a **draft** PR. It never marks the PR ready-for-review and never merges. Reports the branch, commit SHA, and PR URL.
2. **`/reviewer`** — reviews the draft PR diff (`gh pr diff {n}`). Feedback posts to the PR (`gh pr review --request-changes`) and mirrors to Linear. On pass it marks the PR **ready for review** (`gh pr ready`) and approves — but does **not** merge.
3. **Merge** — the merge happens only after reviewer approval **and** user authorisation. Authorisation takes one of two forms: an explicit per-PR instruction (e.g. "merge LIN-42" / "ship it"), or the session auto-merge preference below. No agent ever runs `gh pr merge` on its own initiative.

**Session auto-merge preference (Step 0a):** the first implementing agent of a session asks once — "How should PRs be handled this session?" — and records the answer in `/tmp/{repo-name}-automerge`. If the user chose **Auto-merge**, implementing agents apply the `Auto-merge` label at PR creation and the target project's `.github/workflows/auto-merge.yml` (created by `/devops-engineer` alongside the CI pipeline; requires "Allow auto-merge" + branch protection on `main` in repo settings) merges once CI is green and the reviewer has approved — the user's gate is exercised once per session instead of per PR. If **Manual approval**, every merge stays per-PR. Delete the file to be asked again. `developer`, `devops-engineer`, and `qa-engineer` all read this preference; the `reviewer` reports whether an approved PR will auto-merge or awaits authorisation.

Why draft-PR-then-gate-the-merge instead of withholding the push: a draft PR runs CI, backs the work up to the remote, and gives line-anchored review — while the not-ready/unmerged state is the actual safety gate. Withholding the push only changes the definition of "on GitHub"; it doesn't add real safety and it loses CI + backup.

**Same gate applies to `devops-engineer` and `qa-engineer`:** both now commit on a branch, push, and open a **draft** PR — never pushing to `main` or merging directly. `qa-engineer` puts its test suite on a `test/qa-suite-{YYYY-MM-DD}` branch instead of committing to `main`. The merge stays user-triggered for all four implementing agents.

---

## Adding a new agent

1. Create `.claude/agents/{name}.md` with the frontmatter above.
2. Add it to the roster table in this file.
3. Create a matching skill in `.claude/skills/{name}/SKILL.md` so it is user-invocable.
4. If it reads the TAD, verify it references the correct section numbers from the table above.
5. Update the README if the new agent affects a user-facing flow.

## Adding a new skill

Skills are user-invocable launchers (`/skill-name`) that spawn an agent. Each skill lives in its own directory:

```
.claude/skills/{name}/SKILL.md
```

The `SKILL.md` content follows this pattern:

```markdown
## Launcher

Your only job is to spawn an isolated agent. Call the Agent tool immediately with:
- `subagent_type`: `general-purpose`
- `model`: `sonnet` or `opus`   ← must match the agent's frontmatter model
- `description`: `{Human-readable description}`
- `run_in_background`: `false`
- `prompt`: exactly the text below (substitute $ARGUMENTS verbatim)

---

Read the file `/Users/user/Desktop/pocket-it/.claude/agents/{name}.md` using the Read tool. Replace every occurrence of `{{ARGUMENTS}}` in the content with this exact value:

$ARGUMENTS

Then execute the instructions in that file exactly as written.
```

Note: `.claude/commands/` is the legacy format — it still works but `.claude/skills/` is the current recommended format.
