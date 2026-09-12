# Session handoff

Memoria della pipeline, scritta dagli agenti. Lo stato del lavoro non sta qui (si calcola con `status.sh`): qui stanno i fatti che non scadono e il log degli eventi.

## Fatti che non scadono
<!-- max 100 righe: invarianti, gotcha, decisioni e perché. Chi aggiunge una riga toglie quella che non vale più. -->
- bin/worktree.sh: mai 'git worktree add --track -B <branch>' su un branch locale esistente — resetta il branch su origin e perde i commit non pushati (WIP di un agente killato). Preferire il branch locale se refs/heads/<branch> esiste.
- guard.sh: il blocco push-su-main non copre 'git push > file' (il target della redirezione conta come posizionale), 'git -c k=v push' e 'env X=1 git push' — fail-open noti, da chiudere in un prossimo task sul hook.
- handoff.sh: CAP is a single variable (currently 100); a stale 'max N righe' comment from an older handoff file is auto-normalised on every subcommand run, so no project file contradicts the enforced cap.
- next-wave.sh (pre-#24): the id regex ^#\s*([A-Za-z]+-[\w.]+) truncated any id with a second embedded hyphen (T-BUG-1 -> tid T-BUG); same-prefix ids collided in the in-memory dict and the later one silently overwrote the earlier — no exception, no warning, task just vanished from the board. Fixed in #24 alongside the mixed-id sort-key TypeError; reproduced independently in review (T-BUG-1 + T-BUG-10 -> '1 total' instead of 2).
- guard.sh force-push detection: matching only the whole tokens -f/--force misses git's clustered short flags (-uf, -fu, -qf) and the +refspec form (+main, +HEAD:main), both of which git accepts as force pushes. Any new force check must cover all three shapes.
- A new bin/*.test.sh or .claude/hooks/*.test.sh must be added to testCommand in .pocket-it.json in the same PR, or it runs once and never again — the repo has no runner that discovers tests by convention.
- guard.sh: the prefix must never authorize a destructive push to the base branch. Beyond force flags there are three more families: the + refspec, branch deletion (--delete, -d, empty refspec), and --mirror/--prune. Any new guard must cover all four.
- force-push detection in guard.sh must cover clustered short flags (-uf, -fu, -qf) and a leading + on the refspec (+main, +HEAD:main), not just -f/--force as standalone tokens
- guard.sh force-push detection must cover short-flag clusters mixed with digit flags (-f4/-4f, IPv4/IPv6) and destructive base-branch removal (-d/--delete, empty-source refspec, --mirror/--prune) — not just -f/--force as separate tokens

## Log (più recente in alto, ultime 40 righe)
- 2026-09-12 PI-23 PR #49 draft — interlinea minima da metriche font, no-clip su reveal/tendina — 0 test (prosa)
- 2026-09-12 orchestrator: dopo il merge di PI-22, aggiungere in shared/implementing-common.md la regola sulle verifiche che reintroducono il difetto (descriverle per effetto nei report) — rinviata per non confliggere con PI-22, emersa dalla review di PI-21
- 2026-09-12 retro: shared/lessons.md:17 offre ancora «apri una sessione nuova prima della terza» come azione dell'orchestratore, che non può farlo — da riformulare al prossimo retro (file suo), segnalato dalla review di PI-20
- 2026-09-12 PI-20 PR #44 approved — nome assente, compattazione non più azione dell'orchestratore — merge: user
- 2026-09-12 PI-20 PR draft — removed private entry point name, fixed compaction wording in two files — 0 tests (prose)
- 2026-09-12 PI-19 PR #42 approved round 3 — nome privato assente dal tree — merge: user
- 2026-09-12 PI-19 fix pushed — report non nomina più l'entry point privato
- 2026-09-12 PI-19 PR #42 delta needs work — report nomina l'entry point privato
- 2026-09-12 PI-19 fix pushed — segnali OR, vincolo assoluto, entry point privato tolto
- 2026-09-12 PI-19 PR #42 needs work — segnali elencati ma non decidono nulla
- 2026-09-12 PI-19 PR draft — compaction call is orchestrator's, not user's — no automated tests
- 2026-09-12 PI-10 PR #36 conflict resolved — unione di fatti e log, 0 righe perse, MERGEABLE
- 2026-09-12 PI-10 PR #36 approved round 3 — tutte e 4 le famiglie di push distruttivo chiuse, 58 casi, merge: orchestrator
- 2026-09-12 PI-10 PR #36 fix pushed — F3 digit cluster + F4 base-branch deletion closed — 10 tests
- 2026-09-12 PI-11 PR #35 conflict resolved — union of handoff log lines, 0 lost, MERGEABLE
- 2026-09-12 PI-10 PR #36 needs work (delta 2) — -f4/-4f clusters and base-branch deletion pass with the prefix
- 2026-09-12 PI-11 PR #35 approved — verify.test.sh registered, run-scoped cleanup — merge: orchestrator
- 2026-09-12 PI-10 CI fix pushed — closed 2 force-push detection gaps (clustered -f, +refspec) — 7 new tests
- 2026-09-12 PI-11 CI fix pushed — registered verify.test.sh in testCommand, scoped its cleanup to per-run path (PR #35 review)
- 2026-09-12 PI-11 PR #35 needs work — new verify.test.sh not registered in testCommand
- 2026-09-12 PI-10 PR #36 needs work — prefix lets clustered -uf and +refspec force through
- 2026-09-12 PI-10 PR #36 draft — authorized push prefix for main, plus intake fix — 10 tests
- 2026-09-12 PI-11 PR #35 draft — verify.sh now recognises *.test.sh — 6 tests
- 2026-09-12 PI-9 PR #32 approved — codici di uscita e canali verificati invariati, merge: orchestrator
- 2026-09-12 PI-9 PR #32 draft — handoff log/fact now name the file path — 7 tests
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
