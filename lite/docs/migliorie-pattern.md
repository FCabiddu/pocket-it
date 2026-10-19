# Migliorie al flusso `lite` dai pattern agentici — piano tecnico

Piano per Claude. Il perché di ogni punto sta nel Claude Doc «Il flusso di agenti a confronto con i pattern agentici»; qui c'è solo il come.
Stato di partenza: `origin/main` del 2026-10-06 (dopo la PR #74).

## Regole per chi esegue il piano

- Ogni miglioria è un **lavoro piccolo**: un branch `lite/<nome>` da `origin/main` (con `worktree-new.sh`), una PR, i suoi `-cases.sh`.
- Le migliorie toccano regole, agenti o hook: **prima del merge si mostra il diff all'utente** e si aspetta l'ok (regola «Riferire»).
- Ogni hook nuovo ha il suo `<nome>-cases.sh` accanto, nello stile di `lite/hooks/log-errors-cases.sh`: cartelle temporanee, variabili `*_DIR` solo per le prove, `PASS`/`FAIL`, exit 1 se un caso fallisce. Ogni caso deve poter fallire: prima di aprire la PR si rompe l'hook di proposito e si incolla nel corpo l'output rosso.
- Gli hook non bloccano mai per errore proprio: `exit 0` in fondo, `2>/dev/null` sul python, come `log-errors.sh`. Solo gli hook di guardia (punto 5) bloccano, e solo con exit 2 e un messaggio.
- I campi degli eventi hook marcati «da verificare» si controllano **prima** di scrivere il codice, con l'hook di cattura del punto 2.0.
- Ordine: 1 → 2 → 3 → 4, poi 5, 6, 7, 8 in qualsiasi ordine. Un punto alla volta, ognuno mergiato prima del successivo.

---

## 1. Mergiare #75 e #73

PR aperte: #75 `lite/agenti-checkout-principale`, #73 `lite/corpo-pr`.

1. `gh pr view <n> --json mergeable,mergeStateStatus,baseRefName` per entrambe.
2. Se una è indietro rispetto a main: worktree del suo branch, `git merge origin/main`, risolvere i conflitti, rilanciare i suoi `-cases.sh`, push normale.
3. Mostrare all'utente il diff finale (`gh pr diff <n>`), ok, poi `gh pr merge <n> --squash --repo <utente>/<repo>`.
4. Verifica: `git show origin/main:lite/hooks/cd-principale.sh` contiene la parte di #75; i `-cases.sh` di entrambe sono verdi su main.

---

## 2. Registro dei lanci (observability)

Obiettivo: per ogni lancio di un subagente una riga con chi, quanto è durato, quanti turni e token, come è finito. Oggi `log-errors.sh` vede solo gli errori.

### 2.0 Cattura dei campi reali (prima di tutto)

I campi verificati sulla documentazione: SubagentStart e SubagentStop hanno `agent_type`, `agent_id`, `transcript_path`; SubagentStop ha anche `last_assistant_message`. `agent_transcript_path` **non esiste**. Non verificato: dove sta il transcript del subagente e se contiene `usage` per messaggio.

Passi:
1. Hook temporaneo in `~/.claude/settings.json` su `SubagentStart`, `SubagentStop`, `PreCompact`: `cat >> ~/.claude/logs/cattura.jsonl; echo >> ~/.claude/logs/cattura.jsonl`.
2. Lanciare un subagente qualsiasi (per esempio `Explore` con una domanda breve).
3. Leggere `cattura.jsonl`; con `transcript_path` cercare il file del subagente (`ls "$(dirname <transcript_path>)"/<session_id>/` e simili) e controllare che le righe abbiano `message.usage` con `input_tokens`, `output_tokens`, `cache_read_input_tokens`.
4. Togliere l'hook temporaneo e cancellare `cattura.jsonl`.
5. Scrivere in testa a `log-lanci.sh` i campi trovati davvero. Se il transcript del subagente non si trova, il registro tiene solo durata ed esito, e i token restano a OTel (punto 9).

### 2.1 `lite/hooks/log-lanci.sh`

Un solo script per tre eventi, scrive in `${LANCI_DIR:-$HOME/.claude/logs/lanci}/<data>.jsonl`, pulizia a 30 giorni (una volta al giorno, come `log-errors.sh`).

- `SubagentStart`: scrive `{"ora", "evento":"start", "sessione", "agent_id", "agente", "cwd"}`.
- `SubagentStop`: scrive `{"ora", "evento":"stop", "sessione", "agent_id", "agente", "cwd", "esito", "turni", "token_in", "token_out", "token_cache", "ultimo"}` dove:
  - `esito` da `last_assistant_message` (prime righe), con regole fisse e nessun LLM:
    `APPROVED`/`CHANGES` (reviewer), `E2E VERDE`/`E2E ROSSO`/`E2E SCRITTI` (tester), un link `github.com/.../pull/<n>` (developer: `pr`), altrimenti `altro`;
  - `turni` e `token_*` dal transcript del subagente, se il 2.0 li ha trovati; altrimenti assenti;
  - `ultimo`: i primi 300 caratteri di `last_assistant_message`.
- `PreCompact`: scrive `{"ora", "evento":"compact", "sessione", "agent_id"?, "agente", "trigger"}` (matcher `manual`/`auto`). Non blocca.
- La durata non si salva: la calcola `errori.sh` dalla coppia start/stop con lo stesso `agent_id`.

Configurazione in `~/.claude/settings.json` (tre voci, tutte `"timeout": 10`):

```json
"SubagentStart": [{"hooks": [{"type": "command", "command": "bash ~/Desktop/agents/lite/hooks/log-lanci.sh", "timeout": 10}]}],
"SubagentStop":  [{"hooks": [{"type": "command", "command": "bash ~/Desktop/agents/lite/hooks/log-lanci.sh", "timeout": 10}]}],
"PreCompact":    [{"hooks": [{"type": "command", "command": "bash ~/Desktop/agents/lite/hooks/log-lanci.sh", "timeout": 10}]}]
```

`settings.json` non è nel repo: nella PR si mette il blocco nel corpo e nel README degli hook (se c'è) e lo si applica a mano dopo il merge, con l'ok dell'utente.

### 2.2 Riassunto in `lite/bin/errori.sh`

Stesso segnaposto `.letto-<hash>` già usato; legge anche `LANCI_DIR`. Dopo «Falliti di nuovo» aggiunge:

```
Lanci: 9 (developer 5, reviewer 3, tester 1)
- developer   5  durata media 14m, max 31m   turni max 162/200   esiti: pr 4, altro 1
- reviewer    3  durata media 4m             esiti: APPROVED 2, CHANGES 1
- tester      1  durata 22m                  esiti: E2E VERDE 1
Vicini al limite di turni (≥ 80% di maxTurns): developer a1b2 162/200
Compattazioni: 1 (developer a1b2, auto)
Senza stop (forse ancora in corso o interrotti): reviewer c3d4 dalle 10:42
```

`maxTurns` si legge dal frontmatter di `~/.claude/agents/<agente>.md` (se non c'è, la riga «vicini al limite» non si stampa per quell'agente). Filtro per repo identico a quello degli errori (`cwd` dentro `repo`).

### 2.3 Prove: `lite/hooks/log-lanci-cases.sh`

Casi minimi (ognuno deve diventare FAIL se si toglie la riga che lo realizza):
1. start + stop con lo stesso `agent_id` → `errori.sh` stampa una durata.
2. `last_assistant_message` che inizia con `CHANGES — 1)` → esito `CHANGES`.
3. testo con `https://github.com/x/y/pull/12` → esito `pr`.
4. start senza stop → riga «Senza stop».
5. stop con 170 turni e `maxTurns: 200` → riga «Vicini al limite».
6. PreCompact `auto` → «Compattazioni: 1».
7. evento con `cwd` di un altro repo → non compare.
8. secondo lancio di `errori.sh` senza eventi nuovi → «Lanci: 0».
9. JSON rotto in ingresso → exit 0 e nessuna riga scritta.

---

## 3. Tabellone delle metriche per onda

File del progetto: `docs/recap/metriche.md`, una riga per onda, scritta da `errori.sh` con un'opzione nuova:

```
errori.sh --onda <slug>-<n> --regole v7
```

Colonne: `data | onda | regole | task | PR | giri di review (CHANGES) | RIGIRA | lanci | durata totale | token (se disponibili) | danni | attriti`.

- `task`, `PR`, `CHANGES`, durate e token: dal registro dei lanci (punto 2) nella finestra dal segnaposto precedente.
- `RIGIRA`: numero di stop del tester oltre il primo nella finestra.
- `danni` e `attriti`: li scrive la sessione principale dopo la lettura (`errori.sh` mette `?`).
- `regole`: la versione scritta in testa a `lite/CLAUDE.md` (`grep -m1 -o 'v[0-9]\+'`), se `--regole` manca.
- Se il file non esiste lo crea con l'intestazione. Aggiunge, non riscrive.

Modifica a `lite/CLAUDE.md`, sezione «Errori e regole», prima riga: «A fine onda lancia `errori.sh --onda <slug>-<n>`…»; e la riga del tabellone va nella PR di documenti insieme agli attriti. Il passo 7 della feature resta com'è.

Prove (in `log-lanci-cases.sh` o in un `errori-cases.sh` nuovo): file creato con intestazione; seconda onda aggiunge una riga; `CHANGES` contati giusti; `--regole` assente legge la versione dal file.

---

## 4. Note di avanzamento e commit a ogni criterio verde

Problema: developer, tester e task-writer arrivati a fine turni hanno perso lavoro non committato (`attriti.md` di un progetto). Pattern: structured note-taking + checkpoint.

Modifiche (solo testo degli agenti, in `lite/.claude/agents/`):

- `developer.md`, dopo il passo 4: «Each time an acceptance criterion turns green, commit locally (`wip: <criterio>`), without pushing. Keep `NOTE.md` at the worktree root, never committed (add it to `.git/info/exclude`): the criteria done, the one in progress, the last command and its result. If you start and `NOTE.md` exists, read it first and continue from there.»
- `tester.md`: stessa regola, commit dopo ogni spec scritto.
- `task-writer.md`: commit dopo ogni task scritto.
- Il passo 8 del developer resta: i commit `wip:` finiscono nello squash di `merge-pr.sh`, quindi su main non si vedono.

Ripresa: se il registro (punto 2) mostra un agente fermo vicino a `maxTurns`, la sessione principale rilancia lo stesso agente sullo **stesso worktree** con «Riprendi da NOTE.md». Da aggiungere in `lite/CLAUDE.md`, passo 5 o in una riga sotto «La sessione principale non scrive codice…».

Verifica: non si prova con uno script. Si guarda nel tabellone (punto 3) che i lanci «Senza stop» o «Vicini al limite» non producano più lavoro perso nelle due feature successive; se nel frattempo succede, è un danno e si riapre.

---

## 5. Livelli di rischio e hook dei comandi costosi (HITL)

### 5.1 Tabella in `lite/templates/README.md`

| Livello | Esempi | Chi decide |
|---|---|---|
| libero | test, lint, build locali, git sul proprio branch | l'agente |
| con traccia | `gh pr create`, `npm install`, chiamate a servizi di test | l'agente, e finisce nel corpo della PR |
| solo con ok | chiamate AI a pagamento, DB con dati veri, deploy, invio di email | l'utente, tramite la sessione principale |

### 5.2 Riga nuova nel `CLAUDE.md` del progetto

```
Comandi solo con ok: <regex>, <regex>, ...
```

Esempio: `Comandi solo con ok: netlify deploy, supabase db push, node scripts/genera-.*\.mjs`. `progetto-pronto.sh` controlla che la riga ci sia (anche vuota: `Comandi solo con ok: nessuno`), come fa con `Deploy da main:`.

### 5.3 `lite/hooks/comandi-costosi.sh` (PreToolUse, matcher `Bash`)

- Si applica solo ai subagenti (`agent_type` presente); la sessione principale passa, perché è lei che chiede l'ok.
- Trova il `CLAUDE.md` del progetto dal `cwd` (`git rev-parse --git-common-dir`, poi la sua cartella), legge la riga `Comandi solo con ok:`, divide sulle virgole.
- Se il comando combacia con una regex: exit 2, messaggio «comando solo con ok dell'utente (`CLAUDE.md` del progetto): fermati e chiedilo nel report».
- Nessuna riga o «nessuno»: passa.
- Registrare in `~/.claude/settings.json` sotto il matcher `Bash` esistente, accanto a `guard.sh`.

Prove (`comandi-costosi-cases.sh`): developer + comando in lista → exit 2; principale + stesso comando → 0; comando non in lista → 0; progetto senza riga → 0; regex con spazi intorno alla virgola → funziona; comando in lista dentro `bash -c '...'` → exit 2.

---

## 6. Sandbox sui comandi degli agenti (sicurezza)

Da **provare prima su un progetto**, non da mettere subito nel `settings.json` globale. Copre solo Bash/PowerShell/Monitor: Read, WebFetch e gli hook ne restano fuori; `denyRead` non ferma il tool Read (serve `permissions.deny`).

Configurazione da provare nel `.claude/settings.json` di un progetto (per esempio il più piccolo):

```json
{
  "sandbox": {
    "enabled": true,
    "network": {
      "allowedDomains": ["github.com", "api.github.com", "*.githubusercontent.com", "registry.npmjs.org", "localhost"]
    },
    "filesystem": {
      "denyRead": ["**/.env*", "~/.ssh", "~/.aws"]
    }
  },
  "permissions": {
    "deny": ["Read(**/.env*)"]
  }
}
```

Punti aperti da verificare nella prova, uno per uno, scrivendo il risultato nella PR:
1. Gli E2E del tester leggono le credenziali da `.env.local`: con `denyRead` su `.env*` si rompono. Opzioni: escludere il comando E2E (`sandbox.excludedCommands`) o leggere le variabili con lo script `scripts/e2e.sh` lanciato fuori sandbox. Decide l'utente.
2. `gh` e `git push` passano con `allowedDomains` GitHub? Verificare con un push vero su un branch di prova.
3. Il dev server e Playwright su `localhost` funzionano dentro la sandbox?
4. `worktree-new.sh` collega `.env.local` in symlink: con `permissions.deny` su `Read(**/.env*)` gli agenti non lo leggono più col tool Read, ma Next/Vite sì (processo figlio di Bash, sotto la sandbox). Verificare.

Solo se tutti e 4 hanno una risposta si porta la config nei modelli di `lite/templates/` e la si cita in `progetto-pronto.sh`.

**Esito della prova (2026-10-16, su un progetto Next.js)**, fatta con `claude -p … --model haiku --allowedTools Bash` dal worktree con la config del repo:
1. Gli E2E non leggono `.env.local`: `scripts/e2e.sh` prende le credenziali dalle variabili esportate nella shell (`supabase status`), quindi `denyRead` su `.env*` non li tocca e non si esclude niente. Il symlink `.env.local` di `worktree-new.sh` è bloccato anche per `cat`, `node` e Next (la sandbox risolve il symlink); Next parte lo stesso con una riga di errore.
2. `gh` fallisce dentro la sandbox (`tls: failed to verify certificate`, programmi Go): va in `excludedCommands` con gli script di `lite/bin` che lo usano, e vale solo per una chiamata pura (niente pipe, `$(...)`, `cd`). `git push` passa in HTTPS e fallisce in SSH: il remote dei progetti va in HTTPS.
3. Dev server e `curl` su localhost funzionano con `allowLocalBinding`; Playwright elenca i test; Chromium parte solo con `--single-process` (in `playwright.config.ts` sotto `SANDBOX_RUNTIME`); `pgrep`/`pkill` con `com.apple.sysmond` in `allowMachLookup`.
4. Con `permissions.deny` su `Read(**/.env*)` il tool Read non lo legge; sotto la sandbox non lo leggono nemmeno i processi figli (punto 1).

In più: una chiave con il tipo sbagliato (`allowMachLookup: true`) fa ignorare tutto il file senza avviso e la sessione gira senza sandbox. La config sta in `lite/templates/settings.json`; `progetto-pronto.sh` controlla chiavi e tipi (`progetto-pronto-cases.sh`); `lite/templates/README.md`, «Sandbox», dice il resto. Resta attiva solo su quel progetto finché un altro progetto non la copia.

---

## 7. Revisione di sicurezza sulle PR sensibili

Niente agente nuovo: una sezione in `lite/.claude/agents/reviewer.md`.

- Testo: «If the PR touches authentication, payments, personal data, file uploads, SQL or shell built from input, or the env file, add a `Sicurezza` section to your report: input validated, secrets not logged or committed, authorization checked server side, no new dependency from an unknown publisher. A point there is a `CHANGES` point like the others.»
- Elenco dei percorsi sensibili: riga facoltativa `File sensibili: <glob>, ...` nel `CLAUDE.md` del progetto; senza, il reviewer decide dai nomi.

Prova: una PR di prova che logga una variabile d'ambiente in un handler di login → il reviewer deve rispondere `CHANGES` con un punto in `Sicurezza`. È una prova a mano, da scrivere nel corpo della PR con il report ottenuto.

---

## 8. Criterio misurabile «lavoro piccolo o feature»

In `lite/CLAUDE.md`, «Come si lavora», primo punto, sostituire «(bug, modifica, refactor limitato)» con:

«È lavoro piccolo se tutte e tre: tocca al massimo 5 file, non serve una scelta tecnica nuova (nessuna voce nuova nelle direttive), non ci sono requisiti da chiedere all'utente. Altrimenti è una feature. Nel dubbio lo dici all'utente con la tua proposta.»

Nessuna prova a script; si misura dal tabellone: feature con 1 onda e ≤ 2 task sono segnale che il criterio va abbassato.

---

## 9. OpenTelemetry (facoltativo, solo se serve un pannello)

Da fare solo se il registro dei lanci (punto 2) non dà i token o se l'utente vuole un pannello.

Variabili, in `~/.claude/settings.json` sotto `env`:

```json
"CLAUDE_CODE_ENABLE_TELEMETRY": "1",
"OTEL_METRICS_EXPORTER": "otlp",
"OTEL_LOGS_EXPORTER": "otlp",
"OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4317",
"OTEL_LOG_TOOL_DETAILS": "1"
```

- Metriche utili: `claude_code.cost.usage`, `claude_code.token.usage` con attributi `agent.name` (senza `OTEL_LOG_TOOL_DETAILS=1` i nomi degli agenti personalizzati diventano `custom`) e `query_source` (`main`/`subagent`). Evento `claude_code.tool_result`.
- Tracce: beta, richiedono `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1` e `OTEL_TRACES_EXPORTER`.
- Collector locale: un `otel-collector` in Docker che scrive su file è sufficiente; nessun servizio esterno senza ok dell'utente (i dati escono dalla macchina).
- `OTEL_LOG_TOOL_DETAILS=1` mette nei log anche gli input dei tool: con un exporter remoto possono uscire percorsi e comandi. Con exporter locale va bene.

---

## Cosa non fare

- Niente LLM-as-judge automatico sulle PR, niente voto tra più reviewer, niente pannello esterno: si riconsiderano solo se il tabellone mostra un problema che solo loro risolvono.
- Non cambiare `log-errors.sh`: il registro dei lanci è un file e una cartella separati, così le due cose si provano da sole.
- Non mettere la sandbox nel `settings.json` globale prima della prova del punto 6.
