# PI-22 — `cleanup-merged.sh` cancella il worktree di un agente che sta ancora lavorando

**Status**: Needs Work
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: high
**Depends on**: none
**Wave**: 1
**Files**: bin/cleanup-merged.sh, bin/cleanup-merged.test.sh, .claude/agents/shared/implementing-common.md
**TAD**: none — segui le convenzioni degli altri script in `bin/`
**Contract**: none
**Branch**: task/pi-22-cleanup-keeps-running-worktrees
**PR**: https://github.com/FCabiddu/pocket-it/pull/46

## Goal
`bin/cleanup-merged.sh` rimuove il worktree e il branch locale delle PR già mergiate. Le pipeline lo lanciano **dopo ogni merge**, anche mentre altri agenti stanno lavorando in parallelo nei loro worktree.

Per stabilire se un branch è mergiato, `merged_into()` usa `git merge-base --is-ancestor <sha del branch> <base>`. Un branch appena creato, sul quale l'agente non ha ancora fatto nessun commit, punta allo stesso commit della base: è quindi, banalmente, antenato della base. Lo script lo classifica come mergiato, cancella il worktree e cancella il branch.

È successo davvero, con conseguenze gravi, e la catena è istruttiva:

1. Un developer era stato lanciato su un task di sicurezza e stava ancora leggendo e analizzando: nessun commit, nessun file modificato, quindi il worktree risultava pulito e non protetto dalla regola che conserva i worktree sporchi.
2. Dopo il merge di un'altra PR è partito lo script di pulizia, che ha rimosso quel worktree e il suo branch.
3. La directory corrente dell'agente è ricaduta sul checkout principale del repository, e l'agente ha continuato a modificare il file su cui lavorava **lì**.
4. Quel file era l'hook di sicurezza attivo per ogni sessione. Una versione non revisionata di una guardia sui push è rimasta in uso ovunque finché non è stata notata e ripristinata.

Due difetti, in due posti diversi, e vanno chiusi entrambi.

**A. Lo script scambia «nessun commit ancora» per «mergiato».** Un branch senza commit propri non ha nulla di mergiato: è lavoro che non è ancora cominciato, o che è in corso senza essere stato committato. Non va toccato.

**B. L'agente, perso il worktree, ha ripiegato in silenzio sul checkout principale.** Qualunque sia la causa per cui il percorso del worktree non esiste più, un agente che lavora fuori dal proprio worktree modifica l'albero condiviso di tutte le altre sessioni. Deve fermarsi e riferire, non proseguire altrove.

## Acceptance criteria
- [x] AC1 — Dato un worktree il cui branch non ha nessun commit oltre la base, quando lo script gira, allora il worktree e il branch restano, e lo script dice perché li ha conservati.
- [x] AC2 — Dato un worktree il cui branch ha commit propri ed è stato mergiato per antenato nella base, quando lo script gira, allora viene rimosso come oggi.
- [x] AC3 — Dato un worktree il cui branch corrisponde a una PR mergiata con squash, quando lo script gira, allora viene rimosso come oggi.
- [x] AC4 — Dato un worktree con modifiche non committate, quando lo script gira, allora resta come oggi.
- [x] AC5 — Date le regole condivise lette all'avvio da ogni agente che implementa, quando il percorso del proprio worktree non esiste più, allora prescrivono di fermarsi e riferire, e vietano esplicitamente di proseguire nel checkout principale o in qualunque altra directory.

## Tests expected
Un caso per AC1-AC4 in `bin/cleanup-merged.test.sh`, nello stile dei casi esistenti. Prova per mutazione AC1: togliendo la condizione sui commit propri, il suo caso deve diventare rosso. AC5 è prosa, si verifica leggendo il diff. Integration/E2E: non servono.

## Notes
Il difetto A sta in `merged_into()`, righe 46-50 di `bin/cleanup-merged.sh`, e in `decide()` che la chiama. Attenzione a non rompere AC3: le PR mergiate con squash non lasciano ascendenza, e lo script le riconosce interrogando `gh`. Un branch senza commit propri non ha nemmeno una PR, quindi quel ramo non lo tocca, ma verificalo.

Il caso «branch senza commit propri» va distinto con il criterio giusto: il branch non contiene commit che la base non abbia. Non basta confrontare il nome o l'età del worktree.

Per AC5 il posto è `.claude/agents/shared/implementing-common.md`, perché è quello che developer e qa-engineer leggono all'avvio. Una regola scritta solo nello script non arriva all'agente.

Rischio alto perché lo script cancella lavoro: una condizione sbagliata nell'altro verso lascerebbe accumulare worktree, una sbagliata in questo verso distrugge lavoro in corso.

Questo repo è pubblico: niente dei progetti su cui gira la pipeline.
