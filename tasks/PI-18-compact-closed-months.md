# PI-18 — Compattazione dei mesi chiusi

**Status**: Todo
**Label**: DevOps
**Epic**: handoff
**Story**: handoff
**Priority**: Should
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: PI-17
**Wave**: 5
**Files**: bin/handoff.sh, bin/handoff.test.sh, .claude/agents/retro.md
**TAD**: tech-analysis/HANDOFF_MEMORY_TECH_ANALYSIS.md (§4.4, §12 PI-18, §13 DA-2)
**Contract**: none
**Branch**: 
**PR**: 

## Goal
Un comando `handoff.sh compact --before AAAA-MM`, eseguito dal retro, piega i frammenti di un mese già chiuso in un unico file `docs/handoff/archive/{AAAA-MM}-{stamp}-{rand}.md`, con una sezione `### {nome del frammento d'origine}` per ciascun frammento piegato e le sue righe identiche all'originale (§4.2, §4.4 del TAD). Compatta **solo** i frammenti già presenti sul ramo base: un frammento ancora solo su un ramo aperto non viene toccato, e resta visibile dopo il merge. Riduce il numero di file senza spostare né perdere una riga: la guardia di PI-17 (AC3) copre già ogni caso di spostamento generato da questo comando.

## Acceptance criteria
- [ ] AC1 — Given frammenti di un mese chiuso, alcuni presenti sul ramo base e altri solo su un ramo aperto, when `handoff.sh compact --before AAAA-MM` sul ramo del retro, then vengono piegati solo i frammenti del ramo base, e i file del ramo aperto non sono toccati (dopo il merge restano visibili).
- [ ] AC2 — Given la memoria prima e dopo `compact`, when si confrontano `recent --all` e `facts`, then il multinsieme del log e l'insieme dei fatti sono uguali.
- [ ] AC3 — Given due `compact` concorrenti su due rami con insiemi sovrapposti, when si fondono, then 0 conflitti e nessuna riga duplicata nella vista, grazie all'identità per nome del §4.3 del TAD.
- [ ] AC4 — Given un `compact` di un frammento e uno di più frammenti, when `doctor.sh`, then nessun errore. Ogni frammento piegato arriva alla guardia come `D` (con `--no-renames`, anche quando git lo vedrebbe come `R` di qualunque percentuale), ed è coperto da una sezione `### {basename}` con lo stesso multinsieme (regola di PI-17 AC3). Given un `compact` mutato che scrive la sezione con una riga in meno, then `doctor.sh` dà errore sul frammento piegato.

## Tests expected
Un caso per criterio in `bin/handoff.test.sh`, con repo git temporaneo per AC1 e AC3 (comportamento di merge). AC4 riusa/estende i casi `compact` già scritti in `bin/doctor.test.sh` da PI-17 (questo task fornisce finalmente il comando reale al posto dei frammenti costruiti a mano). Integration/E2E: non servono.

## Notes
- **DA-2 (decisione aperta, raccomandazione approvata nel TAD, non bloccante):** eseguire questo task **dopo il primo mese chiuso con frammenti**, non prima. Senza compattazione non si perde nulla: si guadagna solo ordine nella cartella (§10 del TAD: ~300 file/mese prima della compattazione). Il task è pronto in wave 5 (dipende da PI-17), ma chi orchestra la board può ritardarne il lancio finché non esiste almeno un mese chiuso da comprimere; non è un blocco tecnico, è una scelta di sequenza.
- Aggiorna `.claude/agents/retro.md` perché il retro usi `compact` invece di qualunque potatura manuale: l'unico modo per il retro di ridurre righe visibili resta `retract` (fatti), e ora anche `compact` (solo riduzione del numero di file, mai delle righe) per i mesi chiusi.
- Due compattazioni concorrenti cancellano gli stessi frammenti originali: è un delete/delete, che git fonde pulito da solo (§4.4 del TAD) — non serve altro codice difensivo oltre a lasciare che il merge lo faccia.
