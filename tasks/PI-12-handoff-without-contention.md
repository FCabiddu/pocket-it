# PI-12 — La memoria della pipeline è scritta da tutti nello stesso punto, e la piattaforma la blocca

**Status**: Done
**Label**: DevOps
**Epic**: handoff
**Story**: handoff
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: `tech-analysis/HANDOFF_MEMORY_TECH_ANALYSIS.md` — l'elenco definitivo per ciascun task di implementazione è in §12; l'impianto tocca `bin/handoff.sh`, `bin/status.sh`, gli agenti che leggono la memoria all'avvio (`developer`, `reviewer`, `retro`, `implementation-planner`) e lo skill `run-wave`
**TAD**: tech-analysis/HANDOFF_MEMORY_TECH_ANALYSIS.md (§2.4 decisioni, §12 suddivisione in task)
**Contract**: none
**Branch**: design/pi-12-handoff-without-contention
**PR**: 

## Goal
`docs/SESSION_HANDOFF.md` è la memoria della pipeline: ogni agente ci scrive le proprie righe di log e i propri fatti, e ogni agente lo rilegge all'avvio. È un file solo, e tutti scrivono **in cima alla stessa sezione**. Due rami che lavorano in parallelo toccano quindi sempre la stessa porzione dello stesso file.

Il repository dichiara già una contromisura: `.gitattributes` assegna a quel file il driver di merge `union`, che tiene le righe di entrambe le parti invece di fermarsi in conflitto. **La contromisura funziona ma non viene mai consultata dove serve.** Verificato:

1. `git check-attr` conferma che l'attributo è attivo sul file.
2. Su un repository costruito apposta, due rami che aggiungono ciascuno la propria riga in cima si fondono da soli, tenendo entrambe.
3. Recuperando le due versioni esatte che la piattaforma di hosting aveva dichiarato in conflitto e rifacendo lo stesso merge in locale, il merge **passa pulito**.

La ragione è che l'attributo vive nel repository e lo applica il git locale. I merge della pipeline però non li decide il git locale: li valuta la piattaforma sui propri server, e lì quel file non viene consultato. La contromisura copre quindi solo i merge che già non erano un problema.

Conseguenze misurate in una singola ondata da sette task paralleli: la prima PR entra, le altre sei si bloccano, e ogni merge successivo rompe di nuovo quelle che restano. Sono serviti tre giri di reviewer di sola sconciliazione, con un reviewer arrivato al limite dei turni. Nessuna riga di prodotto e nessun test prodotti da quel lavoro.

Il costo peggiore non è il tempo. La risoluzione di quei conflitti è l'unico punto della pipeline in cui una persona o un agente sceglie a mano quali righe tenere, ed è esattamente lì che nella stessa sessione sono sparite due righe di log scritte il giorno prima. Sono state recuperate confrontando il file con la sua versione precedente, non perché un controllo le abbia segnalate.

L'effetto è anche autoaggravante: più task si lanciano in parallelo, più conflitti si generano, quindi la mitigazione naturale diventa ridurre il parallelismo, cioè rinunciare alla ragione per cui la pipeline esiste.

Direzione proposta, da confermare o sostituire nel design: **togliere la contesa invece di gestirla**. Ogni agente scrive il proprio frammento in un file suo, che nessun altro tocca; la memoria leggibile viene composta dai frammenti quando qualcuno la legge. Due rami che scrivono file diversi non possono confliggere, quindi il problema smette di esistere invece di essere mitigato.

## Cosa deve produrre il design
- La struttura scelta, con il motivo per cui batte le alternative considerate (fra cui: lasciare tutto com'è e accettare il costo; serializzare i merge; far comporre il file da uno script al momento del merge).
- Che cosa succede a `docs/SESSION_HANDOFF.md` come file: sparisce, resta come vista generata, resta come archivio storico.
- Come la memoria viene letta all'avvio dagli agenti che oggi leggono un file solo, e a che costo in token: la lettura è nel percorso di avvio di ogni agente, quindi una lettura più cara si paga a ogni lancio.
- Che cosa ne è dei due limiti già in vigore, le ultime righe di log e il tetto dei fatti, e dell'archiviazione introdotta da PI-8.
- La migrazione del contenuto esistente, che è memoria vera e non va persa.
- La compatibilità con le sessioni già in corso e con i worktree aperti.
- La suddivisione in task con una stima per ciascuno, e l'ordine in cui vanno fatti.

## Acceptance criteria
- [x] AC1 — Esiste un documento di design che sceglie una struttura e dice perché, con le alternative scartate e il motivo.
- [x] AC2 — Il design dice esplicitamente come due rami paralleli che scrivono memoria nello stesso momento smettono di confliggere, e per quale meccanismo, non per quale buona volontà.
- [x] AC3 — Il design copre la migrazione del contenuto esistente senza perdita.
- [x] AC4 — Il lavoro è spezzato in task dimensionati, ordinati, ciascuno con la sua stima.

## Notes
Da non rifare: la strada del driver di merge è già stata provata ed è quella che ha fallito. Un design che la ripropone, in qualunque forma che dipenda da un'impostazione locale del repository, non risolve il problema.

Il vincolo vero da rispettare è che la memoria è nel percorso di avvio di **ogni** agente: qualunque struttura si scelga, leggerla deve restare economico e deve restare una cosa sola da capire per chi la legge.

## Esito
Design prodotto in `tech-analysis/HANDOFF_MEMORY_TECH_ANALYSIS.md`. La direzione proposta è confermata (frammenti per ramo) con due correzioni: la composizione avviene **in lettura** e non in una PR di chiusura (che sarebbe di nuovo un punto di serializzazione e di modifica a mano), e la migrazione vive **dentro `handoff.sh`** ed è pigra, perché lo script è installato una volta e usato da più repo. Implementazione in cinque task, PI-14…PI-18 (§12).
