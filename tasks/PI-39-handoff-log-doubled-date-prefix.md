# PI-39 — handoff.sh log: normalizzare un messaggio che comincia già con la data

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
**Files**: bin/handoff.sh, bin/handoff.test.sh, docs/SESSION_HANDOFF.md, docs/SESSION_HANDOFF_ARCHIVE.md
**TAD**: none — segui le convenzioni esistenti degli script in bin/
**Contract**: none
**Branch**: 
**PR**: 

## Goal
`bin/handoff.sh log "<messaggio>"` antepone sempre `- $(date +%Y-%m-%d) ` al messaggio (riga 274). Se chi chiama passa un messaggio che comincia **già** con una data ISO, la riga nasce con la data doppia: su `main` ci sono oggi due righe così, scritte dal commit `f70db11`, per esempio

```
- 2026-09-15 2026-09-15 PI-36 mergiato su main (#70) — la guardia non blocca piu' ...
- 2026-09-15 2026-09-15 PI-15 PR #71 needs work — AC1 dichiara zero occorrenze del grep ...
```

Quella forma non è riconosciuta da `NEEDS_WORK_RE` in `bin/retro-due.sh` (che àncora `^- <data> <ID> PR #<n> …`: con la data doppia il secondo token è la data, non l'ID), quindi l'auto-verifica **R4F1** di `bin/retro-due.test.sh` — che classifica le righe *reali* di questo progetto con la regex vera dello script — va rossa, e con lei `bin/verify.sh` di qualsiasi PR aperta. È così che il difetto è stato trovato: la review di PI-37 (PR #74) è finita NEEDS WORK per un rosso che non c'entrava nulla con il suo diff.

Comportamento atteso: `handoff.sh log` **normalizza in scrittura** — un prefisso di data ISO ridondante all'inizio del messaggio non finisce mai nella riga — e le due righe già scritte su `main` vengono corrette.

## Acceptance criteria
- [ ] AC1 — Given un messaggio qualsiasi che comincia con una data ISO seguita da uno spazio (`YYYY-MM-DD `), when si esegue `handoff.sh log "<messaggio>"`, then la riga scritta ha **una sola** data, quella di `date +%Y-%m-%d`, e il resto del messaggio integro. Vale per la classe intera, non per un esempio: data uguale a oggi, data diversa da oggi, più prefissi di data ripetuti (`2026-09-01 2026-09-02 testo`), e il caso limite del messaggio che **è soltanto** una data.
- [ ] AC2 — Given un messaggio che contiene una data ISO **non** in testa (per esempio `PI-40 PR #80 approved — regressione del 2026-09-01`), when si esegue `handoff.sh log`, then la data interna al testo non viene toccata: si normalizza solo il prefisso.
- [ ] AC3 — Given `docs/SESSION_HANDOFF.md` e `docs/SESSION_HANDOFF_ARCHIVE.md` sul branch, when si cerca una riga di log con due date consecutive (`^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{4}-[0-9]{2}-[0-9]{2} `), then non ce n'è nessuna: le righe già scritte sono corrette in loco, **senza perdere testo** (si toglie solo la data di troppo; il contenuto resta identico parola per parola). Cerca in entrambi i file: la rotazione può averne spostata una nell'archivio.
- [ ] AC4 — Given le due righe corrette, when si esegue `bash bin/retro-due.test.sh`, then R4F1 è verde; e `bash bin/verify.sh` non riporta più quel rosso. Riporta nel corpo della PR l'output di R4F1 prima e dopo.
- [ ] AC5 — Given `NEEDS_WORK_RE` in `bin/retro-due.sh`, when si legge il diff, then **non è stata allargata** per tollerare la data doppia: l'àncora «l'ID è il secondo token» è la difesa che ha fatto emergere il difetto e resta com'è. La correzione sta in scrittura (AC1) e nei dati (AC3), non nel lettore. Se pensi che serva anche una tolleranza in lettura, non farla: scrivilo nel report come proposta motivata.
- [ ] AC6 — Given l'intero `testCommand` del progetto, when lo si esegue, then resta verde come prima (nessun test esistente rotto).

## Tests expected
Test nuovi in `bin/handoff.test.sh`, uno per criterio di AC1/AC2 (tabella di casi, non un esempio singolo): data di oggi in testa, data diversa in testa, doppio prefisso, messaggio che è solo una data, data a metà testo lasciata intatta. Più un test che asserisce AC3 come invariante sui due file reali del repo (nessuna riga con due date consecutive), così la regressione non può rientrare dai dati. Integration/E2E: not needed.

## Notes
- L'implementazione di `log` è in `bin/handoff.sh` intorno a riga 273-274: `line="- $(date +%Y-%m-%d) $*"`.
- La regex del lettore è `NEEDS_WORK_RE` in `bin/retro-due.sh` (circa riga 70) e il test che l'ha scoperta è R4F1 in `bin/retro-due.test.sh` (circa riga 334): quel test classifica le righe **vere** del progetto con la regex **vera** dello script, per questo un dato sporco su `main` lo fa fallire.
- Causa a monte: l'orchestratore ha passato a `handoff.sh log` un messaggio che cominciava con la data. Lo script è il posto giusto per chiudere la classe, perché nessun chiamante deve ricordarsi la convenzione.
- `timeout` e `gtimeout` non esistono su questa macchina: lancia i comandi in primo piano.
- Niente riferimenti a progetti in questo repo: è pubblico.
