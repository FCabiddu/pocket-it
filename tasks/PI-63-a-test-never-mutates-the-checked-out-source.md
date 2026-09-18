# PI-63 — Le fixture di auto-mutazione non devono scrivere sul sorgente in uso

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
**Files**: `bin/doctor.test.sh` (le fixture di auto-mutazione, `SCRIPT`/`restore_doctor`/`DOCTOR_BACKUP` intorno alle righe 1487–1547)
**TAD**: none — segui le convenzioni già presenti negli altri `bin/*.test.sh`
**Contract**: none
**Branch**:
**PR**:

## Goal
`bin/doctor.test.sh` imposta `SCRIPT="$(pwd -P)/doctor.sh"` — il file sorgente del checkout, mai una
copia — e le fixture di ricorsione lo **mutano in loco** (`text[:j] + text[i:j] + text[j:]`, che inserisce
una copia identica di una funzione subito dopo l'originale). Il ripristino c'è ed è affidabile per l'uscita
del processo di test (`restore_doctor` dopo ogni caso più `trap … EXIT`), ma nessuna parte del meccanismo
protegge il file da un **lettore esterno concorrente** durante la finestra in cui è mutato: un `git commit`,
un secondo giro di test, il salvataggio automatico di un editor o un altro agente che passa in quell'istante
legge lo stato corrotto, e il trap che scatta un attimo dopo non lo sa.

Non è teoria: è già successo. Un duplicato byte-identico di `_classify_base` è finito **dentro un commit**,
con l'impronta esatta di quella fixture (copia intera della funzione, immediatamente dopo l'originale), ed è
stato scoperto solo perché mandava in rosso altri test. Il danno che conta non è il duplicato: è che un
sorgente può essere pubblicato in uno stato che nessuno ha scritto e nessuno ha letto.

La lezione scritta in quel giro — «non lanciare la suite in background mentre committi» — è un aggiramento
comportamentale, non una correzione: dipende dal fatto che qualcuno se ne ricordi, e non protegge dagli altri
lettori concorrenti. La correzione è che **il test non scriva sul file in uso**.

Verificato prima di scrivere questo task: `bin/doctor.test.sh` è l'**unico** file di test del repo che punta
al sorgente reale; gli altri `bin/*.test.sh` e gli hook lavorano già su fixture temporanee. Quindi il lavoro
è circoscritto a un file, ma la regola vale per tutti.

## Acceptance criteria
- [ ] AC1 — Given la suite `bin/doctor.test.sh` in esecuzione, when si legge `bin/doctor.sh` dal checkout in
      un qualsiasi istante della corsa (anche a metà di un caso di mutazione), then il contenuto è identico a
      quello committato: nessuna finestra in cui il file sul disco differisce da HEAD. Verificalo con una
      prova, non per costruzione — per esempio un lettore in background che campiona l'hash del file per
      tutta la durata della suite e fallisce se ne trova uno diverso da quello di partenza.
- [ ] AC2 — Given le fixture di auto-mutazione della ricorsione, when girano sulla copia invece che sul
      sorgente, then continuano a verificare esattamente quello che verificavano prima: restano rosse se la
      logica che coprono viene rotta. Dimostralo con una mutazione eseguita in entrambe le direzioni, non
      solo con «i test passano».
- [ ] AC3 — Given l'intera suite `bin/doctor.test.sh`, when gira, then il conteggio dei casi e l'esito sono
      gli stessi di prima della modifica (nessun caso perso per strada nel trasloco sulla copia).
- [ ] AC4 — Given un'interruzione della suite a metà di un caso di mutazione (`SIGINT`), when il processo
      termina, then il checkout resta pulito (`git status --porcelain` su `bin/doctor.sh` vuoto) — è la
      proprietà che oggi dipende dal trap e che dopo la correzione deve valere comunque, perché il sorgente
      non viene più toccato.
- [ ] AC5 — Given un futuro file di test che puntasse di nuovo al sorgente in uso, when la suite gira, then
      la cosa è visibile: aggiungi il controllo dove gli altri test del repo lo leggerebbero, oppure scrivi
      la regola nel posto che un agente legge all'avvio. Una delle due, non entrambe.

## Tests expected
Nella suite stessa, nello stile dei casi già presenti: il lettore concorrente di AC1, il caso di
interruzione di AC4, e la prova di mutazione bidirezionale di AC2 documentata nel report.
Integration/E2E: not needed.

## Notes
- Origine del difetto: `git blame` colloca il codice di auto-mutazione a `780a5ee8` (2026-09-17, PI-45),
  quindi è preesistente e non introdotto da PI-62. È emerso durante la review di PI-62 e il reviewer lo ha
  confermato meccanicamente, non per plausibilità: l'impronta del duplicato committato corrisponde a quella
  specifica fixture.
- La strada indicata dalla review è mutare una copia sotto la directory temporanea della suite invece di
  `$SCRIPT`. Se la fixture deve far girare `doctor.sh` sul proprio testo mutato, falla girare sulla copia:
  serializzare le corse è la soluzione peggiore, perché lascia in piedi la finestra per ogni altro lettore
  che non partecipa alla serializzazione.
- Non allargare a `bin/verify.sh` né agli altri script: la ricognizione qui sopra dice che non ne hanno
  bisogno. Se durante il lavoro ne trovi un altro che scrive sul sorgente in uso, non correggerlo di
  nascosto: dillo nel report.
