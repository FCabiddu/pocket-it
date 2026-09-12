# PI-23 — La design compass prescrive interlinee e ritagli che tagliano le lettere

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
**Files**: .claude/agents/shared/design-compass.md
**TAD**: none
**Contract**: none
**Branch**: 
**PR**: 

## Goal
Un progetto costruito seguendo la compass condivisa ha pubblicato una landing in cui i titoli perdono i discendenti delle lettere: la «g», la «p», la «y» tagliate in basso. La causa è stata misurata, e la regola che l'ha prodotta sta nella compass:

- **Interlinea dei titoli display** (riga 48): la compass raccomanda di stringerla a `0.88`–`1.0`, senza avvertire che il valore sicuro dipende dalle metriche del font. Un serif con discendenti profondi ha un'area del glifo più alta di 1,2 em: con 0,92 la riga taglia circa 0,1 em sotto la linea di base, mentre il font ne riserva ai discendenti circa 0,25. I valori che la compass dà vengono da font condensati con discendenti corti, e applicati a un serif tagliano.
- **Tecnica di rivelazione riga per riga** (riga 104): prescrive un contenitore esterno con `overflow: hidden`. Con un'interlinea stretta quel contenitore taglia i discendenti anche dopo la fine dell'animazione.
- **Tecnica a tendina** (riga 109): anima verso `clip-path: inset(0 0% 0 0)`. Con un'animazione mantenuta sullo stato finale, quel ritaglio resta attivo per sempre e taglia tutto ciò che esce dal riquadro.

Né la compass né le spec che ne derivano contengono una regola contro il taglio del testo. Ogni progetto che la segue può ripetere il difetto.

## Acceptance criteria
- [ ] AC1 — Data la raccomandazione sull'interlinea dei titoli display, quando la si legge, allora dice che il valore minimo sicuro dipende dalle metriche del font scelto, come ricavarlo, e che i valori stretti valgono per i font con discendenti corti.
- [ ] AC2 — Data la tecnica riga per riga, quando la si legge, allora dice come fare spazio ai discendenti dentro il contenitore che ritaglia, e che il ritaglio non deve tagliare nulla a animazione finita.
- [ ] AC3 — Data la tecnica a tendina, quando la si legge, allora dice che lo stato finale non deve lasciare un ritaglio attivo sul testo.
- [ ] AC4 — La compass contiene una regola esplicita: nessun glifo tagliato a nessuna larghezza, verificata sulla pagina renderizzata e non dedotta dal CSS.
- [ ] AC5 — Il carattere della compass resta: le tecniche e il gusto editoriale non vengono tolti né annacquati, vengono resi sicuri.

## Tests expected
Nessun test automatico: è un documento di prosa. Rileggi la compass intera e cerca ogni altro punto che prescrive interlinea stretta, `overflow: hidden` o `clip-path` sul testo, con più formulazioni. Integration/E2E: non servono.

## Notes
Il difetto nel progetto viene corretto là, in un task suo. Qui si corregge la fonte, perché non si ripeta altrove.

Questo repo è pubblico: niente dei progetti su cui gira la pipeline. Descrivi il caso in forma generica, come in questo file.
