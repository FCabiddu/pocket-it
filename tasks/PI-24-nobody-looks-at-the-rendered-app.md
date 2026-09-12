# PI-24 — Nessun agente della pipeline guarda l'app renderizzata

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
**Files**: .claude/agents/ux-ui-designer.md, .claude/agents/qa-engineer.md
**TAD**: none
**Contract**: none
**Branch**: task/pi-24-render-the-app
**PR**: https://github.com/FCabiddu/pocket-it/pull/48

## Goal
In un progetto reale il proprietario ha aperto l'app nel browser e ha trovato «tantissimi errori grafici», a partire da titoli con le lettere tagliate. Nessun controllo della pipeline li aveva visti, e l'analisi ha trovato perché: **nessun agente ha fra i suoi compiti quello di guardare l'app come la guarda un utente.**

- **`ux-ui-designer`, in modalità audit**, legge i sorgenti o scarica il testo della pagina. Non avvia un server, non fa screenshot, non guarda la pagina disegnata. L'audit di quel progetto lo dichiara apertamente («analisi statica, nessun browser, nessuno screenshot») e ha dato il voto massimo alla tipografia di una pagina con le lettere tagliate, lodando proprio le due tecniche che le tagliavano.
- **`qa-engineer`** esegue axe, tastiera, attributi ARIA e contrasto. Nessuno di questi guarda i pixel: axe controlla colori e ruoli, i test in DOM simulato non calcolano il layout, i controlli di overflow guardano la larghezza. Un testo tagliato in verticale non allarga la pagina e passa tutto.
- **Gli strumenti ci sono.** Entrambi gli agenti hanno Bash, quindi possono avviare l'app e usare Playwright; e il modello può leggere le immagini. Manca solo che le loro istruzioni glielo chiedano.

## Acceptance criteria
- [ ] AC1 — Dato `ux-ui-designer` in audit di un'app web o di un sito, quando lavora, allora le sue istruzioni gli prescrivono di avviare l'app, fotografare le pagine a larghezze reali, almeno una mobile e una desktop, e **guardare** le immagini prima di dare un giudizio visivo.
- [ ] AC2 — Dato lo stesso audit, quando dà un voto a tipografia o layout, allora le istruzioni gli vietano di farlo senza aver visto la pagina renderizzata, e gli chiedono di dichiarare nel report se l'ha vista o no.
- [ ] AC3 — Dato `qa-engineer` su un task che tocca l'interfaccia, quando verifica, allora le istruzioni includono un controllo sulla resa: testo che esce o viene tagliato dal proprio contenitore, in orizzontale **e in verticale**, misurato sulla geometria reale nel browser.
- [ ] AC4 — Date le stesse istruzioni, quando descrivono i controlli di accessibilità esistenti, allora dicono esplicitamente cosa quei controlli non vedono, così nessuno scambia un axe verde per una pagina che si legge bene.
- [ ] AC5 — Nessuno dei due agenti viene trasformato in un altro: il designer dirige e critica, il qa verifica. Lo scope di ciascuno resta il suo.

## Tests expected
Nessun test automatico: sono definizioni di agenti. Verifica rileggendo entrambi i file per intero e controllando che le nuove istruzioni non contraddicano quelle esistenti, per esempio sui siti statici senza server o sui task senza interfaccia. Integration/E2E: non servono.

## Notes
Per AC1 considera anche il caso del sito statico, dove non c'è un server da avviare ma una pagina da aprire: la regola deve valere in entrambi.

Per AC3 una misura valida è il confronto fra il riquadro effettivo del testo e quello dell'antenato che lo ritaglia. Un controllo sulla presenza di una classe CSS non vale: è il genere di test rimasto verde con il difetto presente.

Questo repo è pubblico: niente dei progetti su cui gira la pipeline.
