# Session handoff

Memoria della pipeline, scritta dagli agenti. Lo stato del lavoro non sta qui (si calcola con `status.sh`): qui stanno i fatti che non scadono e il log degli eventi.

## Fatti che non scadono
<!-- max 100 righe: invarianti, gotcha, decisioni e perché. Chi aggiunge una riga toglie quella che non vale più. -->
- bin/worktree.sh: mai 'git worktree add --track -B <branch>' su un branch locale esistente — resetta il branch su origin e perde i commit non pushati (WIP di un agente killato). Preferire il branch locale se refs/heads/<branch> esiste.
- guard.sh: il blocco push-su-main non copre 'git push > file' (il target della redirezione conta come posizionale), 'git -c k=v push' e 'env X=1 git push' — fail-open noti, da chiudere in un prossimo task sul hook.
- handoff.sh: CAP is a single variable (currently 100); a stale 'max N righe' comment from an older handoff file is auto-normalised on every subcommand run, so no project file contradicts the enforced cap.
- next-wave.sh (pre-#24): the id regex ^#\s*([A-Za-z]+-[\w.]+) truncated any id with a second embedded hyphen (T-BUG-1 -> tid T-BUG); same-prefix ids collided in the in-memory dict and the later one silently overwrote the earlier — no exception, no warning, task just vanished from the board. Fixed in #24 alongside the mixed-id sort-key TypeError; reproduced independently in review (T-BUG-1 + T-BUG-10 -> '1 total' instead of 2).

## Log (più recente in alto, ultime 40 righe)
- 2026-09-12 PI-8 PR #30 approved — archive one order end to end, LOGCAP sole source of 40, merge: orchestrator
- 2026-09-12 PI-8 PR #30 needs work — archive ordering contradicts its own header comment
- 2026-09-12 PI-8 PR #30 fix pushed — one archive order, LOGCAP-only hardcode fix — 9 tests
- 2026-09-12 PI-8 PR #30 draft — log rotation archives overflow instead of dropping it — 9 tests
- 2026-09-11 PI-6 PR #24 draft - next-wave.sh total-order sort key for mixed alphanumeric ids - 6 tests
- 2026-09-10 PI-5 PR #21 approved and merged — cap 100, refusal behaviour unchanged
- 2026-09-10 PI-5 PR #21 draft — raised handoff fact cap 30 to 100 — 17 tests
- 2026-09-09 PI-4 PR #19 approved — merge: orchestrator
- 2026-09-09 PI-4 PR #19 draft — guard.sh resolves branch for bare/HEAD git push — 20 tests
- 2026-09-09 PI-1 PR #18 approved round 2 — merge: orchestrator
- 2026-09-09 PI-1 PR #18 needs work — worktree.sh -B clobbers unpushed commits
- 2026-09-09 PI-3 PR #17 approved — merge: orchestrator
- 2026-09-09 PI-2 PR #15 approved — merge: orchestrator
- 2026-09-09 PI-2 PR #15 draft — handoff.sh fact refuses at cap — 15 tests
- 2026-09-09 PI-3 PR #17 draft — doctor warns on stale EPIC/STORY summary Status — 8 tests
- 2026-09-09 PI-1 PR #18 draft — bin/worktree.sh + cleanup-merged AC6 — 18+21 tests
