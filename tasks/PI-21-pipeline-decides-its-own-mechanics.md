# PI-21 — La pipeline rimanda all'utente decisioni sul proprio funzionamento

**Status**: Done
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: .claude/skills/run-wave/SKILL.md, .claude/skills/quickfix/SKILL.md, .claude/agents/reviewer.md, .claude/agents/retro.md, CLAUDE.md, README.md
**TAD**: none
**Contract**: none
**Branch**: task/pi-21-pipeline-decides-mechanics
**PR**: https://github.com/FCabiddu/pocket-it/pull/45

## Goal
La pipeline esiste perché il lavoro vada avanti, e i problemi vengano gestiti, senza qualcuno alla tastiera. Oggi in più punti fa il contrario: davanti a un intoppo del proprio funzionamento si ferma e passa la decisione all'utente. Una pipeline che chiede a ogni intoppo non è automatizzata, sposta soltanto il lavoro manuale.

Due difetti concreti, più la regola che li genera.

**1. Un solo reviewer per wave non regge una wave grande.** `run-wave` lancia un reviewer per l'intera wave, e il reviewer ha `maxTurns: 60`. Con sette PR in una sola wave il reviewer si è fermato al limite dei turni, ed è stato necessario riprenderlo. Le due regole sono incompatibili appena la wave cresce, e nessuna delle due dice cosa fare.

**2. Dopo due giri di review la PR «va all'utente».** `run-wave` e `quickfix` dicono entrambi che ciò che resta rosso dopo due giri passa all'utente. Ma un PR rosso al terzo giro è un problema di esecuzione, non una decisione di prodotto: fermarsi lì blocca la pipeline su una cosa che la pipeline stessa può gestire.

**3. Gli agenti etichettano come «da decidere dall'utente» questioni di pipeline.** Reviewer e retro chiudono i loro report con elenchi di cose «da decidere» che mescolano due categorie diverse: le rare decisioni che solo un umano può prendere, e le scelte sul funzionamento della pipeline, che spettano all'orchestratore. Mescolate, finiscono tutte davanti all'utente.

La distinzione da rendere esplicita:

- **Solo umano, per costruzione:** decisioni di business o di prodotto; soldi, credenziali, account, permessi; dati o contenuti che solo il cliente ha; verifiche fisiche o umane (screen reader reale, dispositivo reale, firma legale); il deploy in produzione. Anche qui si ferma **quel singolo punto**, si notifica, e si prosegue sul resto.
- **Dell'orchestratore:** tutto ciò che riguarda il meccanismo — limiti di turni e budget, come si raggruppano le review, quanti giri prima di scalare, con quale modello si riprova, quando compattare, conflitti, memoria persa, esecuzioni intermittenti, agenti bloccati. L'orchestratore decide, corregge dalla corsia giusta, e **notifica**. Non chiede.

## Acceptance criteria
- [x] AC1 — Dato `run-wave` con una wave di più PR del massimo che un reviewer gestisce entro i suoi turni, quando si arriva alla review, allora lo skill prescrive più reviewer in parallelo, ciascuno su un gruppo limitato di PR, e dice qual è il limite del gruppo e perché.
- [x] AC2 — Dati `run-wave` e `quickfix`, quando una PR richiede un secondo giro di review (e a maggior ragione un terzo), allora gli skill prescrivono, prima di rilanciare il developer, un'analisi di causa — perché il giro precedente non ha chiuso il problema — classificata in almeno queste tre famiglie, aperta ad altre: il finding o il task descrivevano un esempio e non l'intera specifica; la base si è mossa sotto la PR nel frattempo; la verifica stessa ha reintrodotto il difetto. La correzione va scritta dove la causa la rende necessaria (il task/finding, il passo di verifica, la regola di stesura dei report), poi si riprende la PR con quella correzione in mano. Il parcheggio della PR con motivo scritto resta come ultima risorsa dopo l'analisi — mai come risposta a un conteggio di giri — e senza rimandare la decisione all'utente.
- [x] AC3 — Dati `reviewer.md` e `retro.md`, quando un agente chiude il report con punti aperti, allora il file gli prescrive di separarli nelle due categorie, e di non attribuire all'utente una questione sul funzionamento della pipeline.
- [x] AC4 — Dato ognuno dei quattro file, quando lo si rilegge per intero, allora non resta nessuna frase che mandi all'utente una decisione sul meccanismo della pipeline.
- [x] AC5 — Dati i punti che restano davvero umani, quando uno di essi si presenta, allora i testi dicono di fermare solo quel punto e continuare sul resto, non di fermare tutto.

