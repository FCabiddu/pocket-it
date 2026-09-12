# PI-9 — `handoff.sh` non dice su quale repo ha scritto

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: XS
**Budget**: 60
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/handoff.sh, bin/handoff.test.sh
**TAD**: none — segui le convenzioni degli altri script in `bin/`
**Contract**: none
**Branch**: 
**PR**: 

## Goal
`bin/handoff.sh` risolve il repo su cui scrivere da `git rev-parse --show-toplevel`, cioè dalla directory corrente (riga 10), e poi conferma con un laconico `handoff: logged`.

Un agente che lavora in un worktree non ha la directory corrente garantita: si azzera fra un comando e l'altro, quindi basta dimenticare un `cd` perché lo script scriva nel checkout condiviso invece che nel worktree. È successo davvero: la scrittura è finita nell'albero sbagliato, ha sporcato file che appartenevano a un altro lavoro in corso e se ne è accorto solo chi, molto più tardi, ha visto uno stato di task cambiato senza spiegazione.

Lo script si è comportato come documentato, quindi qui non si cambia la risoluzione del repo. Si cambia il fatto che l'operazione sia invisibile: se `handoff: logged` avesse detto *dove*, l'errore sarebbe saltato all'occhio subito, nello stesso output.

## Acceptance criteria
- [ ] AC1 — Dato un qualsiasi `handoff.sh log` andato a buon fine, quando leggo l'output, allora contiene il percorso del file scritto.
- [ ] AC2 — Dato un qualsiasi `handoff.sh fact` andato a buon fine, quando leggo l'output, allora contiene il percorso del file scritto.
- [ ] AC3 — Dato uno script chiamante che ridirige l'output (`>/dev/null`), quando lo esegue, allora continua a funzionare e il codice di uscita non cambia: l'aggiunta è sull'output, non sul contratto.

## Tests expected
Un caso per criterio in `bin/handoff.test.sh`. Per AC1 e AC2 basta asserire che l'output contenga il percorso atteso del file, non la stringa fissa. Integration/E2E: non servono.

## Notes
`ROOT` è calcolato alla riga 10 di `bin/handoff.sh` e il file alla riga 11. I messaggi di conferma da estendere sono quelli dei due sottocomandi `log` e `fact`.

Attenzione a chi già chiama lo script: diversi punti della pipeline lo invocano con l'output ridiretto, e i suoi codici di uscita sono significativi (i fatti rifiutano con `exit 3` al tetto). Nessuno dei due va toccato.
