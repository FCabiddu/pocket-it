# PI-13 — Qualunque assegnazione davanti a `git` disinnesca le guardie sul push

**Status**: Done
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: PI-10
**Wave**: 1
**Files**: .claude/hooks/guard.sh, .claude/hooks/guard.test.sh
**TAD**: none — segui le convenzioni dell'hook
**Contract**: none
**Branch**: task/pi-13-guard-fail-open
**PR**: 

## Goal
Il blocco Python che classifica i push dentro `.claude/hooks/guard.sh` ancora le proprie espressioni all'inizio del comando, con `^git`. Basta quindi **qualsiasi** assegnazione di variabile davanti a `git` perché quell'ancora non corrisponda più e il comando non venga classificato affatto: la guardia non nega, semplicemente non vede. Un push verso il ramo base passa.

Le forme che lo producono non sono esotiche, sono normale uso quotidiano di git e della shell:

- una variabile d'ambiente qualsiasi premessa al comando;
- `git -c chiave=valore push`, cioè la forma standard per una configurazione una tantum;
- e, dopo PI-10, anche il prefisso di audit **con valore diverso da quello autorizzato**: una forma che dichiara di non essere autorizzata disinnesca il controllo invece di essere respinta.

L'ultima è la più insidiosa, perché PI-10 insegna alla pipeline proprio la grafia «assegnazione davanti a `git`». Una scrittura che prima nessuno aveva motivo di usare diventa d'uso corrente, e con essa la strada che apre.

Il difetto è di categoria: una guardia che **fallisce lasciando passare**. Il comportamento voluto è l'opposto — davanti a una forma che non riconosce, deve negare e dirlo, non tacere.

## Acceptance criteria
- [x] AC1 — Dato un push verso il ramo base preceduto da un'assegnazione di variabile qualsiasi, quando l'hook lo valuta, allora lo blocca.
- [x] AC2 — Dato un push verso il ramo base nella forma `git -c chiave=valore push`, quando l'hook lo valuta, allora lo blocca.
- [x] AC3 — Dato lo stesso push con il prefisso di audit ma con un valore diverso da quello autorizzato, quando l'hook lo valuta, allora lo blocca: solo il valore esatto autorizza.
- [x] AC4 — Dato il push con il prefisso di audit nella sua forma autorizzata, quando l'hook lo valuta, allora passa: questo task non deve richiudere ciò che PI-10 ha aperto.
- [x] AC5 — Dato un push verso un ramo che non è quello base, in tutte le forme di AC1-AC3, quando l'hook lo valuta, allora passa come è sempre passato.

## Tests expected
Un caso per criterio in `.claude/hooks/guard.test.sh`. Prova per mutazione AC1 e AC3: rimettendo l'ancora al solo inizio del comando, i loro casi devono diventare rossi. Integration/E2E: non servono.

## Notes
Il difetto sta nel blocco Python delle righe 36-113 di `.claude/hooks/guard.sh`, nell'espressione che riconosce il comando a partire dall'inizio della stringa. Le altre guardie dell'hook, quelle basate su `grep`, non hanno questa ancora e vanno lasciate stare: il task riguarda solo la classificazione dei push.

Non allargare la soluzione a «riconosci ogni possibile prefisso»: è una rincorsa che si perde. La direzione giusta è che una forma non riconosciuta venga **negata**, non ignorata — e che il valore del prefisso di audit sia confrontato per uguaglianza esatta, non per presenza.

Dipende da PI-10 perché tocca le stesse righe: va fatto dopo, non insieme.

## Ampliamento dopo la review di PI-10

La review del terzo giro di PI-10 ha misurato due altre forme che passano verso il ramo base, **sia prima sia dopo** quella PR, con e senza prefisso: un refspec con glob che mappa tutti i rami su tutti i rami, e `--all` con force. Sono fail-open preesistenti e non regressioni, e stanno nello stesso secchio di questo task: la guardia non le nega, non le vede.

Hanno in comune con le altre una cosa che è il vero criterio: **raggiungono il ramo base senza nominarlo**. Una guardia che cerca il nome del ramo non le troverà mai.

- [x] AC6 — Dato un push verso il ramo base espresso con un refspec glob che non nomina il ramo, quando l'hook lo valuta, allora lo blocca.
- [x] AC7 — Dato `--all` combinato con una forma di force, quando l'hook lo valuta, allora lo blocca.
- [x] AC8 — Dati i push legittimi verso rami di task nelle stesse grafie, quando l'hook li valuta, allora passano: la stretta non deve prendere in mezzo la pulizia ordinaria.
