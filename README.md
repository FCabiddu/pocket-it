# pocket-it

An AI-powered software development pipeline built on [Claude Code](https://claude.ai/code) agents. Choose the path that fits your project: a single-command MVP builder for prototypes, or a full structured pipeline for production products.

---

## How it works

```mermaid
flowchart TD
    subgraph lite["⚡ Lite — MVP Builder"]
        MVP(["/mvp\nDescription + optional stack"])
        MVP --> MVPOUT[("Full-stack MVP\nFrontend + Backend\nModern UI — committed")]
    end

    subgraph full["🏗️ Full Pipeline"]
        A(["/business-analyst"]) --> B[("BAD\nBusiness Analysis Doc")]
        B --> C(["/tech-architect"])
        C --> D[("TAD\nTechnical Architecture Doc")]
        D --> E(["/implementation-planner"])
        E --> F[("IPD\nImplementation Plan Doc\n+ Linear Issues")]

        F --> G{{"👤 Human checkpoint\nReview plan & Linear board"}}

        G --> H(["/scaffold"])
        H --> I[("Repo initialized\nDeps installed\nInitial commit")]

        I --> J{{"👤 Human checkpoint\nVerify scaffold"}}

        J --> K(["/develop"])

        K --> L{Cross-group\ndependencies?}

        L -->|None| M([Parallel dispatch])
        L -->|Frontend needs Backend| N([Phased dispatch])

        M --> FE([Frontend Agent\nOpus])
        M --> BE([Backend Agent\nOpus])
        M --> DO([DevOps Agent\nSonnet])
        M --> QA([QA Agent\nOpus])

        N --> P1([Phase 1\nBackend + DevOps])
        P1 --> P2([Phase 2\nFrontend + QA])
    end
```

---

## Lite path — MVP Builder

| Skill | What it does | Model |
|---|---|---|
| `/mvp [description]` | Takes a plain-English description, picks or confirms a stack, builds frontend + backend with a modern production-quality UI, runs checks, and commits. No TAD, no Linear, no pipeline ceremony. | Opus |

```bash
# Stack auto-selected — agent confirms before building
/mvp a job board with company profiles and applicant tracking

# Specify your own stack
/mvp a todo app with auth Stack: Next.js, Supabase
```

Use the lite path for prototypes, side projects, and one-off tools. Use the full pipeline when you need Linear traceability, TAD-derived quality gates, and code reviews.

---

## Full pipeline steps

### Phase 1 — Planning

| Skill | What it produces | Model |
|---|---|---|
| `/business-analyst` | Business Analysis Document (BAD) — user stories, acceptance criteria, scope | Sonnet |
| `/tech-architect` | Technical Architecture Document (TAD) — stack, structure, API contracts, infra, testing strategy | Opus |
| `/implementation-planner` | Implementation Plan Document (IPD) — epics, stories, tasks with estimates + Linear issues with labels | Sonnet |

**Output:** three Markdown documents in `./business-analysis/`, `./tech-analysis/`, `./implementation-plans/` and a fully populated Linear project.

---

### Phase 2 — Bootstrap

| Skill | What it does | Model |
|---|---|---|
| `/scaffold [git-url]` | Reads the TAD, runs the stack init command, installs deps, creates folder structure, `.gitignore`, `.env.example`, README, then commits. Pushes to `git-url` if provided. | Sonnet |

**`/develop` hard-blocks if scaffold has not been run.**

---

### Phase 3 — Build

| Skill | What it does | Model |
|---|---|---|
| `/develop` | Surveys the Linear board, groups tasks by label, checks cross-group dependencies, presents a dispatch plan, then spawns developer agents in parallel or in phases. | Sonnet |

Developer agents spawned by `/develop`:

| Agent | Responsibility | Model |
|---|---|---|
| `frontend-developer` | UI components, pages, state management, routing — reads TAD for exact stack | Opus |
| `backend-developer` | APIs, services, database migrations, background jobs — reads TAD for exact stack | Opus |
| `devops-engineer` | Dockerfiles, CI/CD pipelines, infrastructure config — reads TAD for exact infra | Sonnet |
| `qa-engineer` | Full testing pyramid — unit, component, integration, E2E — reads TAD for exact test stack | Opus |

Each agent: marks Linear issues **In Progress** when starting, **Done** when complete.

---

## Setup

### Prerequisites

- [Claude Code](https://claude.ai/code) installed
- A [Linear](https://linear.app) account with the Claude AI Linear MCP connected

### Install

Clone the repo, then copy the `.claude/` folder into your target project:

```bash
git clone https://github.com/FCabiddu/pocket-it
cp -r pocket-it/.claude /your/project/root/
```

Copy the pipeline config to your global Claude Code settings so the agents have context in every project:

```bash
cp pocket-it/CLAUDE.template.md ~/.claude/CLAUDE.md
```

> If you already have a `~/.claude/CLAUDE.md`, append the contents of `CLAUDE.template.md` to it rather than overwriting.

Then install the security hook (blocks pushes containing secrets or API keys):

```bash
bash .claude/hooks/install.sh
```

Restart Claude Code. The skills will appear in your `/` menu.

---

## Usage

### Lite path

```bash
# Description only — agent picks the stack and confirms
/mvp a job board with company profiles and applicant tracking

# Specify a stack
/mvp a real-time chat app Stack: Next.js, Prisma, SQLite
```

### Full pipeline

```bash
# 1. Describe your feature — agent produces the BAD
/business-analyst Build a recipe sharing app with social features

# 2. Review the BAD, then generate the architecture
/tech-architect

# 3. Review the TAD, then generate the implementation plan + Linear issues
/implementation-planner

# Review the Linear board. Edit or remove issues if needed.

# 4. Scaffold the project (optionally push to a remote)
/scaffold
# or
/scaffold https://github.com/you/your-project

# 5. Dispatch developer agents
/develop
```

---

## Model choices

| Agent | Model | Why |
|---|---|---|
| mvp-builder | **Opus** | Open-ended stack decisions, full-stack design, unknown codebase |
| business-analyst | Sonnet | Template-driven structured output |
| tech-architect | **Opus** | Open-ended research, high-stakes irreversible architectural decisions |
| implementation-planner | Sonnet | Structured breakdown from a defined TAD |
| frontend-developer | **Opus** | Adapts to unknown stack, produces core codebase |
| backend-developer | **Opus** | Same — APIs, migrations, business logic |
| qa-engineer | **Opus** | Test design requires reasoning across the whole codebase |
| devops-engineer | Sonnet | Structured config files, well-defined patterns |
| develop (orchestrator) | Sonnet | Reads Linear + dispatches agents, no deep reasoning needed |
| scaffold | Sonnet | Structured execution from TAD, no open-ended reasoning |

---

## Repository structure

```
.claude/
  agents/     # Agent definitions
  skills/     # Skill launchers
README.md
```

Drop the `.claude/` folder into any project root and the skills appear automatically in Claude Code.
