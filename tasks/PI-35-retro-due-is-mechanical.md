# PI-35 — Uno script dice quando serve un retro, e run-wave e quickfix lo lanciano senza aspettare nessuno

**Status**: Done
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: M
**Budget**: 200
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: `bin/retro-due.sh` (nuovo), `bin/retro-due.test.sh` (nuovo), `.pocket-it.json` (`testCommand`), `.claude/skills/run-wave/SKILL.md`, `.claude/skills/quickfix/SKILL.md`, `.claude/agents/retro.md`
**TAD**: none — follow existing conventions (`bin/next-wave.sh`, `bin/doctor.sh`: gli script decidono, il modello lancia)
**Contract**: output di `bin/retro-due.sh` (vedi AC1), letto da skill e hook; lo scope passato al retro dal trigger automatico è `Signals:` seguito dalle righe di segnale verbatim, `{scope}` della riga di segno in quel caso è `signals-{date}` (un token, mai il testo dei segnali) — round 2 review, vedi Notes
**Branch**: task/pi-35-retro-due
**PR**: https://github.com/FCabiddu/pocket-it/pull/66

## Goal
Oggi il miglioramento del flusso dipende dall'orchestratore che si ricorda di lanciare un retro, o dall'utente che lo chiede. Le regole in prosa («un errore si chiude in tre mosse», «il retro chiude il cerchio») non vengono applicate con costanza. Quelle fatte rispettare da uno script o da un hook sì. Il segnale esiste già: ogni NEEDS WORK del reviewer lascia nel log del handoff una riga con `cause: …`, e gli sforamenti lasciano `BUDGET`/`STALL`. Manca un meccanismo che lo legga. Serve uno script deterministico che dica se è dovuto un retro e su cosa, chiamato da `run-wave` e `quickfix` dopo ogni review, e un segno lasciato dal retro che faccia ripartire il conteggio.

## Acceptance criteria
- [ ] AC1 — Given un log del handoff, when si lancia `bash bin/retro-due.sh`, then l'output è una riga `RETRO DUE: <n> segnali` seguita da una riga per segnale (`<task> — <tipo> — <riga di log>`), e l'uscita è 10. Se non ci sono segnali l'output è `retro-due: nothing` e l'uscita è 0. Un errore di input dà uscita 2.
- [ ] AC2 — Given le righe di log successive all'ultimo segno di retro, when lo script le valuta, then conta come segnale ciascuna di queste: (a) una riga `needs work` con `cause:` diversa da `first-round`; (b) la stessa `cause` che ricorre in due task diversi; (c) un task con tre o più righe `needs work`; (d) una riga `BUDGET` o `STALL`. Per ciascun tipo c'è un test positivo e un test negativo (per esempio `cause: first-round` da solo non basta).
- [ ] AC3 — Given un retro terminato, when scrive nel log la riga di segno (formato definito qui e scritto in `retro.md`, per esempio `retro-mark <data> <scope>`), then una nuova esecuzione di `retro-due.sh` ignora tutte le righe precedenti al segno. Il test copre un segno a metà log e un log senza nessun segno.
- [ ] AC4 — Given lo script, when legge la memoria, then non scrive nulla: `git status --porcelain` è identico prima e dopo, anche lanciato dalla radice di un progetto senza `docs/`. Se esiste un compositore di lettura in `bin/handoff.sh` (sottocomando `recent`/`grep`), lo usa, altrimenti legge `docs/SESSION_HANDOFF.md` e l'archivio.
- [ ] AC5 — Given `run-wave/SKILL.md` e `quickfix/SKILL.md`, when si leggono i passi successivi a ogni review, then contengono l'istruzione: eseguire `retro-due.sh` e, con uscita 10, lanciare subito l'agente `retro` in background con i segnali come scope, senza chiedere e senza aspettare la fine dell'epica.
- [ ] AC6 — Given `retro.md`, when il retro termina, then l'ultima cosa che fa è scrivere la riga di segno con `handoff.sh log`, dopo il merge della sua PR.

## Tests expected
Un test per ciascuno fra AC1, AC2 (un positivo e un negativo per tipo), AC3 e AC4, su log di prova creati dal test. Una mutazione per ciascun tipo di segnale. AC5 e AC6 si verificano con grep nel test. Integrazione/E2E: non serve.

## Notes
- Formato delle righe di log attuali, da un caso reale: `- 2026-09-13 PI-12 PR #39 needs work — contesa spostata su _base.md — cause: first-round`. Il reviewer scrive `cause: {…} — fix at: {…}`, vedi `.claude/agents/reviewer.md` riga ~146.
- PI-14…PI-18 stanno cambiando la memoria in frammenti. Leggi tramite il compositore quando c'è (AC4), così lo script non si rompe con il passaggio ai frammenti.
- L'hook di fine turno che blocca finché un retro dovuto non è partito sta fuori da questo repo, nella configurazione privata dell'utente. Lo aggancia l'orchestratore dopo il merge. Questo task fornisce solo lo script con il suo contratto di uscita (0 / 10 / 2).
- Nessun riferimento a progetti: il repo è pubblico.
- Round 2 (5 finding): `retro-mark` va riconosciuto solo nella forma esatta ancorata `^- <data> retro-mark <data> <scope>$`; `BUDGET`/`STALL`/`needs work` vanno ancorati alla forma reale del log (`- <data> BUDGET/STALL …`, `<ID> PR #<n> … needs work` senza `—` di mezzo) — `quickfix/SKILL.md` ora scrive `needs-work` (trattino) nella sua riga di chiusura proprio per non collidere con questo; `cause:` finisce al primo `—`; ogni errore di lettura/argomento dà uscita 2, mai `nothing`/exit 1; `run-wave`/`quickfix` non rilanciano un retro se un `retro/*` è già aperto; `retro.md` scrive il segno anche senza PR propria (tranne se resta in draft) e dichiara l'input `Signals:` con `{scope}` = `signals-{date}`.
- Round 3 (2 finding): `cause:` va letto solo dal campo vero `— cause: <valore>` (l'ultimo, con `findall`), mai dalla prima occorrenza della sottostringa (`because:`, `root cause:`); `needs work` va ancorato all'intera riga (`^- <data> <ID> PR #<n> …`), l'esito deve essere la parola giusto dopo `PR #<n>`, non una qualunque presente prima del prossimo `—`.
- Round 4 (2 finding): le forme del qualificatore fra parentesi vanno ricavate dal log/archivio reale (`bash bin/handoff.sh recent --all | grep 'needs work'`), non da un elenco scritto a mano — mancava `needs work (delta)` senza numero; **`reviewer.md:142` è fuori da `**Files**:` ma è stato corretto in questo giro**: il template della riga NEEDS WORK non conteneva `cause:`, quindi un reviewer che lo seguisse alla lettera non avrebbe mai prodotto i segnali (a)/(b) — è il produttore del segnale che questo task consuma, per questo la correzione è giustificata anche fuori dai File dichiarati.
