## Intake — the questions belong here, not in the agents

This skill runs **in the main session**, where `AskUserQuestion` works. It replaces every question the pipeline agents used to ask, so that from here on nothing downstream needs to guess. Do not spawn an agent for this.

Arguments (free text, optional): `$ARGUMENTS`

### 1. Read what already exists
`cat .pocket-it.json 2>/dev/null`, `ls business-analysis tech-analysis tasks 2>/dev/null`, `git remote -v | head -1`, `sed -n 1,40p README.md 2>/dev/null`. Never re-ask what is already answered there.

### 2. Ask once, in one `AskUserQuestion` call (max 4 questions), only what is still unknown
Pick from, in priority order:
1. **Cosa costruiamo** — one sentence from the user if `$ARGUMENTS` is empty, plus "chi lo usa" (customers / staff / admin).
2. **Scope** — `simple` (sito o feature piccola) / `medium` (prodotto con backend) / `full` (enterprise, multi-team).
3. **Vincoli duri** — stack imposto, integrazioni obbligatorie, deploy target, scadenza, budget CI (multi-select: "nessuno", "stack imposto: …", "integrazione: …", "scadenza: …").
4. **Come lavoriamo** — automerge on/off, test integration/E2E `on-demand` (default) / `on` / `off`, branching `flat` / `epic`.

Use the "Other" answer freely for specifics. One round only; if a second round is needed, the brief says so instead.

### 3. Write two files, then commit them
- `.pocket-it.json` — from `~/.claude/agents/pocket-it/templates/pocket-it.json`, with the answers applied (never drop keys).
- `business-analysis/BRIEF.md` — ≤ 40 lines, the user's own words where possible:

```markdown
# Brief — {product / feature}
Data: {today} · Scope: {scope} · Fonte: intake con l'utente

## Cosa
{2–4 sentences}
## Per chi
{personas in one line each}
## Vincoli duri
{bullets, or "nessuno dichiarato"}
## Fuori scope (detto dall'utente)
{bullets}
## Decisioni di lavoro
automerge {on/off} · test integration/E2E {policy} · branching {flat/epic} · base {branch}
## Domande ancora aperte
{only what the user said "non lo so" to}
```

```bash
git add .pocket-it.json business-analysis/BRIEF.md && git commit -q -m "chore: intake — brief e config pocket-it" && git push -q
```

### 4. Hand off
Tell the user the two paths, then run `/business-analyst business-analysis/BRIEF.md` unless they said to stop here. The business-analyst treats BRIEF.md answers as facts.
