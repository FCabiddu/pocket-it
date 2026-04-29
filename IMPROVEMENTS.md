# Pipeline Improvements

_Last audited: 2026-04-29_

---

## Real gaps (things that can break)

---

### IMP-1 — Linear re-discovery in every child agent

**Severity**: Medium — redundant MCP calls, risk of name-matching picking the wrong project  
**Files**: `develop.md`, `backend-developer.md`, `frontend-developer.md`, `devops-engineer.md`, `qa-engineer.md`, `reviewer.md`, `documentation-agent.md`

**Problem**

The orchestrator already resolved the project ID, team ID, and status IDs in Step 2. Every child agent re-calls `list_teams` → `list_projects` to find the same project via name-matching. That is 5 agents × 2–3 MCP calls = 10–15 redundant calls per run, plus the risk that fuzzy name-matching picks the wrong project in a workspace with similarly-named projects.

**Fix**

In `develop.md` Step 5, extend the arguments string passed to every child agent:

```
Project: {project_name} (Linear project ID: {project_id}, team ID: {team_id}).
Issue: {issue_id} — {issue_title}.
Branch: feat/{branch_name}.
Status IDs: In Progress = {in_progress_id}, Done = {done_id}.
```

In each child agent, replace the `list_teams` + `list_projects` + `list_issue_statuses` calls with: parse the IDs from arguments and use them directly. Only call `get_issue` and `save_issue`.

Also remove `mcp__claude_ai_Linear__list_teams`, `mcp__claude_ai_Linear__list_projects`, and `mcp__claude_ai_Linear__list_issues` from the tools list of agents that no longer need them.

---

### IMP-2 — Reviewer scope expanded to code quality; fix loop uses code-quality-only mode

**Severity**: Medium — redundant acceptance criteria gate on bug fixes; no TAD-derived quality gate on any PR  
**Files**: `develop.md` Step 8, `reviewer.md`

**Problem**

The reviewer only checked acceptance criteria, which is redundant on bug fix PRs (criteria already verified in Step 6). At the same time, no PR — feature or fix — had a code quality gate derived from the TAD (security controls, API contract, migrations).

**Fix**

Expanded the reviewer to run two tracks:
- **Code quality check** (always): TAD Section 6.2 security controls, Section 5.2 API contract, Section 8 migration conventions. Binary and TAD-derived only — no style or subjective criteria.
- **Acceptance criteria check** (full mode only): original behaviour, unchanged.

`develop.md` Step 6 passes `Mode: full`. Step 8 passes `Mode: code-quality-only` — acceptance criteria are skipped since they were already verified, but the code quality gate now runs on bug fix PRs too.

---

### IMP-3 — No explicit warning when DEPS.json is missing

**Severity**: Low — silent fallback to brittle text parsing  
**File**: `develop.md` Step 3

**Problem**

Step 3 silently falls back to IPD text parsing if `*_DEPS.json` is not found. Text parsing of a free-form dependency section is brittle — edge cases in wording can cause the orchestrator to miss a blocking dependency and dispatch an issue before its blocker is done.

**Fix**

In Step 3, after the fallback branch triggers, add an explicit user-facing warning before continuing:

> "No DEPS.json found in `implementation-plans/`. Falling back to IPD Section 5 text parsing for dependencies — this may miss complex relationships. If the dependency graph is non-trivial, cancel and re-run `/implementation-planner` to regenerate the deps file."

---

## Simplification opportunities

---

### IMP-4 — Spawn protocol repeated 8 times verbatim

**Severity**: Low — maintenance burden, risk of inconsistency  
**File**: `develop.md`

**Problem**

Every agent spawn in `develop.md` (Steps 5, 5.5, 6, 7, 8, 8.5) repeats the same 3-step pattern:

1. Use the Read tool to read the agent file
2. Replace `{{ARGUMENTS}}` with a constructed string
3. Call the Agent tool with `subagent_type: general-purpose`, `model: {opus|sonnet}`, `description:`, `prompt:`

This is duplicated 8+ times. Any change to the spawn mechanic (e.g. a new Agent tool parameter) requires updating every instance.

**Fix**

Add a `## Spawn Protocol` reference section near the top of `develop.md` that defines the pattern once. Each step then says "spawn the reviewer agent [Spawn Protocol]" and only specifies the parts that vary: agent file, arguments string, model, description.

---

### IMP-5 — Developer agents read the full IPD unnecessarily

**Severity**: Low — token waste, slower agent startup  
**Files**: `backend-developer.md`, `frontend-developer.md`, `devops-engineer.md`

**Problem**

Step 0 of every developer agent reads both the TAD and the full IPD. The agent then implements a single issue. The IPD is referenced only briefly in Step 5b ("cross-reference the task in the IPD for additional context"). The full IPD is often 5,000–10,000 tokens and contains planning context that has no bearing on implementing one task — the issue + parent story from Linear already contains all acceptance criteria.

**Fix**

Remove the full IPD read from Step 0. In Step 5b, change "cross-reference the task in the IPD" to "the issue description and parent story in Linear are your complete spec — use them directly." If an agent genuinely needs IPD context for a specific reason (e.g. checking the sprint boundary), it can skim the relevant section on demand rather than reading the whole document upfront.

---

## Status

| ID | File(s) | Severity | Status |
|----|---------|----------|--------|
| IMP-1 | `develop.md` + all child agents | Medium | ✅ Fixed |
| IMP-2 | `develop.md` Step 8 | Medium | ✅ Fixed |
| IMP-3 | `develop.md` Step 3 | Low | ✅ Fixed |
| IMP-4 | `develop.md` | Low | ✅ Fixed |
| IMP-5 | `backend-developer.md`, `frontend-developer.md`, `devops-engineer.md` | Low | ↩️ Reverted |
