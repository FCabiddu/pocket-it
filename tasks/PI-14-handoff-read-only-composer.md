# PI-14 — Compositore in sola lettura per la memoria della pipeline

**Status**: Todo
**Label**: DevOps
**Epic**: handoff
**Story**: handoff
**Priority**: Must
**Estimate**: M
**Budget**: 200
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/handoff.sh, bin/handoff.test.sh
**TAD**: tech-analysis/HANDOFF_MEMORY_TECH_ANALYSIS.md (§2.1, §2.4 ADR-2, §4.1–§4.4, §5.1–§5.3, §8.1, §11.1–§11.3, §12 PI-14)
**Contract**: none
**Branch**: 
**PR**: 

## Goal
`handoff.sh` guadagna un compositore puro per i comandi di lettura: `facts`, `show`, `recent N` / `recent --all` e `grep REGEX`. Oggi queste letture leggono solo `docs/SESSION_HANDOFF.md` (e il suo archivio) con `awk`; da questo task leggono attraverso il compositore, che unisce le sorgenti congelate (`docs/SESSION_HANDOFF.md`, `docs/SESSION_HANDOFF_ARCHIVE.md`, se presenti) con eventuali frammenti sotto `docs/handoff/**` nel formato descritto al §4.2 del TAD, applicando l'ordinamento, la deduplicazione e i ritiri del §4.3. **Additivo**: `log` e `fact` restano quelli di oggi e continuano a scrivere solo il vecchio file — questo task non tocca le scritture, solo le letture. Non esistono ancora frammenti scritti dalla pipeline reale (arriveranno con PI-16): questo task implementa il compositore e lo prova con frammenti di test costruiti a mano, così il meccanismo è pronto prima che qualcosa lo popoli.

## Acceptance criteria
- [ ] AC1 — Given la copia di `docs/SESSION_HANDOFF.md` di questo repo, senza frammenti, when `handoff.sh facts`, then l'output è byte-identico a `awk '/^## Fatti/{f=1;next} /^## /{f=0} f && /^- /' docs/SESSION_HANDOFF.md`.
- [ ] AC2 — Given la stessa copia più `SESSION_HANDOFF_ARCHIVE.md`, when `handoff.sh recent --all`, then il multinsieme delle righe è uguale al multinsieme delle righe `- ` di Log più quelle dell'archivio (conteggio stampato nella PR).
- [ ] AC3 — Given frammenti di prova (`## Log`, `## Fatti`, `## Ritirati`, due righe di log identiche in due frammenti, una sezione d'archivio con lo stesso nome di un frammento), when `recent --all` e `facts`, then le due righe identiche compaiono due volte, la copia dichiarata una volta sola, il fatto ritirato non compare, e lo stesso fatto riscritto dopo il ritiro compare.
- [ ] AC4 — Given un repo pulito con o senza il vecchio file, when si eseguono `facts`, `show`, `recent 5`, `grep X`, then `git status --porcelain` è identico prima e dopo e nessun file viene creato.
- [ ] AC5 — Given una riga congelata datata 2026-09-10 e frammenti del 2026-09-11 e 2026-09-12, when `recent --all`, then l'ordine è 12, 11, 10, e a parità di giorno i frammenti vengono prima delle righe congelate.

## Tests expected
Un caso per criterio in `bin/handoff.test.sh`, nello stile dei casi già presenti (repo git temporaneo per caso, §11.2 del TAD). AC1 e AC2 vanno provati anche sulla copia della memoria reale di questo repo (§11.3: conteggi prima/dopo nel corpo della PR). Integration/E2E: non servono, il criterio centrale di questo task è il formato e l'ordinamento della composizione, provabile a livello di script.

## Notes
- Il TAD classifica il rischio di questo task come «med» (tocca il percorso di avvio di ogni agente), abbassato a `low` per la board perché è puramente additivo: nessuna scrittura cambia comportamento, e un errore nella composizione è visibile subito (byte-identità con l'`awk` di oggi, AC1).
- Formato del frammento: §4.2 del TAD. Sezioni ammesse `## Log`, `## Fatti`, `## Ritirati`; una voce di ritiro è `- ~ {sha1 del testo del fatto, primi 12 caratteri esadecimali}`.
- Ordinamento e deduplicazione: tabella §4.3 del TAD, da seguire esattamente (log mai deduplicato/verificato a multinsieme; fatti deduplicati per testo, verificati a insieme; copie dichiarate identificate per nome, mai per contenuto; un ritiro nasconde ogni fatto con hash coincidente in una sorgente più vecchia del ritiro).
- `retract` come comando di scrittura arriva con PI-16; qui serve solo che il compositore sappia interpretare una sezione `## Ritirati` già presente in un frammento di test.
- Nessuna delle quattro letture (`facts`, `show`, `recent`, `grep`) deve scrivere alcunché (ADR-2 del TAD) — è l'AC4.
