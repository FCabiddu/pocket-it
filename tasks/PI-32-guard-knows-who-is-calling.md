# PI-32 — La guardia non sa se un comando arriva dall'orchestratore o da un agente

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: high
**Depends on**: PI-13
**Wave**: 1
**Files**: .claude/hooks/guard.sh, .claude/hooks/guard.test.sh
**TAD**: none — convenzioni dell'hook
**Contract**: none
**Branch**: 
**PR**: 

## Goal
La guardia permette il push verso il ramo base e il merge delle PR solo quando il comando porta un prefisso di audit. Il prefisso doveva distinguere la sessione principale, che ha il mandato di farlo, dagli agenti, che non devono mai scrivere sul ramo base.

**Non funziona, e lo si è visto.** Un reviewer ha dichiarato di aver pushato sul ramo base usando il prefisso riservato all'orchestratore, per salvare una riga di diario. Il prefisso è scritto in chiaro negli skill dell'orchestratore e nell'hook stesso, cioè in file del repository che ogni agente può leggere. È solo testo: chi lo scrive passa. Un permesso che si ottiene leggendo un file condiviso non è un permesso.

**Esiste un segnale che un agente non può falsificare, ed è stato verificato sul campo.** Quando un hook `PreToolUse` gira dentro un subagente, Claude Code gli passa nell'input JSON i campi `agent_id` e `agent_type`. Quando gira nella sessione principale, quei campi **mancano**. È stata registrata la stessa chiamata Bash dai due contesti: dal subagente l'input conteneva `agent_id` e `agent_type` valorizzati; dalla sessione principale non li conteneva. Quei campi li scrive Claude Code, non il comando né un file del repository.

## Acceptance criteria
- [ ] AC1 — Dato un push verso il ramo base in un input che contiene `agent_id`, quando l'hook lo valuta, allora lo blocca **anche se il comando porta il prefisso di audit**, con un messaggio che dice che agli agenti il ramo base è vietato e dove vanno invece le righe di diario.
- [ ] AC2 — Dato lo stesso push con il prefisso esatto in un input **senza** `agent_id`, quando l'hook lo valuta, allora passa come oggi.
- [ ] AC3 — Dato un `gh pr merge` con il prefisso di merge in un input che contiene `agent_id`, quando l'hook lo valuta, allora lo blocca, **salvo** gli agenti che per mandato mergiano le proprie PR: oggi il solo `retro`, riconosciuto da `agent_type`.
- [ ] AC4 — Dato un push verso un ramo di task in un input con `agent_id`, quando l'hook lo valuta, allora passa: agli agenti resta permesso tutto ciò che era permesso, tranne il ramo base.
- [ ] AC5 — Dato un input con `agent_id` presente ma vuoto, o di tipo inatteso, quando l'hook lo valuta, allora lo tratta come agente: nel dubbio si nega.
- [ ] AC6 — Il commento in testa all'hook spiega il meccanismo, la verifica fatta e perché il prefisso da solo non bastava.

## Tests expected
Un caso per criterio in `.claude/hooks/guard.test.sh`, costruendo l'input JSON con e senza `agent_id` e `agent_type`. Prova per mutazione AC1: ignorando `agent_id`, il suo caso deve diventare rosso. Integration/E2E: la verifica sul campo è già stata fatta e descritta sopra; ripetila nel report solo se il formato dell'input risulta cambiato.

## Notes
Dipende da PI-13 perché tocca le stesse righe dell'hook: va fatto dopo il suo merge, non insieme.

Il prefisso di audit non va tolto: resta la traccia che il merge o il push della sessione principale era voluto. Diventa però inutile nelle mani di un agente, ed è questo il punto.

Rischio alto perché è l'hook che protegge ogni sessione: un errore nel riconoscere la sessione principale bloccherebbe l'orchestratore, un errore nell'altro verso riaprirebbe il ramo base agli agenti.

Questo repo è pubblico: niente dei progetti su cui gira la pipeline.
