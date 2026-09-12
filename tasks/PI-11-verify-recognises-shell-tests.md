# PI-11 — `verify.sh` non riconosce i test in shell e avvisa a vuoto su ogni diff

**Status**: Needs Work
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: XS
**Budget**: 60
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/verify.sh
**TAD**: none — segui le convenzioni degli altri script in `bin/`
**Contract**: none
**Branch**: 
**PR**: 

## Goal
`bin/verify.sh` chiude il suo giro dicendo se nel diff ci sono file di test. Alla riga 51 li riconosce con:

```
\.(test|spec)\.[cm]?[jt]sx?$|_test\.(py|go)$
```

JavaScript, TypeScript, Python e Go. Non la shell. In questo repo i test sono `bin/*.test.sh` e `.claude/hooks/*.test.sh`, cioè **tutti** in shell: `verify.sh` stampa quindi `warn no test files in the diff` anche su una PR che aggiunge nove casi di test.

Il danno non è il messaggio sbagliato in sé, è che rende l'avviso inservibile proprio dove servirebbe. Un avviso che compare sempre non distingue più la PR con i test da quella senza, e un reviewer che lo vede ogni volta smette di leggerlo: resta solo il `PASS affected tests`, di cui rischia di fidarsi più di quanto dovrebbe.

## Acceptance criteria
- [ ] AC1 — Dato un diff che contiene un file `*.test.sh`, quando eseguo `verify.sh`, allora dice che nel diff ci sono file di test e ne riporta il numero giusto.
- [ ] AC2 — Dato un diff che contiene solo file `*.sh` che non sono test, quando eseguo `verify.sh`, allora l'avviso di assenza di test compare come oggi.
- [ ] AC3 — Dato un diff con file di test negli altri linguaggi già riconosciuti, quando eseguo `verify.sh`, allora il comportamento non cambia: il conteggio resta quello di prima.

## Tests expected
Se esiste già un test per `verify.sh`, un caso per criterio lì. Se non esiste, dichiaralo nel report e verifica AC1-AC3 a mano su tre diff costruiti apposta, riportando l'output di ciascuno: non dichiarare il criterio soddisfatto senza aver mostrato l'output. Integration/E2E: non servono.

## Notes
Il difetto è tutto nella riga 51 di `bin/verify.sh`, e nella `grep -cE` che conta le occorrenze subito dopo: le due espressioni vanno tenute allineate, altrimenti il conteggio non corrisponde alla condizione che l'ha attivato.

Attenzione a non allargare troppo: `*.sh` non è un test, lo è `*.test.sh`. Un pattern generoso rimetterebbe l'avviso nella stessa inutilità di adesso, dal lato opposto.
