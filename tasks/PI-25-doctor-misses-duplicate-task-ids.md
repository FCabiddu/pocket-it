# PI-25 — `doctor.sh` non si accorge di due task con lo stesso id

**Status**: In Progress
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: XS
**Budget**: 60
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/doctor.sh, bin/doctor.test.sh
**TAD**: none — segui le convenzioni degli altri script in `bin/`
**Contract**: none
**Branch**: task/pi-25-doctor-duplicate-ids
**PR**: 

## Goal
Due file di task con lo stesso id si mascherano a vicenda in `next-wave.sh`: uno dei due sparisce dalla board senza che nessuno se ne accorga. È già successo più volte, in questo repo e in un progetto, e ogni volta la contromisura è stata una regola scritta per chi crea i task: «controlla l'elenco prima di assegnare un numero». La regola non basta, perché si affida a chi la legge. L'ultima volta un task duplicato è rimasto sulla board per giorni con uno stato che contraddiceva il lavoro già mergiato.

`bin/doctor.sh` gira prima di ogni lancio, e i suoi errori fermano il lancio. È il posto giusto per un controllo meccanico che non dipende dalla memoria di nessuno.

## Acceptance criteria
- [ ] AC1 — Data una board con due file di task che dichiarano lo stesso id, quando `doctor.sh` gira, allora segnala un **errore**, non un avviso, con l'id e i due percorsi.
- [ ] AC2 — Data una board senza id duplicati, quando `doctor.sh` gira, allora il controllo non produce output.
- [ ] AC3 — Dati id che differiscono solo per il segmento numerico, per esempio `X-9` e `X-19`, quando `doctor.sh` gira, allora non vengono scambiati per uguali.
- [ ] AC4 — Dati i file di riepilogo di epiche e storie, che lo script già distingue dai task, quando `doctor.sh` gira, allora non vengono contati come duplicati.

## Tests expected
Un caso per criterio in `bin/doctor.test.sh`. Prova per mutazione AC1: togliendo il controllo, il suo caso deve diventare rosso. Integration/E2E: non servono.

## Notes
L'id va letto da dove lo legge `next-wave.sh`, così i due script sono d'accordo su cosa conta come stesso id. Se oggi lo ricavano in modi diversi, allineali e dillo nel report.

Questo repo è pubblico: niente dei progetti su cui gira la pipeline.
