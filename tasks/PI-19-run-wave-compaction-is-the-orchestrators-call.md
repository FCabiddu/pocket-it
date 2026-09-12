# PI-19 — `run-wave` fa decidere all'utente una cosa che deve decidere l'orchestratore

**Status**: Needs Work
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: XS
**Budget**: 60
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: .claude/skills/run-wave/SKILL.md
**TAD**: none
**Contract**: none
**Branch**: task/pi-19-compaction-is-orchestrator-call
**PR**: https://github.com/FCabiddu/pocket-it/pull/42

## Goal
La sezione «Session hygiene» di `.claude/skills/run-wave/SKILL.md` chiude la seconda wave dicendo all'orchestratore di terminare il report con una frase che gira la decisione all'utente: compattare il contesto o aprire una sessione nuova.

È la decisione sbagliata da girare. Una sessione carica non si rompe, peggiora in silenzio: il giudizio cala prima che qualcosa appaia guasto, quindi aspettare un sintomo visibile significa decidere tardi. E l'utente ha meno elementi dell'orchestratore per giudicare, perché non ha visto quanti agenti sono stati lanciati, quanti giri di review sono serviti e quanto è stato riletto.

Il numero di contesto non è leggibile dal modello, ma la decisione non richiede quel numero: richiede segnali contabili che l'orchestratore ha già sotto gli occhi.

Vincolo verificato, da rispettare nella riscrittura: **il modello non può avviare la compattazione**. La esegue il runtime, non esiste un tool, un hook o un comando con cui la sessione la avvii, e il modello non può nemmeno leggere il proprio consumo di contesto. Quello che appartiene all'orchestratore è quindi la **decisione e il momento**, non l'esecuzione. Il testo non deve promettere un'azione che nessuno può eseguire.

Il tono cambia di conseguenza: non una domanda all'utente, ma una riga che constata. La sessione è da compattare, lo stato è su disco e non si perde nulla. L'utente preme il tasto perché lo strumento richiede una battuta umana, non perché gli si stia chiedendo un parere.

La stessa regola è già stata riscritta nell'entry point privato dell'orchestratore: questo task allinea lo skill pubblico, non inventa una regola nuova.

## Acceptance criteria
- [x] AC1 — Dato il testo della sezione, quando lo si legge, allora attribuisce la decisione all'orchestratore e non all'utente, e non è formulata come una domanda.
- [x] AC2 — Dato lo stesso testo, quando lo si legge, allora dice esplicitamente che l'esecuzione non è del modello, così nessuno ci legge un'azione eseguibile che non esiste.
- [x] AC3 — Dato lo stesso testo, quando lo si legge, allora elenca segnali contabili per decidere, non una soglia di contesto che il modello non può leggere.
- [x] AC4 — Dato il resto dello skill, quando lo si rilegge, allora non resta nessun'altra frase che rimandi all'utente la stessa decisione.

## Tests expected
Nessun test automatico: è un file di prosa. Verifica rileggendo il file intero, e cerca le altre occorrenze con un `grep` su «compact» prima di dichiarare AC4. Integration/E2E: non servono.

## Notes
Il testo di riferimento già scritto sta nell'entry point privato dell'orchestratore, che questo repo non contiene: non cercarlo qui e non citarlo. Riscrivi con le tue parole a partire dal contenuto di questo task.

Questo repo è pubblico: la riscrittura non deve nominare progetti, sessioni o numeri di PR che non appartengano a pocket-it.
