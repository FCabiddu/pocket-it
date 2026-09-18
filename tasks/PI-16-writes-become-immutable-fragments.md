# PI-16 — Le scritture diventano frammenti immutabili; congelamento del vecchio file; `retract`

**Status**: Needs Work
**Label**: DevOps
**Epic**: handoff
**Story**: handoff
**Priority**: Must
**Estimate**: M
**Budget**: 200
**Risk**: high
**Depends on**: PI-15
**Wave**: 3
**Files**: bin/handoff.sh, bin/handoff.test.sh, .claude/agents/shared/implementing-common.md:104,118, .claude/agents/developer.md:112, .claude/agents/retro.md:3,34,48,58, .claude/skills/quickfix/SKILL.md:79, .claude/skills/run-wave/SKILL.md:48, CLAUDE.md:78,79,160,161,164, README.md:46,74
**TAD**: tech-analysis/HANDOFF_MEMORY_TECH_ANALYSIS.md (§2.4 ADR-3, ADR-4, ADR-5, §4.2, §4.3, §4.4, §5.2, §6, §9.2, §11.2, §12 PI-16, §13 R-01, R-02, R-03, R-07)
**Contract**: none
**Branch**: task/pi-16-writes-immutable-fragments
**PR**: https://github.com/FCabiddu/pocket-it/pull/93

## Goal
Da questo task `log`, `fact` e `retract` smettono di scrivere `docs/SESSION_HANDOFF.md` e `docs/SESSION_HANDOFF_ARCHIVE.md` e creano invece un frammento immutabile sotto `docs/handoff/{AAAA-MM}/{AAAAMMGGTHHMMSSZ}-{slug}-{rand4}.md` (§4.1, §4.2 e ADR-5 del TAD), con creazione esclusiva (`set -o noclobber`) così un file non viene mai scritto due volte. Il vecchio file si **congela**: da qui in poi nessuno scrive più sopra, resta sola sorgente letta dal compositore per sempre (ADR-3). `retract` è un comando nuovo: crea un frammento `## Ritirati` con l'hash del testo del fatto da nascondere, senza toccare alcun file esistente (ADR-4). Il comando `where` stampa la cartella relativa in cui scriverebbe, non richiede un repo, non scrive niente, ed è il segnale verificabile che questo task è installato (§5.2, §9.2 «Regola ponte»). È il task a rischio alto della sequenza: è la modifica che ogni agente di ogni progetto userà alla prossima scrittura di memoria, e contiene la prova di non-contesa a quattro rami.

## Acceptance criteria
- [ ] AC1 (non-contesa) — Given lo scenario a quattro rami del §11.2 del TAD con `GIT_ATTR_NOSYSTEM=1` (`task/a` e `task/b` scrivono `log`+`fact`+`retract`; `chore/1` e `chore/2` scrivono ciascuno una riga sul ramo base; `task/a` viene fuso con `--squash` e poi scrive ancora), when si fondono tutti, then 0 conflitti e il multinsieme di `recent --all` è uguale alle righe scritte. La mutazione con un file per ramo produce il conflitto.
- [ ] AC2 (nessuna scrittura due volte) — Given 50 invocazioni `log` nello stesso secondo sullo stesso ramo, when si contano i file, then ci sono 50 file distinti, ciascuno con una voce, e nessun file esistente ha cambiato mtime o contenuto.
- [ ] AC3 (congelamento) — Given un repo con il vecchio file, when `log`, `fact` e `retract`, then `git diff -- docs/SESSION_HANDOFF.md docs/SESSION_HANDOFF_ARCHIVE.md` è vuoto. Given un repo senza vecchio file, then il vecchio file non viene creato.
- [ ] AC4 (ritiro senza toccare altri) — Given un fatto presente in un frammento creato su un altro ramo e in una sorgente congelata, when `retract "testo"`, then `facts` non lo mostra più e quei file sono invariati byte per byte (hash prima e dopo).
- [ ] AC5 (tetto) — Given 100 fatti visibili, when `fact "nuovo"`, then esce con 3 e il messaggio contiene `retract`. When si esegue `retract` di un fatto e poi `fact "nuovo"`, then esce con 0 e i visibili sono 100.
- [ ] AC6 (memoria reale) — Given la copia della memoria di questo repo, when una `log` e una `fact`, then l'insieme di `facts` contiene l'insieme dell'`awk` di oggi più il nuovo fatto, e il multinsieme di `recent --all` contiene log più archivio di oggi più la nuova riga.
- [ ] AC7 (segnale che non scrive) — Given lo script installato, when `handoff.sh where` in una cartella che non è un repo git, then stampa `docs/handoff/{AAAA-MM}/`, esce con 0 e la cartella resta vuota (`find "$D" -mindepth 1` vuoto). When `where` nella radice di un repo, con e senza il vecchio file, then stesso output e `git status --porcelain` identico prima e dopo. Mutazione: lo script vecchio nella cartella non-repo esce con 1 e la cartella resta vuota; nella radice di un repo senza `docs/` lo script vecchio lascia `?? docs/`, e il test lo rileva come rosso.
- [ ] AC8 (testi) — Given il repo dopo il task, when `git grep -n "SESSION_HANDOFF" -- ':!docs' ':!tech-analysis' ':!tasks'`, then ogni riga restituita descrive la sorgente congelata o sta in `bin/handoff.sh` o nel suo test. Nessuna riga dice «prepends», «kept to 40», «creates docs/SESSION_HANDOFF.md» o «remove one line by hand», e la Facts hygiene di `retro.md` pota con `retract`.

