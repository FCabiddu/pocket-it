# Cosa il flusso lite si aspetta da un progetto

Gli agenti e gli script di `lite/bin/` sono uguali per ogni progetto; quello che cambia da un progetto all'altro sta in pochi file del progetto, con un uso fisso. `lite/bin/progetto-pronto.sh` controlla che ci siano: la sessione principale lo lancia una volta, all'inizio di un progetto, e se è rosso l'`architect` crea i pezzi mancanti partendo da questi modelli, li adatta allo stack e li prova.

| File del progetto | Chi lo usa | Cosa deve fare | Modello |
|---|---|---|---|
| `CLAUDE.md` con la riga `File delle direttive tecniche: \`<percorso>\`` | tutti gli agenti | dire dove sono le direttive | — |
| il file delle direttive | tutti gli agenti | stack, struttura, pattern, test, invarianti, sicurezza, ambiente (`architect.md`) | — |
| `docs/sicurezza/audit-<data>.md` | `security`, `progetto-pronto.sh` | la prima analisi di sicurezza di tutto il progetto (`security.md`, lavoro Audit) | — |
| `scripts/pre-merge.sh` | `merge-pr.sh`, prima di ogni merge | controlli veloci (typecheck, lint, unit) sul codice della PR unito alla base; exit 0 o 1. Senza, `merge-pr.sh` non mergia | `pre-merge.sh` |
| `scripts/e2e.sh <spec...>` | il `tester` | un giro E2E alla volta sulla macchina (fila sul posto), build se serve, riga nel registro `<git-common-dir>/e2e-giri/` | `e2e.sh` |
| `scripts/e2e-scelta.sh [--base] [--head] [--verifica]` | il `tester` | dai file cambiati, gli spec da lanciare su stdout e il perché su stderr; `--verifica` controlla la mappa | `e2e-scelta.sh` + `spec-per-cartella.txt` |
| `.claude/settings.json` | Claude Code, su ogni comando Bash degli agenti | la sandbox (sotto): rete solo verso GitHub e npm, niente lettura di `.env*`, `~/.ssh`, `~/.aws`, server su localhost permessi; `gh` e gli script di `lite/bin` che lo usano fuori sandbox | `settings.json` |

La riga `E2E:` in `CLAUDE.md` dice quando si lanciano gli E2E: `E2E: a fine onda` (il tester li lancia a ogni onda, passo 6 delle regole globali), `E2E: al rilascio` (il tester li scrive senza lanciarli, `e2e.sh` non parte salvo `E2E_FORZA=1`, e si lanciano solo nel giro prima del rilascio, per esempio con uno `scripts/rilascio.sh` come quello di app-demo: build, controlli, E2E) o `E2E: nessuno` (sotto). `progetto-pronto.sh` la chiede.

La riga `Deploy da main: sì` o `Deploy da main: no` in `CLAUDE.md` dice se un merge su main pubblica in produzione (e consuma build o crediti); `progetto-pronto.sh` la chiede, così la sessione principale lo sa e lo dice all'utente prima del primo merge su main. Con `sì`, ogni merge su main è un deploy e vale la regola globale: solo su istruzione esplicita.

La riga `Comandi solo con ok: <regex>, <regex>, ...` in `CLAUDE.md` elenca i comandi che un agente non lancia mai da solo: l'hook `lite/hooks/comandi-costosi.sh` ferma il subagente che ci prova (exit 2) e gli dice di chiederlo nel report; la sessione principale passa, perché è lei che chiede l'ok all'utente. Regex di Python separate da virgola (quindi senza virgole dentro), cercate nel testo del comando, anche dentro `bash -c '...'`; esempio: `Comandi solo con ok: netlify deploy, supabase db push, node scripts/genera-.*\.mjs`. Un progetto che non ne ha scrive `Comandi solo con ok: nessuno`. `progetto-pronto.sh` la chiede. I livelli:

| Livello | Esempi | Chi decide |
|---|---|---|
| libero | test, lint, build locali, git sul proprio branch | l'agente |
| con traccia | `gh pr create`, `npm install`, chiamate a servizi di test | l'agente, e finisce nel corpo della PR |
| solo con ok | chiamate AI a pagamento, DB con dati veri, deploy, invio di email | l'utente, tramite la sessione principale: la riga `Comandi solo con ok` |

Un progetto senza E2E (una libreria, una CLI provata solo da test unit) scrive `E2E: nessuno` in `CLAUDE.md`: niente `e2e.sh` né `e2e-scelta.sh`, e le onde non hanno il task del tester.

## Sandbox

`.claude/settings.json` (modello `settings.json`, provato il 2026-10-16 su un progetto Next.js) chiude ogni comando Bash degli agenti nella sandbox di Claude Code: scrive solo nel progetto e nelle cartelle temporanee, parla solo con `github.com`, `api.github.com`, `*.githubusercontent.com` e `registry.npmjs.org`, non legge `.env*` (nemmeno attraverso il symlink di `worktree-new.sh`), `~/.ssh` e `~/.aws`. `permissions.deny` su `Read(**/.env*)` serve a parte, perché `denyRead` non ferma il tool Read. Un progetto che ha bisogno di altri domini (un'API di test, un CDN) li aggiunge ad `allowedDomains`. Da sapere:
- `gh` non supera la verifica TLS dentro la sandbox (programmi Go, documentato da Claude Code), quindi sta in `excludedCommands` insieme agli script di `lite/bin` che lo chiamano (`merge-pr.sh`, `worktree-new.sh`, `sicurezza-ok.sh`, `pulisci-onda.sh`). L'esclusione vale solo per una chiamata pura: con una pipe, `$(...)`, `cd` o un altro comando nella stessa riga tutto resta in sandbox e `gh` fallisce. Per questo le PR si aprono con `--body-file` e `gh` non si chiama dentro altri script.
- `git fetch`/`push` passano solo con il remote in HTTPS (`https://github.com/<utente>/<repo>.git`, credenziali nel keychain): su SSH il proxy della sandbox non fa passare la connessione.
- Il server di sviluppo e `curl` su localhost funzionano (`allowLocalBinding`); `pgrep`/`pkill` funzionano con `com.apple.sysmond` in `allowMachLookup`. Chromium di Playwright non può registrare il suo servizio Mach e si chiude all'avvio: in `playwright.config.ts` si passa `--single-process` quando c'è `SANDBOX_RUNTIME`, fuori sandbox non cambia niente.
- Una chiave sbagliata (per esempio `allowMachLookup: true` al posto di una lista) fa ignorare tutto il file, sandbox compresa, senza fermare la sessione. `progetto-pronto.sh` controlla le chiavi e i tipi; nella sessione `/sandbox` dice se è attiva, e nei comandi in sandbox c'è `SANDBOX_RUNTIME=1`.

Nei modelli si cambia solo il blocco «DA ADATTARE»; il resto (fila, registro, uscita) è quello che gli agenti si aspettano. Un progetto può riscrivere `e2e-scelta.sh` con una logica più fine (per esempio seguendo gli import), purché tenga uso e uscita.