## Tests expected
Nessun test automatico: sono file di prosa e di configurazione di agenti. AC4 si verifica rileggendo ciascun file per intero e cercando le frasi che rimandano all'utente con più di una formulazione, perché la stessa cosa si può dire senza la parola ovvia. Riporta nel report l'esito di ogni ricerca. Integration/E2E: non servono.

## Notes
Per AC1 il limite del gruppo va motivato con un numero, non scelto a sensazione: un reviewer con `maxTurns: 60` si è fermato su una wave da sette PR, cioè sotto i nove turni per PR, e ogni PR che richiede una risoluzione di conflitti o una verifica per mutazione ne consuma di più. Decidi il limite e scrivi il ragionamento nel testo, così chi lo rilegge può correggerlo.

Non alzare `maxTurns` del reviewer come soluzione: è una rete di sicurezza, e allargarla sposta il problema alla wave successiva più grande.

`shared/lessons.md` resta fuori scope (è del retro). PI-20 è mergiato: l'esclusione di `CLAUDE.md` non vale più, ed è stato aggiunto ai `Files` insieme a `README.md`, le altre sedi dove il vecchio meccanismo (un reviewer, due giri) era ancora scritto. `.claude/skills/deps/SKILL.md` è stato toccato al secondo giro e riportato al testo originale al terzo (vedi nota sotto): non è più nei `Files`.

`.claude/agents/shared/implementing-common.md` **non va toccato in questo task**: ci lavora PI-22 in parallelo, e una modifica concorrente produrrebbe lo stesso genere di conflitto che questo task corregge altrove. La regola sulla verifica che reintroduce il difetto (famiglia 3 di AC2) va lì; i testi qui si limitano a nominarlo come destinazione, senza scriverne il contenuto altrove per aggirare il divieto. Il proprietario la aggiunge dopo il merge di PI-22.

Questo repo è pubblico: niente dei progetti su cui gira la pipeline, né di entry point privati.

**Cambio di scope su AC2, recepito.** La scalata a modello più capace / divisione / parcheggio, come prima risposta a un secondo o terzo giro rosso, corregge il sintomo e non la causa. `run-wave` e `quickfix` ora prescrivono un'analisi di causa prima di rilanciare il developer, classificata almeno in tre famiglie osservate su PR reali arrivate al terzo giro: (1) il finding o il task descrivevano un esempio (due grafie di un comando bloccate da una guardia di sicurezza) e non l'intera classe, bypassata da una terza grafia — corretto enumerando l'insieme nel task/finding, non ripetendo l'istanza; (2) la base si è mossa sotto la PR (una lingua di default cambiata su main dopo l'approvazione) e i test, verdi sul branch, assumevano lo stato vecchio — corretto con un merge/rebase e un nuovo giro di test scoped prima di rimandare in review; (3) la verifica ha reintrodotto il difetto (un comando o un report che dimostra l'assenza di un nome lo ripete letteralmente) — corretto descrivendo la verifica per effetto, mai per contenuto. `reviewer.md` in `Mode: delta` ora dichiara questa causa anche quando la mancanza era sua, e i finding su una classe di problemi elencano l'insieme, non uno o due esempi. `retro.md` raccoglie i giri di review in più per causa, non solo per numero. Il parcheggio resta l'ultima risorsa dopo l'analisi, mai la risposta a un conteggio di giri; i reviewer paralleli su gruppi limitati e la separazione umano/orchestratore restano come nella prima stesura.

