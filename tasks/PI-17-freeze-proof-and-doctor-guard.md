# PI-17 — Prova del congelamento e guardia in `doctor.sh`

**Status**: Todo
**Label**: DevOps
**Epic**: handoff
**Story**: handoff
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: PI-16
**Wave**: 4
**Files**: bin/doctor.sh, bin/doctor.test.sh, bin/handoff.test.sh
**TAD**: tech-analysis/HANDOFF_MEMORY_TECH_ANALYSIS.md (§2.3, §4.4, §9.2, §9.5, §12 PI-17, §13 R-03)
**Contract**: none
**Branch**: 
**PR**: 

## Goal
Due cose. Primo, la prova che un ramo aperto prima di PI-16 (che scrive ancora nel vecchio file con lo script vecchio) si fonde su `main` senza conflitti dopo il congelamento, e che le sue righe restano visibili tramite il compositore. Secondo, una guardia in `doctor.sh` che segnala ogni riga tolta da una sorgente congelata e ogni frammento alterato dopo essere stato scritto (modificato, cambiato di tipo, cancellato senza una sezione d'archivio equivalente), usando `git log -m --first-parent --no-renames --name-status --diff-filter=MTD -- docs/handoff` così che ogni spostamento — compattazione compresa — arrivi nella forma unica `D` (+ eventuale `A`), mai come `R`.

## Acceptance criteria
- [ ] AC1 — Given un ramo creato prima del cambio che aggiunge righe (log con rotazione e fatto) al vecchio file con lo script vecchio, e `main` che dopo il cambio ha frammenti nuovi, when si fonde il ramo su `main`, then 0 conflitti, e `facts` e `recent --all` mostrano le righe del ramo.
- [ ] AC2 — Given il punto di congelamento, cioè il primo commit che aggiunge un file sotto `docs/handoff/` (`git log --diff-filter=A --reverse --format=%H -- docs/handoff | head -1`), e un `HEAD` in cui il multinsieme delle righe `- ` di `SESSION_HANDOFF.md` ∪ `SESSION_HANDOFF_ARCHIVE.md` non contiene più quello del punto di congelamento, when `doctor.sh`, then esce con errore e nomina la riga mancante. Given uno spostamento dal log all'archivio, fatto dalla rotazione di un ramo pre-cambio, then nessun errore.
- [ ] AC3 (ogni modo di alterare un frammento già scritto) — la guardia legge `git log -m --first-parent --no-renames --name-status --diff-filter=MTD -- docs/handoff`. `-m --first-parent` serve perché una cancellazione fatta dentro un merge sfugge al `log` di default (misurato nel TAD). `--no-renames` serve perché ogni spostamento, anche verso l'archivio, deve arrivare nella forma unica `D` + `A`: senza l'opzione, un `compact` di un frammento esce `R085` e una rinomina vera `R100`, il `compact` di due frammenti esce `D D A`; con l'opzione tutti e tre i casi escono come `D` + `A`, qualunque `diff.renames` configurato. Quindi `R` non deve mai comparire; l'unica eccezione vale per la sola `D`.
  - Given un commit che, sotto `docs/handoff/{AAAA-MM}/`, **modifica** (`M`) un frammento, when `doctor.sh`, then errore con il percorso.
  - Given un commit che **cambia tipo** (`T`) a un frammento (per esempio lo sostituisce con un symlink), then errore con il percorso.
  - Given un commit, anche di merge o di squash, che **cancella** (`D`) un frammento, then errore con il percorso, **tranne** quando il suo `{basename}` compare in HEAD come sezione `### {basename}` di un file `docs/handoff/archive/*.md` con lo stesso multinsieme di righe `- `.
  - Given un **`compact` di un solo frammento** (senza `--no-renames` git lo riporterebbe come `R` con una percentuale qualsiasi), then nessun errore.
  - Given un **`compact` di più frammenti** in un archivio, then nessun errore.
  - Given una **rinomina vera fuori dall'archivio** (`git mv {AAAA-MM}/r.md {AAAA-MM}/r2.md`, oggi `R100`), then errore sul percorso d'origine — è una `D` senza sezione: il rename rompe l'identità per nome del §4.3 del TAD.
  - Given uno **spostamento dentro `archive/` senza sezione** (`git mv {AAAA-MM}/a.md archive/a.md`), then errore: il file spostato non ha una sezione `### a.md`.
  - Given solo aggiunte, merge con squash e un frammento ricomparso accanto alla propria sezione d'archivio, then nessun errore.
  - Mutazione: senza `--no-renames` il `compact` di un frammento dà un errore falso (`R`) oppure, se `R` viene ignorata, la rinomina vera passa; un `git rm` di un frammento senza sezione dà errore; con `--diff-filter=M` al posto di `MTD`, o senza `-m --first-parent` sul caso del merge, l'errore sparisce.

## Tests expected
AC1 e la prima parte di AC2 in `bin/handoff.test.sh` o `bin/doctor.test.sh` (repo git temporaneo, più rami — integrazione, §11.1 del TAD: il criterio è un comportamento di `git merge`, non di una funzione). AC2 e AC3 in `bin/doctor.test.sh`, un caso per ciascuno dei nove sotto-casi elencati in AC3, ciascuno provato per mutazione come descritto (righe finali dell'AC). Integration/E2E: non servono oltre ai test già in `bin/*.test.sh`.

## Notes
- Il `compact` citato in AC3 è il comando che arriva con PI-18: questo task scrive la guardia che lo riconoscerà correttamente **prima** che `compact` esista, usando frammenti e sezioni d'archivio costruiti a mano nel test. Non implementare `compact` qui.
- `doctor.sh` oggi è il pre-flight a costo zero token dell'orchestratore: la nuova guardia deve restare nello stesso stile (errori bloccanti stampati con `ERROR`, warning con `warn`, exit 1 se ci sono errori) — guarda le sezioni esistenti dello script per lo stile dei messaggi.
- R-03 del TAD («una sorgente congelata viene riscritta») è il rischio che questo task chiude: la guardia più «il retro pota solo con `retract`» sono l'unica mitigazione dichiarata.
