# pocket-it

Questa cartella è `~/.claude/agents` (symlink). Contiene i pacchetti di agenti che Claude Code carica da `~/.claude/agents/**/.claude/agents/*.md`: il checkout locale deve stare su main, aggiornato dopo ogni merge, e gli agenti si leggono all'avvio di una sessione.

| Cartella | Cosa |
|---|---|
| `lite/` | Il sistema per il lavoro sul software (dal 22/09/2026), spiegato sotto |
| `mvp-builder/` | Pacchetto per costruire siti statici, con il suo `design-compass.md` |
| `legal-advisor/` | Pacchetto per privacy, cookie e termini |
| `legal-check/` | Verifica legale dei propri prodotti (giochi di carte, da tavolo, gioco di ruolo online con master): diritti e licenze, privacy, pagamenti, marketing, sicurezza prodotto, AI, disclaimer di terze parti. Scrive un report, non tocca il prodotto |
| `link-skills.sh` | Ricostruisce `~/.claude/skills` da tutte le cartelle `*/.claude/skills/*/` |

## lite

`lite/CLAUDE.md` sono le regole globali: si installano copiandolo in `~/.claude/CLAUDE.md`. Il flusso, in tre diagrammi, sta in [`lite/FLUSSO.md`](lite/FLUSSO.md).

### Chi lavora

- **Sessione principale**: lancia gli agenti, porta le loro domande all'utente, mergia e riferisce. Durante un'onda non scrive codice.
- **`analyst`**: trasforma la richiesta in requisiti verificabili (`docs/features/<slug>/requisiti.md`) e dice cosa si può fare sul codice di oggi. I requisiti sono l'unico documento che l'utente approva.
- **`architect`**: sceglie la soluzione tecnica e scrive il design: un indice `design-tecnico.md` e un file per argomento in `design-tecnico/`, al massimo 150 righe ciascuno; le alternative scartate e le parti già mergiate vanno in `archivio/`, che nessun task cita. Tiene aggiornate le direttive del progetto (stack, pattern, test, invarianti) e controlla i task prima che partano.
- **`task-writer`**: divide il design in task piccoli, una PR ciascuno con i criteri e il loro comando, raggruppati in onde; per ogni onda scrive anche il task `E2E-<n>` del tester.
- **`developer`**: fa un task sul suo worktree, esegue i test veloci (unit, lint, typecheck), apre la PR con i risultati e corregge quello che chiede il reviewer.
- **`reviewer`**: legge il codice e i risultati riportati nella PR, senza lanciare test, rispetto al task e alle direttive; risponde APPROVED oppure CHANGES. Non mergia.
- **`security`**: guarda il progetto da attaccante, con i principi di `lite/docs/sicurezza.md`. Una volta all'inizio analizza tutto il progetto (Audit); a fine onda, in parallelo al tester, cerca i buchi aperti dal diff dell'onda. Senza il suo ok (`sicurezza-ok.sh`) `merge-pr.sh` non porta l'onda su main. Non scrive codice.
- **`tester`**: a fine onda, sul branch dell'onda, scrive gli E2E e li lancia una volta insieme a quelli che coprono i file cambiati. Ogni rosso diventa una correzione del suo test, un test instabile o un errore dell'app, che passa a un developer come task.

**Onda**: gruppo di task indipendenti che girano in parallelo su un branch `onda/<slug>-<n>`. Arriva su main solo con gli E2E verdi, e l'onda dopo parte da lì.

### Script (`lite/bin/`)

