# PI-20 — Tre testi ancora pubblici contraddicono le regole appena scritte

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: XS
**Budget**: 60
**Risk**: low
**Depends on**: PI-19
**Wave**: 1
**Files**: tasks/PI-1-worktree-script.md, .claude/agents/shared/lessons.md, CLAUDE.md
**TAD**: none
**Contract**: none
**Branch**: 
**PR**: 

## Goal
Le review di PI-19 hanno trovato tre punti del repository che dicono il contrario di ciò che PI-19 ha appena stabilito. Sono tutti anteriori a quella PR.

1. **`tasks/PI-1-worktree-script.md`, riga 20** nomina l'entry point privato dell'orchestratore. Questo repo è pubblico e quell'entry point non gli appartiene: è la stessa regola per cui PI-19 lo ha tolto dallo skill `run-wave`.
2. **`.claude/agents/shared/lessons.md`, riga 17** descrive la compattazione del contesto come un'azione che l'orchestratore compie.
3. **`CLAUDE.md`, riga 162** fa lo stesso.

Il secondo e il terzo non sono imprecisioni di stile. È verificato che il modello **non può** avviare una compattazione: la esegue il runtime, non esiste tool né comando, e il modello non può nemmeno leggere il proprio consumo di contesto. Un testo che la presenta come un'azione dell'orchestratore insegna una regola che nessuno può eseguire, e chi la legge smette di cercare la strada che funziona. Come riscritto in PI-19: all'orchestratore appartengono la decisione e il momento, non l'esecuzione.

## Acceptance criteria
- [ ] AC1 — Dato `tasks/PI-1-worktree-script.md`, quando lo si legge, allora non nomina l'entry point privato e la frase conserva il suo senso.
- [ ] AC2 — Dati `shared/lessons.md` e `CLAUDE.md`, quando li si legge, allora non presentano la compattazione come un'azione che l'orchestratore esegue.
- [ ] AC3 — Dato l'intero repository, quando lo si cerca, allora il nome dell'entry point privato non compare in nessun file che arriva su main, né nei messaggi di commit della PR.

## Tests expected
Nessun test automatico: sono file di prosa. AC3 si verifica con una ricerca sull'intero albero, **descritta per effetto nel report senza scrivere il nome**: PI-19 ha dovuto fare un giro in più proprio perché il comando di verifica riportato nel report conteneva il nome che si stava togliendo. Integration/E2E: non servono.

## Notes
`shared/lessons.md` è il file delle lezioni di metodo, e lo possiede il retro: correggi solo la riga indicata, non riordinare, non consolidare, non promuovere né togliere lezioni.

Per AC2 riprendi la formulazione già approvata in `.claude/skills/run-wave/SKILL.md` dopo PI-19, così i tre testi dicono la stessa cosa con parole coerenti.

Questo repo è pubblico: niente dei progetti su cui gira la pipeline.
