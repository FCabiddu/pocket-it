# pocket-it — Agent Maintenance Guide

This file is for working on the agents themselves. (The old `CLAUDE.template.md` for target projects was removed from versioning together with the old prospecting agents — recover it from git history at `72bd240^` if you need it.)

---

## Agent format

Each agent is a Markdown file in `.claude/agents/` with a YAML frontmatter block:

```yaml
---
name: agent-name          # matches the filename without .md
description: ...          # shown in the agent picker; also used by the orchestrator
model: sonnet             # alias: sonnet / opus / haiku / inherit (not full IDs like claude-opus-4-8)
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
| `ux-ui-designer.md` | Opus | **Three modes.** Standalone: (A) audits an existing static site against the shared compass → `{target-dir}/UX_UI_REVIEW.md`; (B) gives a lightweight static-site design direction for `mvp-builder`. Also runs **in the development pipeline** (see below) as mode (C). Keeps 28 inspiration galleries as a manual compass-refresh channel (not a runtime fetch). Critiques and directs; does not build. |

(The old prospecting agents — business-prospector, pitch-generator, scraper, legal-advisor, css-animator — and the creative-writing agents were removed from this repo; recover them from git history before `72bd240` if needed.)

**Development pipeline — full software engineering flow**

| File | Model | Role |
|------|-------|------|
| `business-analyst.md` | Sonnet | Writes BAD from a feature description |
| `ux-ui-designer.md` (mode C) | Opus | Acts as a pure UX/UI designer: reads the BAD, writes an enterprise Design Spec (design tokens, component specs with accessibility contracts, page/screen specs, IA, WCAG 2.1 AA) to `design-specs/{NAME}_DESIGN_SPEC.md`. Runs after `business-analyst`, before `tech-architect`. **Scope-conditioned: a default step for `Production`/enterprise BADs, optional for `MVP`/simple/static.** `business-analyst` recommends it (or not) based on `PROJECT_SCOPE` in its closing report |
| `tech-architect.md` | Opus | Writes TAD from the BAD (reads the Design Spec from `design-specs/` if present — folds it into TAD Section 7 per the spec's §8 handoff table — otherwise BAD alone) |
| `implementation-planner.md` | Sonnet | Writes IPD, pushes Linear issues, writes deps JSON |
| `developer.md` | Sonnet | Implements one Backend or Frontend issue (branches on `Label:` in arguments), opens a draft PR |
| `devops-engineer.md` | Sonnet | Implements one DevOps issue, opens a draft PR |
| `qa-engineer.md` | Sonnet | Implements full test suite on a branch, opens a draft PR |
| `reviewer.md` | Sonnet | Checks acceptance criteria + TAD constraints against PR diffs |
| `documentation-agent.md` | Sonnet | Writes README, API reference, architecture overview |

Model rationale: agents run on Sonnet by default (Pro subscription — optimising for token budget). Exceptions on Opus where judgement quality dominates: `tech-architect` (architecture) and `ux-ui-designer` (design taste + accessibility depth). Upgrade others to Opus if quality gaps appear in practice.

### Shared design compass

`mvp-builder` and `ux-ui-designer` share one design knowledge base: `.claude/agents/shared/design-compass.md` (layout archetypes, typography, colour, Industry Design DNA, decorative elements, full animation catalogue). Both agents `Read` it at runtime instead of embedding it — the builder to make design decisions, the designer to judge/design against the same standard. **Edit the compass once; never copy its content back into either agent.** Each agent keeps only its own framing on top: the builder's anti-repetition + build rules; the designer's three modes (audit rubric, static direction, and the enterprise Design Spec whose component/accessibility/WCAG knowledge lives in the agent file, not the compass — the compass is the shared *visual language*, deliberately builder-focused and not bloated with app-UI concerns).

The designer's 28-gallery inspiration library is a **manual** refresh channel, not a runtime tool — those galleries are JS-heavy SPAs that return only site names to a fetch (verified), so the agent never fetches them during an audit. A human browses them and distils new trends into the compass.

### Accessibility floor — WCAG 2.1 AA (mandatory, no opt-out)

Accessibility is decoupled from the optional Design Spec: a **WCAG 2.1 AA baseline is a hard floor on every output**, standalone or inside the development pipeline, MVP or enterprise. It lives in the shared `design-compass.md` (so `mvp-builder` static sites meet it too) and is enforced end-to-end:
- **Compass** — defines the baseline checklist; `mvp-builder` and `ux-ui-designer` both read it.
- **Design Spec** (`ux-ui-designer` mode C) — *adds depth* (per-component ARIA/keyboard contracts + verification plan); never lowers the floor.
- **TAD 7.6** — accessibility target is never `N/A`; minimum AA even for MVP/static.
- **qa-engineer** — builds mandatory a11y tests (axe + keyboard/focus) from the target.
- **reviewer** — treats the AA baseline as a code-quality gate on frontend diffs.

The *depth* of the design (tokens, component library, screens) scales with scope; the *accessibility floor* does not. Editing the compass is the only way to change the baseline — there is deliberately no per-project switch.

---

## Output folders

| Folder | Created by | Read by |
|--------|-----------|---------|
| `business-analysis/` | `business-analyst` | `ux-ui-designer` (mode C), `tech-architect` |
| `design-specs/` | `ux-ui-designer` (mode C) | `tech-architect` (→ TAD Section 7); `developer` (Frontend — read directly, overrides TAD §7) |
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
| 7.4 | CSS approach + component-library **technology** (engineering choice). Design tokens & per-component visual/behavioural contracts are NOT here — the Design Spec in `design-specs/` is authoritative; 7.4 references it |
| 7.5 | Performance budget |
| 7.6 | Rendering strategy (SSR/SSG/ISR/CSR) + accessibility target. **The accessibility target is never `N/A`: minimum WCAG 2.1 AA always** (see the a11y floor policy below); per-component a11y depth lives in the Design Spec |
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

**`/ux-ui-designer`** — mode is inferred from what you pass:
- Enterprise Design Spec (development pipeline): pass the BAD path — `business-analysis/{NAME}_BUSINESS_ANALYSIS.md` (or run it right after `/business-analyst`)
- Audit: pass a built-site path or URL — `~/Desktop/clients/{slug}` or `https://…`
- Static direction: pass a plain brief — `Design direction for a coffee-bar landing page`

