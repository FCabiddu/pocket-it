# PI-10 — L'hook vieta all'orchestratore un push che le sue stesse istruzioni gli prescrivono

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: .claude/hooks/guard.sh, .claude/hooks/guard.test.sh, .claude/skills/run-wave/SKILL.md, .claude/skills/quickfix/SKILL.md, .claude/skills/deps/SKILL.md
**TAD**: none — segui la forma già usata per `gh pr merge` nello stesso hook
**Contract**: none
**Branch**: 
**PR**: 

## Goal
`.claude/hooks/guard.sh` blocca ogni `git push` verso `main` o `master`, senza eccezioni. Gli skill della pipeline prescrivono però all'orchestratore di fare esattamente quello a fine lavoro: aggiornare board, indice e memoria sul ramo base e pushare. Le due regole si annullano, e l'orchestratore resta senza una strada praticabile.

Il divieto è giusto per gli agenti: un developer o un reviewer non devono toccare `main`, mai. Non è giusto per l'orchestratore, che è la sessione principale e ha già il mandato di mergiare le PR approvate.

Lo stesso hook ha già risolto un caso identico. `gh pr merge` è vietato a tutti salvo quando il comando porta il prefisso `POCKET_IT_USER_MERGE=1`, che non è un permesso tecnico ma una traccia di audit: dice che quel merge è coperto dal mandato dell'orchestratore. Qui serve la stessa forma per il push sul ramo base.

Effetto collaterale da chiudere nello stesso giro: finché l'orchestratore non può pushare sul ramo base, un file di task appena scritto non arriva su origin, e `bin/worktree.sh` crea i worktree da `origin/main`. L'agente lanciato su quel task non trova il suo file e si ferma. È successo davvero.

## Acceptance criteria
- [ ] AC1 — Dato un `git push` verso il ramo base senza prefisso autorizzato, quando l'hook lo valuta, allora lo blocca come oggi, con lo stesso messaggio per gli agenti.
- [ ] AC2 — Dato lo stesso push con il prefisso di audit, quando l'hook lo valuta, allora lo lascia passare.
- [ ] AC3 — Dato un push con il prefisso verso un ramo che non è quello base, quando l'hook lo valuta, allora passa come è sempre passato: il prefisso non cambia nulla fuori dal suo caso.
- [ ] AC4 — Dato un force-push verso il ramo base **con** il prefisso, quando l'hook lo valuta, allora lo blocca lo stesso: riscrivere la storia del ramo base resta vietato a chiunque.
- [ ] AC5 — Dati gli skill che prescrivono l'aggiornamento del ramo base, quando li si legge, allora indicano la forma autorizzata invece di un `git push` nudo che l'hook rifiuterebbe.

## Tests expected
Un caso per AC1-AC4 in `.claude/hooks/guard.test.sh`, nello stile dei casi già presenti per `POCKET_IT_USER_MERGE=1`. Prova per mutazione AC4: togliendo la guardia sul force-push, il suo caso deve diventare rosso. AC5 non è testabile a macchina, si verifica leggendo il diff. Integration/E2E: non servono.

## Notes
La forma da imitare è alle righe 22-28 di `.claude/hooks/guard.sh`, il blocco che gestisce `POCKET_IT_USER_MERGE=1`. Le regole sul push stanno subito sotto, righe 29-31 più il verdetto Python che copre il push implicito dal ramo corrente (righe 36-113): il prefisso deve valere per **tutte** quelle strade, non solo per la forma esplicita `git push origin main`, altrimenti un `git push` nudo da `main` resta bloccato e il problema non è risolto.

Il nome del prefisso è una scelta tua: tienilo coerente con quello dei merge e spiegalo nel commento in testa all'hook, perché è lì che un agente va a leggere cosa gli è concesso.

Il divieto per gli agenti non si tocca: nessun agente conosce il prefisso e nessuno deve impararlo da questo diff.
