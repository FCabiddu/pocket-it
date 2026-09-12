# PI-26 — Il modello di un agente è deciso da una mappatura sul campo Risk

**Status**: Done
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/next-wave.sh, bin/next-wave.test.sh, .claude/skills/run-wave/SKILL.md, .claude/skills/quickfix/SKILL.md, CLAUDE.md
**TAD**: none
**Contract**: none
**Branch**: task/pi-26-model-choice
**PR**: 

## Goal
Oggi il modello con cui gira un developer lo decide `bin/next-wave.sh` con una regola sola: `opus` se il task ha `Risk: high`, altrimenti `sonnet`. Gli skill dicono di passare quel valore così com'è.

Il campo `Risk` è un indicatore troppo grezzo. In un caso reale un task di sicurezza su una guardia dei push era marcato `Risk: low`, ha richiesto tre giri di review sulle stesse righe, e la scelta giusta del modello è venuta dal giudizio dell'orchestratore, non dal campo. Al contrario, un testo di sola prosa gira sul modello più grande se chi ha scritto il task l'ha marcato ad alto rischio per un altro motivo.

Il modello va deciso dall'orchestratore, a ogni lancio, secondo la natura del lavoro. Restano però due vincoli che il task non deve rompere:

- **Il `model` nel frontmatter di ogni agente resta, come pavimento.** Non è configurato un modello di default per i subagenti, quindi un agente lanciato senza modello eredita quello della sessione principale, il più costoso: togliere il frontmatter farebbe costare di più ogni lancio in cui il parametro viene dimenticato.
- **Il modello non si cambia per reazione a un giro fallito.** Un modello più grande non corregge una causa: si cerca perché il giro è fallito, e si cambia modello solo se l'analisi indica il modello come causa.

## Acceptance criteria
- [x] AC1 — Dato l'output di `next-wave.sh`, quando lo si legge, allora il valore del modello è presentato come suggerimento e non come decisione, con un nome di campo che lo dica, e la suite dello script è aggiornata di conseguenza. → campo rinominato `model_hint`; test in `bin/next-wave.test.sh` ("PI-26 AC1 field is named model_hint, not model", "PI-26 AC1 high-risk task gets an opus hint", "PI-26 AC1 low-risk task gets a sonnet hint").
- [x] AC2 — Dati `run-wave` e `quickfix`, quando prescrivono un lancio, allora dicono che l'orchestratore sceglie il modello esplicitamente e lo motiva in una riga del prompt, secondo criteri scritti. → entrambi gli skill, sezione "Model choice".
- [x] AC3 — I criteri sono scritti e sono gli stessi nei due skill e in `CLAUDE.md`: modello più grande per lavoro irreversibile o distruttivo, confini di sicurezza o permessi, ragionamento aperto (diagnosi, design, analisi di causa e le loro review), superficie ampia da tenere coerente; modello più piccolo per lavoro meccanico, ben specificato o di sola prosa. → stesso paragrafo in `run-wave/SKILL.md`, `quickfix/SKILL.md` e nella riga "Model choice" della tabella Conventions di `CLAUDE.md`.
- [x] AC4 — Gli stessi testi dicono che il `model` nel frontmatter resta come pavimento, e perché. → stesso paragrafo, frase sul pavimento e sull'ereditarietà del modello di sessione.
- [x] AC5 — Gli stessi testi dicono che il modello non si cambia per reazione a un giro fallito. → stesso paragrafo, ultima frase; già coerente con la frase preesistente in run-wave Step 3.

## Tests expected
AC1 in `bin/next-wave.test.sh`. AC2-AC5 sono prosa: si verificano rileggendo i tre file per intero e cercando le frasi che fanno ancora dipendere il modello dal solo `Risk`. Integration/E2E: non servono.

## Notes
Chi legge l'output di `next-wave.sh` oggi, compresi altri script o skill, va trovato e aggiornato: cerca nel repo il nome del campo prima di rinominarlo.

Questo repo è pubblico: niente dei progetti su cui gira la pipeline, né di entry point privati.
