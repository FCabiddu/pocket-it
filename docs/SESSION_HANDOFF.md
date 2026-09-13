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
- cleanup-merged.sh: ancestry or topology never proves a branch has work of its own — a fresh branch is an ancestor of its base, and the base it came from may since be merged and deleted. 'Commits of its own' is read from the branch's own reflog (a commit/cherry-pick/revert/am/merge-commit entry, or a rebase replaying one, still in the tip's history); fresh (only 'branch: Created from') and no-reflog branches are kept; 'Branch: copied'/'Branch: renamed' entries restart the reading (git branch -c/-m carry another ref's reflog, commit entries included). Commit criteria cannot tell a live agent on an already-merged branch from a leftover: liveness is the worktree lock (PI-31). A merged PR removes only if its headRefOid contains the local tip. Under set -o pipefail never 'producer | grep -q' (the early exit SIGPIPEs the producer and the pipe reads as false).
- PI-26: a task's Files list can miss occurrences of a repo-wide wording rule (planner didn't grep every phrasing) — before closing such a task, grep the mechanism with several phrasings across the whole repo, not just the cited files.
- Hooks, skills and agents must be read from the installed copy (~/.claude/pocket-it-live, written only by bin/install-live.sh from the published main), never from the development checkout; after every merge into main run: bash ~/.claude/pocket-it-live/bin/install-live.sh — until the README switch is applied, the development checkout is still what every session runs.
- A hook command that runs a guard file fails open whenever that file is absent or half-written (exit 127 is non-blocking): hook commands are written 'bash …/guard.sh || exit 2' (guard.sh exits only 0 or 2), and nothing updates the copy the hook reads in place — build beside, then exchange. A symlink rename is not atomic for readers on macOS (measured); renamex_np RENAME_SWAP of directories is.

## Log (più recente in alto, ultime 40 righe)
- 2026-09-13 PI-30 PR #53 needs work — guard file absent during update fails open
- 2026-09-13 PI-30 PR #53 draft — installed copy separate from dev checkout — 36 tests
- 2026-09-13 PI-22 PR #46 approved round 3 — copied/renamed branches kept, §5/§6 aligned — merge: user
- 2026-09-12 PI-22 PR #46 round 3 — copied/renamed reflog restarts; §5 guard simplified, §6 aligned — 2 checks added
- 2026-09-12 PI-22 PR #46 delta needs work — inherited reflog, §5 BR before branch
- 2026-09-12 PI-22 PR #46 round 2 — commits of its own read from branch reflog; worktree guard rule executable — 12 checks added
- 2026-09-12 PI-22 PR #46 needs work — fresh branch off merged epic removed
- 2026-09-12 PI-22 PR #46 draft — cleanup-merged keeps no-own-commit worktrees; lost-worktree stop rule — 17 test checks added
- 2026-09-12 orchestrator: dopo il merge di PI-22, aggiungere in shared/implementing-common.md che una migrazione o una backfill non si applica mai a un database reale prima di review e merge: si prova su una copia, e sul database reale la applica chi mergia. Emerso da un task che l'ha applicata prima della review, lasciando il database in uno stato che il codice in produzione gestiva male. Causa anche nella specifica del task, che diceva di provarla su una copia prima che sul database reale senza dire quando.
- 2026-09-12 PI-27 PR #51 needs work — AC3 forbids the exact file AC4 requires
- 2026-09-12 PI-26 PR #52 approved — merge: orchestrator
- 2026-09-12 PI-27 PR draft — deps skill: dependabot.yml edit folded into rollup task, not user/orchestrator — no tests (prose)
- 2026-09-12 PI-26 follow-up — README.md and implementation-planner.md aligned, Files completed pre-review
- 2026-09-12 PI-26 PR draft — model_hint replaces model, orchestrator chooses — 3 new tests
- 2026-09-12 PI-21 PR #45 approved round 4 — scope ridotto, deps da ritracciare — merge: user
- 2026-09-12 PI-21 round-3 fix pushed — removed ROUND log and merged-tree test, reverted deps edit, added pocket-it /quickfix routing sentence
- 2026-09-12 PI-21 PR #45 delta needs work — ROUND non contabile, merged-tree per gruppo
- 2026-09-12 PI-21 round-2 fix pushed — cause-first everywhere, cap 3, ROUND log, CLAUDE/README/deps aligned
- 2026-09-12 PI-21 PR #45 needs work — escalation opus residua, causa non tracciata
- 2026-09-12 PI-21 PR #45 draft — pipeline decides own mechanism, root-cause not round-count — no tests (prose)
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
