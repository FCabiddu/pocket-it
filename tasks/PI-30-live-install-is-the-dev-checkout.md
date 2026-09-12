# PI-30 — La copia installata della pipeline è la stessa in cui si sviluppa

**Status**: In Progress
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: M
**Budget**: 200
**Risk**: high
**Depends on**: none
**Wave**: 1
**Files**: bin/install-live.sh (nuovo), bin/install-live.test.sh (nuovo), README.md
**TAD**: none
**Contract**: none
**Branch**: task/pi-30-separate-live-install
**PR**: 

## Goal
Gli hook, gli skill e gli agenti che ogni sessione usa vengono letti **direttamente dal checkout principale del repository**, lo stesso in cui gli agenti di pocket-it sviluppano: l'hook di sicurezza sui comandi è configurato con il percorso del file dentro quel checkout, e la cartella degli agenti punta allo stesso albero.

Questo significa che **qualunque scrittura accidentale nel checkout principale cambia all'istante il comportamento di tutte le sessioni**, prima di qualsiasi review.

È successo davvero. Uno script di pulizia ha cancellato il worktree di un developer mentre lavorava su una guardia di sicurezza. La directory corrente dell'agente è ricaduta sul checkout principale, e l'agente ha continuato lì a modificare il file dell'hook. Per alcuni minuti una versione non revisionata e a metà di una guardia di sicurezza è stata **attiva per ogni sessione**, finché non è stata notata e ripristinata.

La causa immediata, lo script che cancellava il worktree, si corregge in PI-22. Ma anche con quella chiusa resta la causa strutturale: basta un qualunque altro errore che porti un agente a scrivere nel checkout principale, e il danno arriva subito in produzione. La copia che gira e la copia che si modifica devono essere due cose diverse.

## Acceptance criteria
- [ ] AC1 — Esiste uno script che crea e aggiorna una copia installata separata, ottenuta **solo** dalla versione pubblicata del ramo base, mai dal checkout di sviluppo.
- [ ] AC2 — Dato uno stato in cui il checkout di sviluppo ha modifiche non committate a hook, skill o agenti, quando si aggiorna la copia installata, allora quelle modifiche non vi arrivano.
- [ ] AC3 — Dato un aggiornamento del ramo base remoto, quando lo script gira, allora la copia installata si allinea con un avanzamento semplice; se la copia installata ha modifiche locali o non è un avanzamento, lo script si rifiuta e lo dice, invece di sovrascrivere.
- [ ] AC4 — Il README spiega come passare hook, skill e agenti alla copia installata, e come tornare indietro, con i comandi esatti.
- [ ] AC5 — Lo script dice quando va lanciato: dopo ogni merge nel ramo base di pocket-it, perché le correzioni revisionate entrino in uso.

## Tests expected
Un caso per AC1, AC2 e AC3 in `bin/install-live.test.sh`, su un repository di prova con un remote locale. Prova per mutazione AC2: facendo copiare lo script dal checkout di sviluppo invece che dal remote, il suo caso deve diventare rosso. AC4 e AC5 si verificano leggendo. Integration/E2E: non servono.

## Notes
Lo script non modifica le impostazioni personali dell'utente, che stanno fuori dal repository: il passaggio della configurazione degli hook alla copia installata lo applica l'orchestratore dopo la review, con la procedura del README e un backup. Per questo AC4 deve essere eseguibile alla lettera.

Rischio alto: se la copia installata restasse indietro o si rompesse, tutti gli hook di tutte le sessioni smetterebbero di funzionare. Lo script deve fallire rumorosamente e lasciare intatta l'ultima copia funzionante.

Questo repo è pubblico: niente dei progetti su cui gira la pipeline, né percorsi personali. Nel README usa segnaposto.
