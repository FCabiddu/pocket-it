# PI-34 — verify.sh e il reviewer creano le worktree usa e getta sotto .claude/worktrees, mai in /tmp

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
**Files**: `bin/verify.sh`, `bin/verify.test.sh`, `.claude/agents/reviewer.md`
**TAD**: none — follow existing conventions (`bin/worktree.sh`, `.claude/worktrees/`)
**Contract**: none
**Branch**: task/pi-34-verify-worktree-not-in-tmp
**PR**: https://github.com/FCabiddu/pocket-it/pull/64

## Goal
`bin/verify.sh` crea la worktree di verifica in `/tmp/pocket-it-verify/…` (riga 16). `reviewer.md` ne fa creare altre due in `/tmp/{repo}-{branch}`: una per risolvere i conflitti (riga 39), una per la verifica locale (riga 73). Tutto questo va contro la regola «worktree sotto `.claude/worktrees/`, mai `/tmp`». In una sola giornata sei reviewer non hanno usato `verify.sh` per questo motivo e hanno rifatto i controlli a mano. Da `/tmp` alcuni push sono stati anche negati dai permessi della sessione. Ogni worktree usa e getta creata da uno script o prescritta da un agente deve stare sotto `<repo>/.claude/worktrees/` e va rimossa sempre, anche quando lo script fallisce o viene interrotto.

## Acceptance criteria
- [ ] AC1 — Given un repo con un branch da verificare, when si lancia `bash bin/verify.sh <branch>`, then la worktree viene creata sotto `<repo>/.claude/worktrees/` e durante l'esecuzione non viene creato nessun percorso sotto `/tmp` o `/private/tmp`, verificato confrontando il contenuto di `/tmp` prima e dopo, oppure con un `TMPDIR` di prova.
- [ ] AC2 — Given `verify.sh` che fallisce a metà (checkout impossibile, test rossi, `SIGINT`/`SIGTERM`), when termina, then la worktree che aveva creato non esiste più e `git worktree list` non la elenca.
- [ ] AC3 — Given un nome di branch con `/`, spazi nel percorso del repo o caratteri speciali, when `verify.sh` crea e poi rimuove la worktree, then non c'è nessuna collisione con le worktree degli agenti in `.claude/worktrees/` e nessuna worktree altrui viene toccata.
- [ ] AC4 — Given `reviewer.md`, when si cerca `/tmp` (`grep -n "/tmp" .claude/agents/reviewer.md`), then nessuna istruzione crea una worktree in `/tmp`: le righe 39 e 73 prescrivono `.claude/worktrees/` (o `bin/worktree.sh`) e la rimozione.
- [ ] AC5 — Given la suite esistente di `bin/verify.test.sh`, when gira dopo la modifica, then i controlli attuali restano verdi (lint, type-check, test interessati, riuso di `node_modules`).

## Tests expected
Un test in `bin/verify.test.sh` per ciascuno fra AC1, AC2 e AC3, con una mutazione per ciascuno (percorso rimesso in `/tmp` → rosso, trap tolto → rosso). AC4 si verifica con un grep nel test. Integrazione/E2E: non serve.

## Notes
- La causa è in `bin/verify.sh:16` (`WT="/tmp/pocket-it-verify/…"`), con `trap cleanup EXIT` alla riga 20: il trap va impostato prima di creare la worktree e deve coprire anche i segnali.
- `bin/cleanup-merged.sh:138` riconosce come «scratch» le worktree in `/tmp`: controlla che quelle nuove di `verify.sh` sotto `.claude/worktrees/` non siano scambiate per worktree di agenti da tenere, e che non restino orfane.
- `bin/doctor.sh:145` parla di file di preferenze legacy in `/tmp`: non riguarda questo task, non toccarlo.
- La PR #58 (PI-28), ancora aperta, modifica `reviewer.md` Step 3b: prima di aprire la PR fai merge di `origin/main`, e se nel frattempo #58 è stata mergiata risolvi i conflitti tenendo entrambe le modifiche.
