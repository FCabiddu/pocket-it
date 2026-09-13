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
