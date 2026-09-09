# Session handoff

Memoria della pipeline, scritta dagli agenti. Lo stato del lavoro non sta qui (si calcola con `status.sh`): qui stanno i fatti che non scadono e il log degli eventi.

## Fatti che non scadono
<!-- max 30 righe: invarianti, gotcha, decisioni e perché. Chi aggiunge una riga toglie quella che non vale più. -->
- bin/worktree.sh: mai 'git worktree add --track -B <branch>' su un branch locale esistente — resetta il branch su origin e perde i commit non pushati (WIP di un agente killato). Preferire il branch locale se refs/heads/<branch> esiste.

## Log (più recente in alto, ultime 40 righe)
- 2026-09-09 PI-4 PR #19 draft — guard.sh resolves branch for bare/HEAD git push — 20 tests
- 2026-09-09 PI-1 PR #18 needs work — worktree.sh -B clobbers unpushed commits
- 2026-09-09 PI-3 PR #17 approved — merge: orchestrator
- 2026-09-09 PI-2 PR #15 approved — merge: orchestrator
- 2026-09-09 PI-2 PR #15 draft — handoff.sh fact refuses at cap — 15 tests
