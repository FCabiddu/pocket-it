# PI-38 — `gh pr merge --delete-branch` fallisce la pulizia da una worktree e il ramo remoto sopravvive

**Status**: Done
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: S
**Budget**: 90 min
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: `bin/cleanup-merged.sh`, `bin/cleanup-merged.test.sh`, `.claude/skills/run-wave/SKILL.md` (Step 5), `.claude/skills/quickfix/SKILL.md` (passo di merge)
**TAD**: none — convenzioni di `bin/cleanup-merged.sh`
**Contract**: `cleanup-merged.sh` continua a stampare la sua riga di riepilogo e a non toccare worktree sporche, bloccate o non mergiate.
**Branch**: task/pi-38-merge-leaves-remote-branch-alive
**PR**: —

## Goal
Il passo di merge di entrambe le skill è `POCKET_IT_USER_MERGE=1 gh pr merge {n} --squash --delete-branch`. Il merge riesce sempre; la **pulizia** no, e in due modi diversi a seconda di dove viene lanciato il comando:

- da una worktree: `gh` fallisce con `fatal: 'main' is already used by worktree …` e si ferma prima di cancellare il ramo **remoto**, che sopravvive;
- dal checkout principale, quando il ramo di task è ancora usato da una worktree di agente: `failed to delete local branch …`, il remoto viene cancellato ma il locale no.

In nessuno dei due casi `gh` esce con errore in modo visibile nel flusso, quindi nessuno se ne accorge. Misura del 15/09/2026 su pocket-it: **30 PR mergiate su 60 hanno ancora il loro ramo su `origin`**, dalla #18 alla #66. `git branch -r` ne elenca 38 diversi da `main`. Il conteggio va rifatto, non copiato: usa `gh pr list --state merged --limit 100 --json number,headRefName` e `git show-ref` sui rami remoti.

Il danno da evitare non è l'estetica dell'elenco: un ramo remoto che sopravvive a un merge squash è un ramo che qualcuno può ripescare come se fosse lavoro vivo, e nasconde nell'elenco i rami davvero aperti. `cleanup-merged.sh` esiste già e viene lanciato da entrambe le skill subito dopo il merge, ma oggi si occupa di worktree e rami **locali**: è il posto giusto in cui mettere anche il remoto.

## Acceptance criteria
- [ ] AC1 — Given una PR mergiata il cui ramo remoto esiste ancora, when si lancia `bash bin/cleanup-merged.sh`, then il ramo remoto viene cancellato e il riepilogo lo conta in una voce propria (per esempio `… , N rami remoti cancellati`).
- [ ] AC2 — Given la classe completa degli stati in cui un ramo remoto **non** va toccato, when si lancia lo script, then nessuno di questi viene cancellato: PR aperta; PR chiusa senza merge; ramo senza PR; ramo protetto o di base (`main`, `master`, e la base di un progetto `branching: epic`); ramo con commit non ancora presenti in nessuna PR mergiata. Un test positivo e uno negativo per ciascuno.
- [ ] AC3 — Given che il merge è squash, when lo script decide se un ramo è mergiato, then **non** usa `git merge-base --is-ancestor`, che con lo squash è falso per costruzione, ma lo stato della PR. Il test rende esplicito questo caso: un ramo il cui contenuto è dentro `main` per squash e i cui commit non sono antenati di `main`.
- [ ] AC4 — Given un ambiente senza `gh`, senza rete o senza permessi di scrittura sul remoto, when si lancia lo script, then la parte remota si salta in silenzio, lo script esce 0 e la pulizia locale avviene comunque. Nessuna attesa lunga.
- [ ] AC5 — Given lo Step 5 di `run-wave` e il passo di merge di `quickfix`, when si legge il testo, then dicono che l'esito della pulizia di `gh pr merge --delete-branch` non è affidabile e che il ramo lo chiude `cleanup-merged.sh`, lanciato subito dopo — senza far dipendere niente dal codice di uscita di `gh`.

## Tests expected
Casi nuovi in `bin/cleanup-merged.test.sh` per AC1, AC2 (positivo e negativo per ogni dimensione), AC3 e AC4, con `gh` simulato e remoti finti creati dal test: **nessuna chiamata di rete vera e nessuna cancellazione su un remoto vero durante i test**. Una mutazione eseguita: togli il controllo dello stato della PR e mostra che i casi negativi di AC2 cominciano a cancellare rami che non dovrebbero.

## Notes
- Non risolvere il problema rendendo più rumoroso `gh`: l'uscita di `gh pr merge` resta ignorata di proposito, perché il merge è riuscito e non va rifatto. La pulizia è un passo separato e deve essere idempotente.
- La bonifica dei 30 rami già rimasti indietro **non** fa parte di questo task: prima si chiude la falla, poi si passa lo script una volta sola. Dillo nel report, non farlo.
- L'oracolo è il comportamento dichiarato qui, non `cleanup-merged.sh` com'è oggi.
- `timeout` e `gtimeout` non esistono su macOS: comandi in primo piano.
- Riporta lo sforzo nel formato corrente di `shared/implementing-common.md` §7, che è cambiato oggi: leggilo lì invece di copiarlo da un report vecchio.
- Il repo è pubblico: nessun riferimento a progetti dell'utente.