**`/developer`**
```
Issue: {issue_id} — {issue_title}
Label: Backend | Frontend
Branch: {branch-name}
DesignSpec: design-specs/{NAME}_DESIGN_SPEC.md   # optional; Frontend only
```
`DesignSpec:` is optional — a `Frontend` developer auto-discovers `design-specs/*.md` if the line is omitted. Pass it explicitly to disambiguate when several specs exist. It is the authoritative source for visual/component/accessibility decisions and overrides TAD Section 7 where they conflict (the length-capped TAD carries only a summary of it).

**`/devops-engineer`**
```
Issue: {issue_id} — {issue_title}
Branch: {branch-name}
```

**`/qa-engineer`** — pass a project description or `"all non-Done QA tasks"`

**`/reviewer`** — pass PR numbers or branch names: `Review the following PRs: 12, 13` (or branch names if the PR isn't known yet). Also pass `TAD:`/`IPD:` and, whenever the target project has one, `Best practices: {path}` — same as `/developer`/`/qa-engineer`/`/devops-engineer` — so best-practices compliance is checked as part of the review, not silently skipped. If unsure whether a best-practices folder exists for the project, check (`find . -type d -name "best-practices"`) before invoking rather than omitting the line.

**`/documentation-agent`** — pass a project slug or leave empty to auto-detect

---

## Development pipeline conventions

| Convention | Format | Example |
|---|---|---|
| Feature branch | `feat/{issue-id-lower}-{title-slug}` | `feat/lin-42-user-auth-api` |
| QA fix branch | `fix/{bug-ticket-id-lower}-{slug}` | `fix/lin-87-login-500` |
| Docs branch | `docs/{project-slug}-{YYYY-MM-DD}` | `docs/recipe-app-2026-05-21` |
| Auto-merge label | GitHub PR label `Auto-merge`, colour `#94a3b8` (slate); mirrored in Linear by `/implementation-planner` | Applied by implementing agents when the session preference is Auto-merge; acted on by the orchestrator's own merge (and, only on a project that opted into a hosted pipeline, also by `.github/workflows/auto-merge.yml`) |
| Dependency file | `implementation-plans/{NAME}_DEPS.json` | Written by `/implementation-planner`; read by developer agents for ordering |
| Pipeline integration | Optional, **off by default** — GitHub repository variable `APP_STATUS` = `dev` \| `prod` only exists on a project that opted in | Asked once per session by `/devops-engineer` (Step 0b); declining is the recommended default |

### Pipeline integration — opt-in, off by default

Hosted CI/CD is **not part of the default flow**. Building a pipeline nobody is watching yet just burns runner minutes and turns every review into a "is this a known pre-existing failure or a new one" argument — real friction we hit repeatedly before this became opt-in. `devops-engineer` now asks once per session, before touching any infrastructure task (Step 0b in its template), whether the project wants a GitHub Actions pipeline at all. **Declining is the recommended default** for a project still in active development.

- **If declined (default):** no `.github/workflows/*.yml` is created or modified, no `APP_STATUS` variable is set, no `Auto-merge` GitHub Action is wired up. Validation stays entirely local — `developer`/`devops-engineer`/`qa-engineer` run `lint → type-check → scoped tests` before pushing, and `reviewer` reads the diff directly with no CI step in its process at all. The `Auto-merge` PR label (a separate, CI-independent preference — see the merge gate below) still works exactly as before: the orchestrator merges once the reviewer approves, it just isn't a GitHub Action doing it.
- **If accepted:** the project gets the dev/prod-gated pipeline described in `devops-engineer.md` — a repository variable `APP_STATUS` (`dev` by default, flipped to `prod` only by explicit human action), a job-level `if:` gate that keeps required status checks satisfiable and free in `dev` (so nothing blocks on "waiting for status to be reported"), and a matching `.github/workflows/auto-merge.yml`. This mechanism is unchanged from before — it's just no longer the default, and the user has to ask for it.
- **Recorded like the auto-merge preference:** `/tmp/{repo-name}-pipeline` holds `true`/`false`. Delete it to be asked again.
- **This preference only governs whether a NEW pipeline gets built.** A project that already has one wired up (or that a human set up outside this flow) keeps it — no agent tears down an existing pipeline on its own initiative just because this preference exists. Removing an existing pipeline is a deliberate, user-directed action, done by hand or via an explicit instruction to `devops-engineer`, not an automatic consequence of this default.
- **Deployment stays out of scope regardless of the answer.** `tech-architect` marks TAD §9.3's deploy rows `N/A — deployment not managed by CI yet` either way, and `devops-engineer` never writes deploy jobs, environment targets, or deploy secrets even on a project that opted into CI.

### Merge gate (developer → reviewer → user)

Code reaches GitHub as a **draft PR** (so the work is backed up and reviewable, and runs CI on a project that opted into a pipeline), but nothing lands on `main` automatically. The merge is the gate, and only the user triggers it:

1. **`/developer`** — creates a task branch, implements, commits, pushes, and opens a **draft** PR. It never marks the PR ready-for-review and never merges. Reports the branch, commit SHA, and PR URL.
2. **`/reviewer`** — reviews the draft PR diff (`gh pr diff {n}`). Feedback posts to the PR (`gh pr review --request-changes`) and mirrors to Linear. On pass it marks the PR **ready for review** (`gh pr ready`) and approves — but does **not** merge.
3. **Merge** — the merge happens only after reviewer approval **and** user authorisation. Authorisation takes one of two forms: an explicit per-PR instruction (e.g. "merge LIN-42" / "ship it"), or the session auto-merge preference below. No agent ever runs `gh pr merge` on its own initiative.

**Session auto-merge preference (Step 0a):** the first implementing agent of a session asks once — "How should PRs be handled this session?" — and records the answer in `/tmp/{repo-name}-automerge`. This preference is independent of the pipeline-integration one above — it governs who pulls the merge trigger, not whether CI exists. If the user chose **Auto-merge**, implementing agents apply the `Auto-merge` label at PR creation, and once the reviewer approves, the merge happens without a further per-PR ask — via the orchestrator's own `gh pr merge` on a project with no pipeline, or via `.github/workflows/auto-merge.yml` (requires "Allow auto-merge" + branch protection on `main`) on a project that opted into one. If **Manual approval**, every merge stays per-PR. Delete the file to be asked again. `developer`, `devops-engineer`, and `qa-engineer` all read this preference; the `reviewer` reports whether an approved PR will auto-merge or awaits authorisation.

Why draft-PR-then-gate-the-merge instead of withholding the push: a draft PR backs the work up to the remote and gives line-anchored review — while the not-ready/unmerged state is the actual safety gate. Withholding the push only changes the definition of "on GitHub"; it doesn't add real safety and it loses the backup.

**Same gate applies to `devops-engineer` and `qa-engineer`:** both now commit on a branch, push, and open a **draft** PR — never pushing to `main` or merging directly. `qa-engineer` puts its test suite on a `test/qa-suite-{YYYY-MM-DD}` branch instead of committing to `main`. The merge stays user-triggered for all four implementing agents.

### Project history log (opt-in per project)

Long-running pipeline engagements risk the orchestrator (human or Claude) burning a large share of a fresh session just re-deriving what already happened from `git log` across dozens of PRs. The mitigation is a running, reverse-chronological history file the pipeline keeps current on its own, instead of relying on the orchestrator to remember to write one near a context limit.

- **Location, by convention:** `docs/SESSION_HANDOFF.md` in the target project. **Opt-in, not mandatory** — a project only has one once someone (usually the orchestrator, on the user's request) creates it. Implementing agents check for it and use it if present; none of them create it unprompted.
- **Who writes to it:** `developer`, `devops-engineer`, and `qa-engineer` each append a short entry (1–3 lines: issue ID, PR number marked "(draft)", one-line what/why) at Step 5g/7.5, right after opening their PR. `reviewer` then updates that entry's marker to "approved, awaiting merge" at Step 4d on approval (or appends one if it's missing). The orchestrator finalises the entry to reflect the actual merge once the user authorises it — the one step no agent template can do on its own, since none of them merge.
- **Content shape:** a short "architectural facts worth remembering" section (gotchas, non-obvious invariants, conventions discovered the hard way) that stays evergreen, plus the reverse-chronological PR/feature log itself. Entries are terse — the PR/commit is the source of truth for detail; this file is a fast-recovery index, not a duplicate changelog.
- **Starting one:** if a project doesn't have this file yet and the user wants one, write it directly (no dedicated agent for this) — backfill a compressed history from context/`git log` if useful, then let the pipeline steps above keep it current going forward.

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