## Tests expected
Un caso per criterio in `bin/handoff.test.sh`; i test di rotazione di PI-8 diventano test di **non-rotazione** (il vecchio comportamento di spostamento in archivio a 40 righe non si applica più al log composto, solo alla finestra di visualizzazione — §4.4 del TAD). AC1 va nel livello integrazione, repo git temporaneo con più rami (§11.2 del TAD): è la prova di non-contesa, criterio di comportamento di `git merge`, non di una funzione. Ogni criterio va provato per mutazione e i conteggi prima/dopo vanno nel corpo della PR (§11.3 del TAD). Integration/E2E oltre ad AC1: non servono.

## Notes

- Dalla review di PI-14 (non bloccante): `handoff.sh __spec X` esce con 0, e il `case` bash è una seconda lista di sottocomandi che l'assert di sincronia `SPEC`/`HANDLERS` non controlla. I sottocomandi di scrittura aggiunti qui vanno dichiarati in `SPEC`, e l'elenco deve restare unico.
- **Perché high:** questa PR non si approva senza mutazioni e conteggi nel corpo, e va assegnata a un modello capace di seguire l'intero scenario a quattro rami senza scorciatoie (raccomandazione del TAD: opus).
- Restano **invariate**, chiamate di sola scrittura fuori da questo task: `reviewer.md:95-96`, `qa-engineer.md:94`, `deps/SKILL.md:17`, `implementing-common.md:101,132,133`.
- I lettori fuori dal repo (istruzioni globali della sessione principale, prompt di lancio con la regola ponte) li aggiorna l'orchestratore dopo l'installazione, quando `handoff.sh where` esce con 0. Non sono un AC di questo task (nota esplicita nel §12 del TAD).
- Lo slug del nome file è il nome del ramo sanificato (`[^a-z0-9]` → `-`, max 40 caratteri) o `detached-{sha7}`; `rand4` sono 4 caratteri `[a-z0-9]` da `/dev/urandom`. Nessuno dei due garantisce da solo l'unicità: la garantisce la creazione esclusiva (§2.4 ADR-5, §6 del TAD).
- Il tetto dei fatti (100) resta un tetto di **scrittura**, contato sui fatti visibili dopo deduplicazione e ritiri (§4.4 del TAD); due scritture parallele possono superarlo di poco ed è accettato (R-05, non bloccante).
- `handoff.sh` scrive solo sotto `docs/handoff/`, sempre con creazione esclusiva; lo slug sanificato impedisce a un nome di ramo ostile di scrivere fuori dalla cartella (§6 del TAD).
