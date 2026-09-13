# Session handoff — archive

Righe di log spostate qui da SESSION_HANDOFF.md quando superano le ultime 40. Nessuna riga viene persa: questo file si accoda, non si sovrascrive mai. Ordine: la più vecchia in alto, la più recente in fondo — vale dentro un batch e tra un batch e il successivo, un solo ordine.

## Log archiviato
- 2026-09-09 PI-1 PR #18 draft — bin/worktree.sh + cleanup-merged AC6 — 18+21 tests
- 2026-09-09 PI-3 PR #17 draft — doctor warns on stale EPIC/STORY summary Status — 8 tests
- 2026-09-09 PI-2 PR #15 draft — handoff.sh fact refuses at cap — 15 tests
- 2026-09-09 PI-2 PR #15 approved — merge: orchestrator
- 2026-09-09 PI-3 PR #17 approved — merge: orchestrator
- 2026-09-09 PI-1 PR #18 needs work — worktree.sh -B clobbers unpushed commits
- 2026-09-09 PI-1 PR #18 approved round 2 — merge: orchestrator
- 2026-09-09 PI-4 PR #19 draft — guard.sh resolves branch for bare/HEAD git push — 20 tests
- 2026-09-09 PI-4 PR #19 approved — merge: orchestrator
- 2026-09-10 PI-5 PR #21 draft — raised handoff fact cap 30 to 100 — 17 tests
- 2026-09-10 PI-5 PR #21 approved and merged — cap 100, refusal behaviour unchanged
- 2026-09-11 PI-6 PR #24 draft - next-wave.sh total-order sort key for mixed alphanumeric ids - 6 tests
- 2026-09-12 PI-8 PR #30 draft — log rotation archives overflow instead of dropping it — 9 tests
- 2026-09-12 PI-8 PR #30 fix pushed — one archive order, LOGCAP-only hardcode fix — 9 tests
- 2026-09-12 PI-8 PR #30 needs work — archive ordering contradicts its own header comment
- 2026-09-12 PI-8 PR #30 approved — archive one order end to end, LOGCAP sole source of 40, merge: orchestrator
- 2026-09-12 PI-9 PR #32 draft — handoff log/fact now name the file path — 7 tests
- 2026-09-12 PI-9 PR #32 approved — codici di uscita e canali verificati invariati, merge: orchestrator
- 2026-09-12 PI-21 PR #45 draft — pipeline decides own mechanism, root-cause not round-count — no tests (prose)
- 2026-09-12 PI-21 PR #45 needs work — escalation opus residua, causa non tracciata
- 2026-09-12 PI-21 round-2 fix pushed — cause-first everywhere, cap 3, ROUND log, CLAUDE/README/deps aligned
- 2026-09-12 PI-21 PR #45 delta needs work — ROUND non contabile, merged-tree per gruppo
- 2026-09-12 PI-21 round-3 fix pushed — removed ROUND log and merged-tree test, reverted deps edit, added pocket-it /quickfix routing sentence
- 2026-09-12 PI-21 PR #45 approved round 4 — scope ridotto, deps da ritracciare — merge: user
- 2026-09-12 PI-26 PR draft — model_hint replaces model, orchestrator chooses — 3 new tests
- 2026-09-12 PI-26 follow-up — README.md and implementation-planner.md aligned, Files completed pre-review
- 2026-09-12 PI-27 PR draft — deps skill: dependabot.yml edit folded into rollup task, not user/orchestrator — no tests (prose)
- 2026-09-12 PI-26 PR #52 approved — merge: orchestrator
- 2026-09-12 PI-27 PR #51 needs work — AC3 forbids the exact file AC4 requires
- 2026-09-12 orchestrator: dopo il merge di PI-22, aggiungere in shared/implementing-common.md che una migrazione o una backfill non si applica mai a un database reale prima di review e merge: si prova su una copia, e sul database reale la applica chi mergia. Emerso da un task che l'ha applicata prima della review, lasciando il database in uno stato che il codice in produzione gestiva male. Causa anche nella specifica del task, che diceva di provarla su una copia prima che sul database reale senza dire quando.
- 2026-09-12 PI-22 PR #46 draft — cleanup-merged keeps no-own-commit worktrees; lost-worktree stop rule — 17 test checks added
- 2026-09-12 PI-22 PR #46 needs work — fresh branch off merged epic removed
- 2026-09-12 PI-22 PR #46 round 2 — commits of its own read from branch reflog; worktree guard rule executable — 12 checks added
- 2026-09-12 PI-22 PR #46 delta needs work — inherited reflog, §5 BR before branch
- 2026-09-12 PI-22 PR #46 round 3 — copied/renamed reflog restarts; §5 guard simplified, §6 aligned — 2 checks added
- 2026-09-12 PI-13 PR #47 draft — guard denies push reaching base branch behind any prefix/unnamed form — 31 guard cases added (113 total)
- 2026-09-12 PI-13 PR #47 needs work — quoted separators now block legitimate commits
- 2026-09-12 PI-13 review round 2 pushed — threat model reframed, quote-split regression fixed, F5/F6/F8 closed — 140 guard cases, 5 mutations proven
