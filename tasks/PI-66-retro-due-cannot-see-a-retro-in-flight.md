# PI-66 — `retro-due.sh` cannot tell "nobody has worked this signal" from "a retro is working it right now"

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/retro-due.sh, bin/retro-due.test.sh
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**:
**PR**:

## Goal
`retro-due.sh` answers a question about the past — are there signals whose retro has not landed — and
returns exit 10 until the retro's mark PR merges. It has no way to say that a retro **is running on those
very signals right now**, because nothing on disk records that.

The damage: **the tool tells the caller to start work that is already in progress.** Measured on
2026-09-18: a retro was launched on a signal, and thirty seconds later a stop hook ran `retro-due.sh`, got
exit 10, and instructed the session to launch a retro on the same signal. The guard that exists for this in
the `/quickfix` skill — look for an open `retro/` PR before launching a second one — cannot help in that
window, because the running retro has not opened its PR yet. Between launch and first push, a retro is
invisible, and the only thing preventing a duplicate is that a human or a model happens to remember.

A duplicate retro is not a harmless retry: two agents write rules into the same start-read files from two
branches, and the second one reasons about signals the first has already answered.

## Acceptance criteria
- [ ] AC1 — Given a retro that has been launched and has not yet opened a PR, when `retro-due.sh` runs,
      then its output distinguishes that state from "nobody has worked these signals". Whether the marker
      is a file, a branch pushed at start, or something else is your call; what is not negotiable is that
      the distinction exists **on disk**, readable by a hook that knows nothing about running agents.
- [ ] AC2 — Given the exit codes callers already branch on (0 nothing, 2 error, 10 due), when you add the
      new state, then every existing caller keeps behaving correctly — the skills, the hooks and
      `bin/doctor.sh`. Find them by searching the repository, not from memory, and list each one in the
      report with what it does under the new state. A new exit code that an old caller reads as "due" has
      changed nothing.
- [ ] AC3 — Given a marker left behind by a retro that died, crashed or was killed, when `retro-due.sh`
      runs later, then the signal becomes due again rather than staying suppressed for ever. State the
      rule you chose (age, liveness, something else) and **execute** the case: kill a marked run and show
      the signal coming back.
- [ ] AC4 — Given `bash bin/retro-due.test.sh`, when it runs, then it is green, covers the three states
      (nothing · due · in flight) and the stale-marker case of AC3, and the `ok` count is not lower than
      before.

## Tests expected
AC3 and AC4 are the evidence, both executed. Integration/E2E: not needed.

## Notes
Found by the orchestrator on 2026-09-18, from a stop hook that asked for a second retro on a signal whose
retro had been running for thirty seconds. The hook is not the defect: it asked the only question the tool
can answer.

Related to PI-65 (nothing relates open branches to the board): same family — work in progress that leaves
no trace anything can read. Do not merge the two; this one is about a single script's contract.

## Occorrenze misurate

Due volte nella stessa sessione, 2026-09-18, lo stop hook ha chiesto di lanciare un retro mentre
un retro era vivo e non aveva ancora pushato nulla:

1. retro lanciato da 28 s — nessuna PR, nessun branch `retro/`, hook bloccante.
2. retro lanciato da 15 s — stesso quadro, entrambi i repo puliti e allineati ai remoti, zero PR
   aperte, e l'unico segnale non lavorato era proprio quello che il retro vivo aveva in scope.

In entrambi i casi la sola difesa è stata il giudizio dell'orchestratore, che ha guardato gli
agenti vivi prima di obbedire. La guardia della PR `retro/` aperta (citata da `/quickfix`) non può
aiutare: fra il lancio e il primo push un retro non esiste su GitHub. Il costo di sbagliare è due
retro che scrivono regole negli stessi file letti all'avvio, da due rami diversi.