**Secondo giro di review (PR #45, 5 finding), tutti recepiti.** Il cambio di scope su AC2 era arrivato a metà lavoro, e la prima stesura lo aveva applicato solo ai punti citati, non a tutta la classe nel repo. Corretto:
- **F1** — nessuna scalata come prima mossa, in nessun punto, nemmeno per un developer fermo che non si può riprendere: prima l'analisi di causa (task in realtà doppio, input sbagliato, base mossa, blocco di uno strumento), poi la correzione nella corsia giusta; si rilancia da zero solo se il worktree non esiste più, sullo stesso modello a meno che l'analisi non indichi il modello come causa; il parcheggio non scatta più su "la causa si è ripresentata una volta" (era un conteggio mascherato) ma solo quando l'analisi conclude che la causa è fuori dalla portata della pipeline.
- **F2** — l'analisi ora ha una destinazione eseguibile: il reviewer propone `cause:`/`fix at:` **nella riga di ritorno del suo Step 6** (mai solo nel commento PR, che l'orchestratore non legge), e chi applica ogni famiglia è nominato (chi edita il criterio e su quale branch; chi rilancia merge/rebase; dove va la regola sulla verifica). *(Il log persistente `ROUND …` proposto qui è stato tolto al terzo giro — vedi nota sotto: la sostanza, cioè che la causa vive nel report e nella riga di ritorno del reviewer, resta.)*
- **F3** — il limite dei reviewer paralleli scende da 4 a **3 PR**, motivato con la misura già su `shared/lessons.md` (~20 turni/PR con conflitti e mutazioni ricontate, non la media piatta 60/7≈8.6 usata prima): 60/~20 ≈ 3. *(La citazione del "merge-tree run" nel ragionamento è stata tolta al terzo giro insieme al meccanismo stesso.)*
- **F4** — *(il test sull'albero sovrapposto proposto qui per `reviewer.md` è stato tolto al terzo giro — vedi nota sotto)*. I report di `run-wave`/`quickfix` hanno ora una riga `Decided on its own: …` per cause trovate, PR parcheggiate, task divisi, agenti ripresi — il proprietario lo vede sempre. `reviewer.md` "never put to the user" → "mai chiesto all'utente, sempre riferito"; `retro.md` dice che solo il punto umano si ferma, il resto del giro atterra comunque.
- **F5** — scope allargato: `CLAUDE.md` (righe 16, 68, 162), `README.md` (28, 57) allineati allo stesso meccanismo. *(`.claude/skills/deps/SKILL.md`, toccato qui, è stato riportato al testo originale al terzo giro — vedi nota sotto.)* `shared/implementing-common.md` resta non toccato (PI-22 in parallelo); la regola sulla verifica-che-reintroduce-il-difetto è nominata come destinazione, non scritta altrove.

**Terzo giro (delta review, 4 finding D1–D4): scope ridotto, non ampliato.** Il reviewer ha trovato che il secondo giro aveva introdotto tre meccanismi nuovi (la riga `ROUND`, il test sull'albero sovrapposto, l'edit diretto di `dependabot.yml`) senza confrontarli con le regole vicine — e la causa era in parte del proprietario stesso, che li aveva dettati in poche righe nel giro precedente senza specificarli o verificarli abbastanza. La correzione della causa qui è **togliere**, non aggiungere altro sopra:
- **D1 (riga `ROUND`)** — tolta da `run-wave`, `quickfix` e `retro.md`: rotazione del log a 40 righe, grep non ancorato, vocabolario non condiviso fra i quattro punti, contatore `k` non definito fra sessioni. Il design di dove vivono `BUDGET`/`STALL` e simili è di PI-12 (già in PR): va progettato lì, non qui. Resta la sostanza già approvata dal reviewer: la causa del giro in più sta nel report e nella riga di ritorno del reviewer (Step 6 di `reviewer.md`), non nel solo commento PR.
- **D2 (fix in un file di pocket-it)** — una frase sola, in `run-wave` e `quickfix`, dove le famiglie indicano che una correzione va in un file di pocket-it (`shared/implementing-common.md`, un template, uno skill, `verify.sh`, un hook): quella correzione passa da un `/quickfix` su pocket-it (solo meccanismo, niente dati di progetto), l'orchestratore non la applica mai direttamente.
- **D3 (test sull'albero sovrapposto)** — tolto interamente da `reviewer.md` Step 3: contraddiceva "never the full suite" nella stessa sezione, e con i gruppi da 3 PR due PR della stessa wave in gruppi diversi non finiscono mai sullo stesso albero — cioè non copriva proprio il caso di base mossa che doveva risolvere. È un problema di progettazione a sé: il proprietario lo apre come task separato.
- **D4 (edit diretto di `dependabot.yml`)** — tolto da `.claude/skills/deps/SKILL.md`, che torna al testo originale: l'edit fatto qui dall'orchestratore introduceva un'implementazione di progetto senza developer né review, nella sessione principale. Il file non è più nei `Files` di questo task (nessuna modifica netta resta).

Nessun'altra modifica toccata: la separazione umano/orchestratore, la causa prima della ripresa (F1), il limite di tre PR per reviewer (F3, motivazione invariata), la riga `Decided on its own` nei report, gli allineamenti in `CLAUDE.md` e `README.md` restano come nel secondo giro. Un'unica eccezione minima, non un meccanismo: `README.md:110` ("the reviewer runs once per wave") era la stessa classe di F5 e non era stata cercata lì — corretta in linea con `README.md:57`, nessun testo nuovo inventato.
