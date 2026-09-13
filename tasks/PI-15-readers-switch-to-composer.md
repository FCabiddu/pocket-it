# PI-15 — I lettori passano al compositore

**Status**: Todo
**Label**: DevOps
**Epic**: handoff
**Story**: handoff
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: PI-14
**Wave**: 2
**Files**: bin/status.sh:37-40, .claude/agents/shared/implementing-common.md:39, .claude/agents/developer.md:32, .claude/agents/reviewer.md:19, .claude/agents/retro.md:23-24, .claude/agents/implementation-planner.md:56, .claude/agents/shared/lessons.md:3, .claude/skills/run-wave/SKILL.md:50
**TAD**: tech-analysis/HANDOFF_MEMORY_TECH_ANALYSIS.md (§5.2, §9.1, §12 PI-15)
**Contract**: none
**Branch**: 
**PR**: 

## Goal
Ogni punto che oggi legge `docs/SESSION_HANDOFF.md` direttamente (con `awk`, `grep`, `cat`, `head`, `tail` o una menzione prescrittiva del file) passa a `handoff.sh facts` / `show` / `recent` / `grep`, cioè al compositore introdotto in PI-14. **Nessuna chiamata di scrittura cambia**: `log` e `fact` restano quelli di oggi, scrivono ancora nel vecchio file. Questo task è l'ordine «prima i lettori, poi gli scrittori» del §9.1 del TAD: finché le scritture non passano ai frammenti (PI-16), tutto quello che il compositore mostra viene ancora dal vecchio file, quindi nessuna installazione intermedia lascia un lettore cieco.

## Acceptance criteria
- [ ] AC1 — Given il repo dopo il task, when `git grep -nE "(^|[^a-z])(awk|grep|cat|head|tail) .*SESSION_HANDOFF|-f docs/SESSION_HANDOFF|facts of .?docs/SESSION_HANDOFF|SESSION_HANDOFF\.md.? facts" -- ':!docs' ':!tech-analysis' ':!tasks' ':!bin/handoff.sh' ':!bin/handoff.test.sh'`, then l'output è vuoto. Oggi la stessa espressione restituisce 11 righe, cioè gli 11 punti elencati nel campo Files sopra (misurato): è la mutazione dell'AC.
- [ ] AC2 — Given la memoria di questo repo, when `bash bin/status.sh`, then le righe `handoff facts:` e `handoff log (last 4):` sono identiche a quelle stampate su `main` prima del task.
- [ ] AC3 — Given un repo senza memoria (né vecchio file né frammenti), when `bash bin/status.sh`, then stampa una riga «handoff: nessuna memoria» ed esce con 0, senza creare file.

## Tests expected
- Il comando `git grep` dell'AC1 va eseguito prima e dopo la modifica e i due conteggi (11 → 0) vanno riportati nel corpo della PR (§11.3 del TAD): è la mutazione stessa, non serve costruirne un'altra.
- Un test in `bin/status.test.sh` se esiste, altrimenti una verifica manuale documentata nella PR, per AC2 e AC3 (esecuzione diretta di `bin/status.sh` su una copia della memoria reale e su un repo vuoto).
- Integration/E2E: non servono, il criterio è testuale (quali comandi vengono invocati) e di output di uno script, non un comportamento di merge.

## Notes
- Gli otto percorsi in Files sono quelli elencati nel §12 del TAD per questo task; ciascuno contiene una o più righe da riscrivere per invocare `handoff.sh facts` / `show` / `recent` / `grep` invece di leggere il file a mano. Non cambiare il numero di riga come riferimento assoluto: verifica il contenuto attuale di ciascun file prima di modificarlo, i numeri possono essere leggermente scaduti rispetto all'ultima revisione del TAD.
- L'AC1 esclude deliberatamente `docs/`, `tech-analysis/`, `tasks/`, `bin/handoff.sh` e `bin/handoff.test.sh`: quei percorsi possono legittimamente nominare `SESSION_HANDOFF.md` (è la sorgente congelata, descritta lì) senza che sia un lettore da correggere.
- Non toccare `reviewer.md:95-96`, `qa-engineer.md:94`, `deps/SKILL.md:17`, `implementing-common.md:101,132,133`: sono chiamate di sola scrittura (`log`/`fact`), fuori scope per questo task e per PI-16 le lascia esplicitamente invariate il TAD.
- I lettori fuori da questo repo (istruzioni globali della sessione principale, prompt di lancio dei progetti) non sono un AC di questo task: li aggiorna l'orchestratore quando `handoff.sh where` esiste ed esce con 0 (dopo PI-16), non prima — vedi §9.2 del TAD, riga «Lettori fuori da questo repo».
