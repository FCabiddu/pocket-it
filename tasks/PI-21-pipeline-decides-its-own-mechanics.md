# PI-21 — La pipeline rimanda all'utente decisioni sul proprio funzionamento

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
**Files**: .claude/skills/run-wave/SKILL.md, .claude/skills/quickfix/SKILL.md, .claude/agents/reviewer.md, .claude/agents/retro.md
**TAD**: none
**Contract**: none
**Branch**: 
**PR**: 

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
- [ ] AC1 — Dato `run-wave` con una wave di più PR del massimo che un reviewer gestisce entro i suoi turni, quando si arriva alla review, allora lo skill prescrive più reviewer in parallelo, ciascuno su un gruppo limitato di PR, e dice qual è il limite del gruppo e perché.
- [ ] AC2 — Dati `run-wave` e `quickfix`, quando una PR è ancora rossa dopo i giri normali di review, allora gli skill prescrivono una scalata eseguibile senza l'utente — per esempio un developer nuovo su `opus` con tutti i finding, oppure la divisione del task, oppure il parcheggio della PR con motivo scritto proseguendo sul resto — e non rimandano la decisione all'utente.
- [ ] AC3 — Dati `reviewer.md` e `retro.md`, quando un agente chiude il report con punti aperti, allora il file gli prescrive di separarli nelle due categorie, e di non attribuire all'utente una questione sul funzionamento della pipeline.
- [ ] AC4 — Dato ognuno dei quattro file, quando lo si rilegge per intero, allora non resta nessuna frase che mandi all'utente una decisione sul meccanismo della pipeline.
- [ ] AC5 — Dati i punti che restano davvero umani, quando uno di essi si presenta, allora i testi dicono di fermare solo quel punto e continuare sul resto, non di fermare tutto.

## Tests expected
Nessun test automatico: sono file di prosa e di configurazione di agenti. AC4 si verifica rileggendo ciascun file per intero e cercando le frasi che rimandano all'utente con più di una formulazione, perché la stessa cosa si può dire senza la parola ovvia. Riporta nel report l'esito di ogni ricerca. Integration/E2E: non servono.

## Notes
Per AC1 il limite del gruppo va motivato con un numero, non scelto a sensazione: un reviewer con `maxTurns: 60` si è fermato su una wave da sette PR, cioè sotto i nove turni per PR, e ogni PR che richiede una risoluzione di conflitti o una verifica per mutazione ne consuma di più. Decidi il limite e scrivi il ragionamento nel testo, così chi lo rilegge può correggerlo.

Non alzare `maxTurns` del reviewer come soluzione: è una rete di sicurezza, e allargarla sposta il problema alla wave successiva più grande.

`shared/lessons.md` e `CLAUDE.md` non fanno parte di questo task: li tocca PI-20.

Questo repo è pubblico: niente dei progetti su cui gira la pipeline, né di entry point privati.
