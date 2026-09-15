# PI-37 — Un task mergiato che resta «Needs Work» torna a proporsi come lavoro pronto

**Status**: Done
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: S
**Budget**: 90 min
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: `bin/doctor.sh`, `bin/doctor.test.sh`, `.claude/skills/run-wave/SKILL.md` (Step 5)
**TAD**: none — convenzioni di `bin/doctor.sh` e `bin/next-wave.sh` (gli script decidono, il modello lancia)
**Contract**: `doctor.sh` continua a uscire 1 sugli errori e 0 con soli warning; il nuovo controllo è un **warning**, non un errore, perché non impedisce un lancio.
**Branch**: task/pi-37-merged-task-left-not-done
**PR**: https://github.com/FCabiddu/pocket-it/pull/74

## Goal
Caso reale, pocket-it, 15/09/2026. `tasks/PI-29-doctor-detects-rewritten-base.md` diceva `**Status**: Needs Work` mentre la sua PR #60 era **mergiata** dal 13/09. Conseguenza: `next-wave.sh` lo elencava fra i due task «ready», cioè offriva come lavoro da lanciare un task già chiuso. Chi non controlla la PR ci lancia sopra un developer.

La causa è un buco fra due corsie. `quickfix/SKILL.md` dice già, dopo il merge: «make sure `tasks/QF-{n}-*.md` says `**Status**: Done` (set it if the developer left it otherwise)». Lo **Step 5 di `run-wave`** no: merge, `tasks-index.sh`, `handoff.sh log`, commit, push — e nessun controllo sullo stato. PI-29 è passato da lì. Una regola scritta in una corsia sola non è una regola.

Due livelli, entrambi necessari: la skill lo dice a chi merge, lo script lo rileva anche quando nessuno lo dice.

## Acceptance criteria
- [ ] AC1 — Given un repo con un file di task il cui campo `**PR**` indica una PR **mergiata** e il cui `**Status**` non è `Done`, when si lancia `bash bin/doctor.sh`, then compare un warning che nomina il file, lo stato trovato e il numero di PR, e il conteggio dei warning cresce di uno. L'uscita resta 0 se non ci sono errori.
- [ ] AC2 — Given la classe completa degli stati non finali (`Todo`, `In Progress`, `Needs Work`, e uno stato non canonico come `WIP`), when la PR del task risulta mergiata, then ciascuno produce il warning. Given `Status: Done` con PR mergiata, o uno stato qualsiasi con PR **aperta**, **chiusa senza merge** o assente (`—`, vuoto, `none`), then **nessun** warning: il controllo parla solo del caso mergiata-ma-non-chiusa.
- [ ] AC3 — Given un ambiente senza `gh`, senza rete o senza permessi sul repo, when si lancia `doctor.sh`, then il controllo si salta in silenzio (nessun warning, nessun errore, nessuna attesa lunga) e tutto il resto di `doctor.sh` gira normalmente. `doctor.sh` non deve diventare dipendente dalla rete: se serve, il controllo si attiva solo quando `gh auth status` risponde subito.
- [ ] AC4 — Given `doctor.sh`, when lo si lancia due volte di fila, then `git status --porcelain` è identico prima e dopo: non scrive niente, non modifica i task file. La correzione dello stato resta un gesto di chi merge, non dello script.
- [ ] AC5 — Given `run-wave/SKILL.md` Step 5, when si legge il passo che segue `gh pr merge`, then contiene l'istruzione — nella stessa forma già presente in `quickfix/SKILL.md` — di verificare che il task file della PR mergiata dica `**Status**: Done` e di correggerlo se il developer l'ha lasciato altrimenti, prima del commit di `tasks/` sul ramo base.

## Tests expected
Casi nuovi in `bin/doctor.test.sh` per AC1, AC2 (un positivo e un negativo per ogni dimensione: stato × esito della PR) e AC4, su repo di prova creati dal test con `gh` simulato — non chiamate di rete vere. AC5 si verifica con un grep nel test. Una mutazione eseguita: togli il controllo e mostra che i casi di AC1/AC2 diventano rossi.

## Notes
- Il caso vero da cui parte il task: `tasks/PI-29-doctor-detects-rewritten-base.md`, PR #60 mergiata il 13/09, stato lasciato `Needs Work` dal giro di correzioni e mai riportato a `Done`; lo stato è stato corretto a mano il 15/09, quindi **non** lo troverai più nel repo — ricostruiscilo come fixture nel test.
- Non allargare lo scope: niente controlli nuovi su `next-wave.sh`, che legge lo stato dal file ed è corretto così com'è. Il difetto è il file, non il lettore.
- L'oracolo è il comportamento dichiarato qui, non `doctor.sh` com'è oggi.
- `timeout` e `gtimeout` non esistono su macOS: comandi in primo piano.
- Misura lo sforzo in minuti d'orologio (`date +%s` nel primo e nell'ultimo comando) e riporta `Effort: N min elapsed (budget 90 min) — wt:{basename di `$PWD`}`.
- Il repo è pubblico: nessun riferimento a progetti dell'utente.
