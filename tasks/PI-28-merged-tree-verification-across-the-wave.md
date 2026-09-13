# PI-28 — Le PR di una stessa wave non vengono mai testate sovrapposte

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: PI-26
**Wave**: 1
**Files**: .claude/skills/run-wave/SKILL.md, .claude/agents/reviewer.md
**TAD**: none
**Contract**: none
**Branch**: 
**PR**: 

## Goal
In un progetto reale, in una sola giornata, **tre volte** due PR verdi sul proprio branch hanno dato rosso appena mergiate insieme, **senza che git segnalasse alcun conflitto**: un helper di test condiviso diventato asincrono in una PR e chiamato come sincrono nell'altra; asserzioni su stringhe in una lingua dopo il cambio della lingua predefinita in un'altra. Uno dei test non diventava nemmeno rosso, passava a vuoto su un DOM vuoto.

Oggi nessuna regola della pipeline prescrive di testare l'albero con le PR di una wave sovrapposte. Il reviewer lo ha fatto in quel caso per iniziativa sua. Un primo tentativo di scriverlo in `reviewer.md` è stato tolto perché aveva due difetti:

- **copriva solo il gruppo di review**, e da quando i reviewer lavorano a gruppi di tre PR, due PR della stessa wave in gruppi diversi non finiscono mai sullo stesso albero: che è proprio il caso della base che si muove sotto un branch;
- **contraddiceva una regola vicina**, «mai la suite completa», senza dichiararsi un'eccezione.

## Acceptance criteria
- [ ] AC1 — Data una wave con più PR destinate alla stessa base, quando le review sono finite e prima del primo merge, allora `run-wave` prescrive un passaggio che costruisce l'albero con **tutte** le PR approvate sovrapposte e ci lancia i test, indipendentemente da come erano divise nei gruppi di review.
- [ ] AC2 — Dato quel passaggio, quando lo si legge, allora dice chi lo esegue, cosa succede se l'albero sovrapposto è rosso, e che la correzione va nella PR che entra per seconda.
- [ ] AC3 — Dato `reviewer.md`, quando descrive la regola «mai la suite completa», allora dichiara esplicitamente l'eccezione per l'albero sovrapposto e perché.
- [ ] AC4 — Data una wave con una sola PR, quando si arriva al merge, allora il passaggio non si applica e non costa nulla.

## Tests expected
Nessun test automatico: sono file di prosa. Verifica rileggendo i due file per intero e controllando che il nuovo passaggio non contraddica i gruppi di review da tre né la regola sulla suite. Integration/E2E: non servono.

## Notes
Dipende da PI-26 perché tocca lo stesso skill: va fatto dopo, non insieme.

Questo repo è pubblico: niente dei progetti su cui gira la pipeline.
