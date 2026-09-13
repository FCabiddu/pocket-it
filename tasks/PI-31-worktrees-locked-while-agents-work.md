# PI-31 — I worktree degli agenti non sono bloccati mentre sono in uso

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: high
**Depends on**: PI-22
**Wave**: 1
**Files**: bin/worktree.sh, bin/worktree.test.sh, bin/cleanup-merged.sh, bin/cleanup-merged.test.sh
**TAD**: none — segui le convenzioni degli altri script in `bin/`
**Contract**: none
**Branch**: 
**PR**: 

## Goal
Lo script di pulizia ha cancellato il worktree di un agente che stava lavorando, perché ha scambiato un branch senza commit propri per un branch già mergiato. PI-22 corregge quel criterio.

Resta però una seconda domanda: **perché lo script ha potuto toccare un worktree in uso?** Lo script di pulizia gira dopo ogni merge, anche mentre altri agenti lavorano, e l'unica cosa che lo ferma è il proprio giudizio su «mergiato o no». Se quel giudizio sbaglia in un caso non ancora previsto, il lavoro in corso sparisce di nuovo. Un solo criterio che decide se cancellare lavoro è un punto singolo di rottura.

Git offre già un meccanismo fatto apposta: un worktree **bloccato** non viene rimosso dalle operazioni ordinarie, e lo script di pulizia **rispetta già** i worktree bloccati. Manca solo che `worktree.sh`, quando crea il worktree di un agente, lo blocchi.

## Acceptance criteria
- [ ] AC1 — Dato un worktree creato da `worktree.sh`, quando la creazione finisce, allora il worktree è bloccato, con un motivo che nomina il branch e la data.
- [ ] AC2 — Dato un worktree bloccato il cui branch **non** risulta mergiato, quando la pulizia gira, allora resta, qualunque cosa decida il criterio sui commit propri.
- [ ] AC3 — Dato un worktree bloccato il cui branch risulta mergiato con certezza, cioè con una PR mergiata che contiene la sua punta, quando la pulizia gira, allora viene sbloccato e rimosso: i blocchi non devono accumularsi all'infinito.
- [ ] AC4 — Dato un worktree bloccato che la pulizia conserva, quando la pulizia riporta l'esito, allora dice che è bloccato e perché.
- [ ] AC5 — Le due protezioni sono indipendenti: rompendo il criterio sui commit propri di PI-22, un worktree bloccato non mergiato resta comunque.

## Tests expected
Un caso per criterio nelle suite dei due script, su un repository di prova. Prova per mutazione AC5: con il criterio di PI-22 disattivato, il caso di AC2 deve restare verde, perché lo protegge il blocco. Integration/E2E: non servono.

## Notes
Dipende da PI-22 perché tocca lo stesso script: va fatto dopo, non insieme.

Il principio del task è la difesa in profondità: una sola regola che decide se distruggere lavoro deve avere almeno una seconda protezione indipendente.

Questo repo è pubblico: niente dei progetti su cui gira la pipeline.