| Script | Quando | Cosa fa |
|---|---|---|
| `worktree-new.sh <branch> [base]` | prima di lanciare un agente | Crea il worktree dell'agente (con `NOTE.md`, il punto del lavoro dell'agente, escluso da git); `--review <PR>` per quello del reviewer |
| `design-check.sh` | l'architect, quando controlla i task | Segnala file del design oltre 150 righe, citazioni a titoli che non esistono o all'archivio, task senza «Da leggere» |
| `progetto-pronto.sh [--prova]` | una volta, all'inizio di un progetto | Controlla che il progetto abbia direttive, le righe `E2E:`, `Deploy da main:` e `Comandi solo con ok:` in `CLAUDE.md`, `scripts/pre-merge.sh`, `scripts/e2e.sh`, `scripts/e2e-scelta.sh` e `.claude/settings.json` con la sandbox (chiavi e tipi); se manca qualcosa, lo crea l'architect dai modelli |
| `merge-pr.sh <PR>` | a PR approvata | Controlla il piano `tasks/<slug>/INDEX.md` se la PR tocca `tasks/` (`piano.sh`), lancia `scripts/pre-merge.sh` del progetto (senza, non mergia), per un'onda verso main vuole l'ok del security, mergia nella base della PR e toglie worktree e branch |
| `sicurezza-ok.sh <PR>` | dopo `SICUREZZA OK` del security | Segna il commit di testa della PR dell'onda (stato «security»); un commit aggiunto dopo chiede un nuovo controllo |
| `stop-worktree-procs.sh <dir>` | dentro `merge-pr.sh` | Ferma i processi rimasti accesi in un worktree (server, watcher) prima di toglierlo |
| `errori.sh --onda <slug>-<n> [--regole v7]` | a fine onda | Mostra gli errori registrati dopo il lancio precedente e il riassunto dei lanci degli agenti (quanti per tipo, durate, turni, token, esiti, chi è vicino al limite di turni, chi ha compattato, chi è partito senza finire); con `--onda` aggiunge la riga dell'onda al tabellone `docs/recap/metriche.md` del progetto (task, PR, giri di review, RIGIRA, lanci, durata, token; `danni` e `attriti` li compila chi legge) |
| `pulisci-onda.sh <slug> <onda> <PR>` | a fine onda, dopo il controllo degli errori | Toglie da main i task dell'onda con una PR che mergia da sola (all'ultima onda anche `tasks/<slug>` e `docs/features/<slug>`); `--prova` mostra cosa farebbe |

### Modelli per il progetto (`lite/templates/`)

Gli agenti sono uguali per ogni progetto; quello che cambia sta in pochi script del progetto con un uso fisso: `pre-merge.sh` (controlli veloci prima del merge), `e2e.sh` (un giro E2E alla volta, con fila e registro), `e2e-scelta.sh` con `spec-per-cartella.txt` (quali spec lanciare dai file cambiati). Su un progetto nuovo l'architect li copia da qui e adatta solo il blocco «DA ADATTARE». Cosa deve fare ciascuno: [`lite/templates/README.md`](lite/templates/README.md).

A fine onda gli errori si dividono in **danni** (lavoro perso, dati toccati senza consenso, soldi spesi, push su main, codice sbagliato su main, task fermo senza via d'uscita: si scrive un recap) e **attriti** (tutto il resto: una riga in `docs/recap/attriti.md`; alla terza volta diventa un danno).

### Hook (`lite/hooks/`)

Ogni hook ha il suo file di casi `<nome>-cases.sh`, che si lancia dopo ogni modifica.

- **`guard.sh`**: blocca i push su main e i force push, ignorando il testo dentro heredoc e virgolette; si scavalca con `ALLOW_MAIN_PUSH=1`.
- **`reviewer-edit.sh`** (PreToolUse su `Edit|Write|NotebookEdit`): gli agenti scrivono solo dentro `.claude/worktrees/`.
- **`cd-principale.sh`** (PreToolUse su `Bash`): la sessione principale non entra con `cd` o `pushd` in `.claude/worktrees/`, perché la shell resterebbe lì; passano `git -C`, i percorsi assoluti e `(cd <worktree> && …)`. Gli agenti invece non lanciano git che cambia stato (`merge`, `checkout`, `reset`, `commit`…) nel checkout principale, anche dopo un `cd` fallito. Casi in `cd-principale-cases.sh`.
- **`read-limit.sh`** (PreToolUse su `Read|Bash`): developer, reviewer e tester leggono al massimo 300 righe di un file per volta, con Read, `cat` o `sed -n`.
- **`memoria-globale.sh`** (PreToolUse su `Edit|Write|NotebookEdit|Bash`): nella memoria globale (`~/.claude/projects/<home>/memory/`) non entra niente di un progetto. Blocca le memorie `type: project` e quelle che nominano un progetto (repo git sotto `~/Desktop` o cartelle con una memoria propria); ogni altra scrittura lì, anche da Bash, chiede conferma all'utente. Casi in `memoria-globale-cases.sh`.
- **`comandi-costosi.sh`** (PreToolUse Bash): ferma un subagente che lancia un comando della riga `Comandi solo con ok:` del `CLAUDE.md` del progetto (deploy, DB con dati veri, chiamate a pagamento) e gli dice di chiederlo nel report; la sessione principale passa (`lite/templates/README.md`).
- **`log-errors.sh`**: registra i permessi negati e i comandi falliti in `~/.claude/logs/errori/`, che poi `errori.sh` legge.
- **`log-lanci.sh`** (SubagentStart, SubagentStop, PreCompact): registra ogni lancio di agente in `~/.claude/logs/lanci/` (tipo, esito letto dalle prime righe del report, turni, token e modello dal transcript del subagente, compattazioni), che poi `errori.sh` riassume. Sparisce da solo dopo 30 giorni, non blocca mai niente.

Ogni agente ha solo le istruzioni del suo lavoro. Una regola nuova la approva il proprietario.
