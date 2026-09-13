# PI-29 — Nessuno si accorge se il ramo base viene riscritto o cancellato

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: PI-25
**Wave**: 1
**Files**: bin/doctor.sh, bin/doctor.test.sh
**TAD**: none — segui le convenzioni degli altri script in `bin/`
**Contract**: none
**Branch**: 
**PR**: 

## Goal
La guardia sui push ferma gli agenti quando, per errore, scrivono verso il ramo base in una forma normale. Non può fermare tutto: una lista di divieti sul testo di una shell non copre ogni modo di scrivere lo stesso comando, e lo si è verificato in più giri di review. La protezione lato server, quella che rifiuta la riscrittura e la cancellazione del ramo base qualunque sia il comando, non è disponibile per tutti i repository: sui repository privati del piano gratuito la piattaforma non la offre.

Per quei repository resta scoperto un caso: il ramo base remoto viene riscritto con un force-push, o cancellato, e nessuno se ne accorge. Il danno è recuperabile, perché ogni clone e ogni worktree conserva la storia, ma solo se ce ne si accorge presto, prima che quei cloni vengano aggiornati o ripuliti.

`bin/doctor.sh` gira prima di ogni lancio. È il posto giusto per **accorgersene**: non impedisce il danno, lo rende visibile subito, finché è ancora recuperabile.

## Acceptance criteria
- [ ] AC1 — Dato un repository in cui il ramo base remoto è avanzato normalmente dall'ultima esecuzione, quando `doctor.sh` gira, allora non segnala nulla.
- [ ] AC2 — Dato un repository in cui il ramo base remoto non contiene più il commit visto all'ultima esecuzione, cioè è stato riscritto, quando `doctor.sh` gira, allora segnala un **errore** con il commit perso, così da poterlo ripristinare.
- [ ] AC3 — Dato un repository in cui il ramo base remoto non esiste più, quando `doctor.sh` gira, allora segnala un errore.
- [ ] AC4 — Dato un repository alla prima esecuzione, senza un commit già visto, quando `doctor.sh` gira, allora registra il commit corrente e non segnala nulla.
- [ ] AC5 — Il commit già visto è conservato in un posto che non viene committato e che ogni worktree dello stesso repository condivide, così una esecuzione da un worktree vede ciò che ha registrato un'altra.
- [ ] AC6 — Il messaggio di errore dice come recuperare il ramo, con il commit da cui ripartire.

## Tests expected
Un caso per criterio in `bin/doctor.test.sh`, su un repository di prova con un remote locale su cui eseguire davvero un force-push e una cancellazione. Prova per mutazione AC2: togliendo il controllo, il suo caso deve diventare rosso. Integration/E2E: non servono.

## Notes
Dipende da PI-25 perché tocca lo stesso script: va fatto dopo, non insieme.

Per AC5 la directory comune del repository, quella restituita da `git rev-parse --git-common-dir`, è condivisa da tutti i worktree e non viene committata.

Il controllo deve richiedere un aggiornamento dei riferimenti remoti per essere affidabile; se il fetch non è possibile, per esempio senza rete, deve dirlo e non segnalare un falso errore.

Questo repo è pubblico: niente dei progetti su cui gira la pipeline.
