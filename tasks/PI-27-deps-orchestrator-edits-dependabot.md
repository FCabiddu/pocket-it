# PI-27 — Lo skill `deps` fa modificare all'orchestratore un file di configurazione

**Status**: Done
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: XS
**Budget**: 60
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: .claude/skills/deps/SKILL.md
**TAD**: none
**Contract**: none
**Branch**: task/pi-27-deps-rollup-owns-dependabot
**PR**: https://github.com/FCabiddu/pocket-it/pull/51

## Goal
Lo skill `.claude/skills/deps/SKILL.md`, alla riga 20, descrive la modifica a `dependabot.yml` come una riga che l'utente può approvare, e in un'altra versione come una modifica fatta direttamente dall'orchestratore. Entrambe le strade sono sbagliate:

- l'orchestratore non implementa: ogni modifica a file passa da un agente con review;
- la scelta di come raggruppare gli aggiornamenti delle dipendenze riguarda il funzionamento della pipeline, non una decisione di business: non va presentata all'utente da approvare.

La modifica a `dependabot.yml` appartiene al task di rollup delle dipendenze che lo skill già crea, con il file nell'elenco dei file del task e un criterio di accettazione che la verifica.

## Acceptance criteria
- [x] AC1 — Dato lo skill `deps`, quando descrive la modifica a `dependabot.yml`, allora la attribuisce al task di rollup, eseguito da un developer e rivisto.
- [x] AC2 — Dato lo stesso skill, quando lo si rilegge per intero, allora non presenta quella scelta all'utente da approvare e non la fa eseguire all'orchestratore.
- [x] AC3 — Dato il modello di task di rollup che lo skill produce, quando lo si legge, allora include `dependabot.yml` fra i file e un criterio che ne verifica la modifica.

## Tests expected
Nessun test automatico: è prosa. Rileggi lo skill per intero. Integration/E2E: non servono.

## Notes
Questo repo è pubblico: niente dei progetti su cui gira la pipeline.

Secondo giro (review): AC3, spostando la modifica di `dependabot.yml` dentro il task di rollup, non aveva aggiornato l'elenco dei file ammessi — contraddiceva la clausola che chiede al developer di modificare proprio quel file e AC4 che ne verifica il contenuto. Corretto aggiungendo `.github/dependabot.yml` all'elenco di AC3, condizionato alla stessa clausola di AC4 ("only when this task's condition triggered its edit").
