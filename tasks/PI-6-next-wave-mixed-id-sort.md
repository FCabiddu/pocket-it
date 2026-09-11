# PI-6 — next-wave.sh va in TypeError con id di task alfanumerici

**Status**: Done
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: XS
**Budget**: 60
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/next-wave.sh, bin/next-wave.test.sh
**TAD**: none — segui le convenzioni degli altri script in `bin/`
**Contract**: none
**Branch**: task/pi-6-next-wave-mixed-id-sort
**PR**: https://github.com/FCabiddu/pocket-it/pull/24

## Goal
`bin/next-wave.sh` si interrompe con `TypeError: '<' not supported between instances of 'int' and 'str'` e non produce alcun output quando nella board convivono id di task interamente numerici e id con una parte alfabetica.

La causa è la chiave di ordinamento nello script Python incorporato:

```python
sorted(status, key=lambda s: [int(x) if x.isdigit() else x for x in re.split(r"[.\-]", s)])
```

Su `T-28.5.5` produce `["T", 28, 5, 5]`, su `T-BUG-1` produce `["T", "BUG", 1]`. Confrontando i due elenchi Python arriva a `28 < "BUG"` e solleva l'eccezione.

È successo l'11/09/2026 su tavern-forge, dove il qa-engineer ha aperto cinque task di bug chiamati `T-BUG-1`…`T-BUG-5` accanto ai `T-28.x.y` dell'epica in corso. Lo script serve all'avvio di ogni sessione e a ogni wave per decidere cosa è pronto, quindi finché quei task esistono la pipeline è cieca.

La chiave va resa **totale**, cioè confrontabile fra segmenti numerici e alfabetici: per esempio `(0, int(x), "")` per i segmenti numerici e `(1, 0, x)` per quelli alfabetici, così i numeri restano ordinati fra loro, le parole fra loro, e i due gruppi non si confrontano mai direttamente. L'ordine fra id puramente numerici non deve cambiare.

## Acceptance criteria
- [ ] AC1 — Dato un insieme di task che contiene sia `T-28.5.5` sia `T-BUG-1`, quando si lancia `bin/next-wave.sh`, allora esce senza eccezioni e stampa la riga di riepilogo e le righe JSON dei task pronti.
- [ ] AC2 — Dato un insieme di soli id numerici (`T-1.2.3`, `T-1.10.1`, `T-2.1.1`), quando si lancia lo script, allora l'ordine è identico a quello odierno: `1.2.3` prima di `1.10.1` (confronto numerico, non lessicografico) e `T-2.1.1` per ultimo.
- [ ] AC3 — Dato un insieme con id alfabetici diversi (`T-BUG-1`, `QF-3`, `T-BUG-10`), quando si lancia lo script, allora l'ordinamento è deterministico e `T-BUG-10` segue `T-BUG-1` per confronto numerico dell'ultimo segmento.

## Tests expected
`bin/next-wave.test.sh`, nello stile dei test già presenti (`bin/doctor.test.sh`, `bin/handoff.test.sh`): board finta in una cartella temporanea, un caso per criterio. Il caso di AC1 deve essere **rosso con la chiave attuale** e verde dopo la fix: verificalo per mutazione e scrivi l'esito nel corpo della PR.
Integration/E2E: non servono.

## Notes
`grep -ln 'isdigit()' bin/*.sh` oggi restituisce solo `bin/next-wave.sh`, quindi sembra l'unica occorrenza dello schema, ma **verificalo tu** invece di fidarti di questa riga: gli altri script potrebbero ordinare per id in un altro modo.

Diagnosi fatta nella sessione dell'11/09/2026 su tavern-forge, dove la rottura è comparsa.
