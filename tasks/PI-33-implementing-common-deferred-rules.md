# PI-33 — Cinque regole per chi implementa, rinviate finché il file era occupato

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: .claude/agents/shared/implementing-common.md
**TAD**: none
**Contract**: none
**Branch**: 
**PR**: 

## Goal
Tre regole per gli agenti che implementano sono emerse da incidenti reali e sono state rinviate perché `shared/implementing-common.md` era in modifica da PI-22, ora mergiata. Vanno scritte lì perché è il file che developer e qa-engineer leggono all'avvio.

1. **Una verifica non deve reintrodurre il difetto che verifica.** Una PR che toglieva un nome privato da un repository pubblico è tornata indietro perché il report conteneva quello stesso nome dentro il comando usato per verificarne la rimozione. Quando si verifica l'assenza di un contenuto che non deve comparire, la verifica si descrive per effetto, senza riportare quel contenuto.
2. **Una migrazione o una backfill non si applica mai a un database reale prima di review e merge.** Un task ha applicato una backfill al database reale del progetto prima della review, lasciandolo in uno stato che il codice in produzione gestiva male: aprire una delle righe create dal codice di main ne distruggeva una parte. Si prova su una copia; sul database reale la applica chi mergia, dopo il merge.
3. **I file cambiati si calcolano rispetto al ramo base remoto.** Dopo PI-22 la §6 crea il branch da `origin/$BASE` senza aggiornare la base locale, ma la §4 calcola ancora i file cambiati rispetto alla base locale. Se la base locale è vecchia l'elenco si allarga, se non esiste resta vuoto e nessun test mirato gira. Va allineata a `origin/$BASE`.

4. **Nessuna scrittura su un database condiviso, nemmeno per provare e nemmeno in review.** Un reviewer ha eseguito cancellazioni e inserimenti sul database reale di un progetto dentro una transazione poi annullata. Le prove sui dati si fanno su una copia o su un database locale usa e getta.
5. **Un test che verifica l'assenza di qualcosa deve prima provare di aver letto l'input.** Più volte in una giornata un test è rimasto verde con il difetto presente perché asseriva un'assenza: nessun errore, nessun elemento, nessun duplicato. Un controllo che non ha letto niente non trova niente. Il test deve includere un caso positivo che fallisce se l'input non viene letto.

## Acceptance criteria
- [ ] AC1 — Dato il file, quando lo si legge, allora contiene la regola 1, con il motivo in una riga.
- [ ] AC2 — Dato il file, quando lo si legge, allora contiene la regola 2, e dice chi applica la migrazione sul database reale e quando.
- [ ] AC3 — Data la §4, quando calcola i file cambiati, allora usa `origin/$BASE`, coerente con la §6.
- [ ] AC4 — Dato il file, quando lo si legge, allora contiene le regole 4 e 5, ciascuna con il motivo in una riga.
- [ ] AC5 — Dato il file intero, quando lo si rilegge, allora nessuna delle tre regole contraddice un'altra sezione.

## Tests expected
Nessun test automatico: è prosa. Rileggi il file intero. Integration/E2E: non servono.

## Notes
Il file è letto all'avvio da ogni agente che implementa: ogni riga in più ha un costo di lettura. Scrivi le regole corte.

Questo repo è pubblico: niente dei progetti su cui gira la pipeline. Gli incidenti vanno descritti in forma generica, come qui.
