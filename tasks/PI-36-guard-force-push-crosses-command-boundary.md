# PI-36 — La guardia sui force-push legge oltre il confine di comando e blocca un push legittimo

**Status**: Done
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: XS
**Budget**: 45 min
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: `.claude/hooks/guard.sh` (riga ~374), `.claude/hooks/guard.test.sh`
**TAD**: none — segui le convenzioni del file (il classificatore dei push in Python più in alto nello stesso file segmenta già per confine di comando)
**Contract**: uscita 0 = consentito, uscita 2 = bloccato con messaggio su stderr. Invariato.
**Branch**: task/pi-36-guard-force-push-boundary
**PR**: https://github.com/FCabiddu/pocket-it/pull/70

## Goal
L'ultima riga di `guard.sh` è un `grep` piatto:

```
grep -qE 'git[[:space:]]+push[[:space:]]+.*(--force|-f)\b.*(main|master)' <<<"$CMD" && block "force-push to main"
```

`.*` attraversa `&&`, `;` e `|`, quindi la parola `main` che chiude il **comando successivo** viene letta come destinazione del push. Riproduzione misurata il 15/09/2026 su `main` di pocket-it:

```
git push --force-with-lease origin task/foo && gh pr create --base main --title x --body y
→ [2] BLOCKED by pocket-it guard: force-push to main
```

Il push è su `task/foo`, non su `main`; `--base main` appartiene a `gh pr create`. È il gesto normale con cui un agente pusha un branch riscritto e apre la PR, e oggi è impossibile in un comando solo. Stessa famiglia dei push negati ai reviewer.

Il danno da evitare è **riscrivere la storia del ramo base**, non la presenza della parola `main` in una riga. Il file contiene già il pezzo che sa distinguerlo: il classificatore Python più in alto segmenta il comando sui confini (`; & && || | |& ( )`), riconosce i refspec, `+ref`, `-f/--force*`, le cancellazioni e `--mirror/--prune/--all`, e sa quali segmenti hanno `push` come sottocomando git.

## Acceptance criteria
- [x] AC1 — Given un comando in cui il segmento del `git push` non tocca il ramo base, when la guardia lo valuta, then l'uscita è 0, **qualunque cosa contengano gli altri segmenti**. La classe da coprire, non gli esempi: per ogni separatore di comando (`&&`, `||`, `;`, `|`, `|&`, newline) e per ogni modo in cui `main`/`master` può comparire dopo il push (`gh pr create --base main`, `gh pr merge … --base master`, un commento, un `echo`, un argomento `--body` che nomina main, una variabile `$BASE`), il push su un branch di task resta consentito.
- [x] AC2 — Given un force-push che raggiunge davvero il ramo base, when la guardia lo valuta, then l'uscita è 2 con il messaggio attuale. Copri l'intera classe di forme che oggi il classificatore Python già conosce: `-f`, `--force`, `--force-with-lease`, `--force-if-includes`, il `+` davanti al refspec, `HEAD:main`, `main`, `refs/heads/main`, il refspec corrispondente (`git push -f origin :`), `--all`/`--mirror` con force, e il caso in cui il branch corrente **è** la base e il refspec è implicito.
- [x] AC3 — Given le altre guardie del file (push alla base senza prefisso, `gh pr merge` senza prefisso, `pkill/killall`, `APP_STATUS → prod`, `sleep N && …`), when si lancia la suite esistente, then nessuna cambia comportamento: `bash .claude/hooks/guard.test.sh` e `bash .claude/hooks/guard.heredoc.test.sh` restano verdi senza modifiche ai casi già presenti.
- [x] AC4 — Given la nuova logica, when si legge il file, then il controllo sul force dichiara il suo modello di minaccia in un commento: chi è l'avversario (un agente che riscrive la base per errore o per aggirare una review), cosa deve impedire (qualsiasi scrittura che rimpiazza o cancella la storia del ramo base su un remoto), e cosa esplicitamente **non** copre.

## Tests expected
Casi nuovi in `.claude/hooks/guard.test.sh`, uno per dimensione delle classi di AC1 e AC2 — non un caso per esempio citato nel Goal. Almeno una **mutazione eseguita**: togli la segmentazione per confine di comando e mostra che i casi di AC1 diventano rossi; rimettila. Niente test di integrazione.

## Notes
- L'oracolo è il comportamento dichiarato qui e il classificatore Python già nel file, **mai** l'implementazione corrente della riga 374: è proprio quella il difetto.
- Se il classificatore Python copre già tutto ciò che serve, la soluzione giusta può essere **cancellare** la riga 374 e lasciar decidere lui — ma solo dopo aver provato con i test che ogni forma di AC2 resta bloccata. Una riga in meno vale più di una regex più lunga.
- Verifica che la tua correzione non reintroduca il difetto: il test deve fallire sulla versione vecchia del file, non solo passare sulla nuova.
- `timeout` e `gtimeout` non esistono su macOS: lancia i comandi in primo piano.
- Misura lo sforzo in minuti d'orologio (`date +%s` nel primo e nell'ultimo comando) e riporta la riga `Effort: N min elapsed (budget 45 min) — wt:{basename di `$PWD`}`.
- Il repo è pubblico: nessun riferimento a progetti dell'utente.
