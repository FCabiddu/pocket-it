# PI-8 — `handoff.sh log` scarta in silenzio le righe più vecchie

**Status**: Done
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/handoff.sh, bin/handoff.test.sh
**TAD**: none — segui le convenzioni degli altri script in `bin/`
**Contract**: none
**Branch**: task/pi-8-handoff-log-rotation
**PR**: https://github.com/FCabiddu/pocket-it/pull/30

## Goal
`bin/handoff.sh log` tronca il log a 40 righe con `lines=lines[:40]` (riga 38) e **butta via** quelle in eccesso: non finiscono da nessuna parte e non sono più recuperabili se il file è già stato committato con il taglio.

Non è un problema teorico. In una sessione recente il taglio ha eliminato due righe di log scritte il giorno prima, e me ne sono accorto solo confrontando a mano il file con la sua versione precedente. Il file si chiama «memoria della pipeline» ed è la prima cosa che ogni agente legge all'avvio: una memoria che cancella in silenzio è peggio di una memoria corta, perché nessuno sa cosa manca.

Il taglio è anche asimmetrico rispetto ai fatti. Per i fatti, PI-2 e PI-5 hanno già deciso la regola giusta: al raggiungimento del tetto lo script **rifiuta** con `exit 3` e non scarta nulla. Il log fa l'opposto, e senza dirlo.

Comportamento voluto: le righe che escono dalle ultime 40 vengono **spostate in un archivio**, non eliminate. Il log resta corto da leggere, ma nessuna riga sparisce. Lo script deve anche dire quante righe ha archiviato, così l'operazione è visibile a chi la esegue.

## Acceptance criteria
- [ ] AC1 — Dato un log con 40 righe, quando aggiungo una riga con `handoff.sh log`, allora la riga più vecchia si trova nel file di archivio e non è stata persa: il totale delle righe (log + archivio) cresce di uno.
- [ ] AC2 — Dato un log con 40 righe, quando aggiungo una riga, allora la sezione `## Log` del file principale ne contiene ancora 40 e la nuova è in cima.
- [ ] AC3 — Dato un archivio che esiste già con righe dentro, quando una nuova rotazione lo tocca, allora le righe già archiviate sono ancora tutte lì: l'archivio si accoda, non si sovrascrive.
- [ ] AC4 — Dato un log sotto le 40 righe, quando aggiungo una riga, allora nessun archivio viene creato e nessuna riga viene spostata.
- [ ] AC5 — Quando una rotazione sposta N righe, allora lo script lo dice sul suo output, con N.

## Tests expected
Un caso per criterio in `bin/handoff.test.sh`, nello stile dei casi già presenti. Prova per mutazione AC1: rimettendo `lines=lines[:40]` senza archiviazione, il test di AC1 deve diventare rosso. Integration/E2E: non servono.

## Notes
La rotazione sta nello script Python incorporato nel sottocomando `log`, righe 33-39 di `bin/handoff.sh`. L'archivio va scelto coerente con il resto del repo: il file principale è `$ROOT/docs/SESSION_HANDOFF.md`, quindi un `$ROOT/docs/SESSION_HANDOFF_ARCHIVE.md` sta nella stessa famiglia — ma se nel repo esiste già una convenzione di archivio, usa quella invece di inventarne una nuova.

Il numero 40 resta 40: questo task non cambia la soglia, cambia solo la destinazione delle righe che la superano.
