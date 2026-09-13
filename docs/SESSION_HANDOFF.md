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
- doctor.sh / next-wave.sh id regex, identical in both files: `^#\s*(?=[A-Za-z][A-Za-z0-9]*-[^\s:]*\d)([A-Za-z][A-Za-z0-9]*(?:[-.][A-Za-z0-9]+)+)` — a letter-led prefix (alphanumeric segments allowed, e.g. E2E, I18N, A11Y), one or more `-`/`.` segments, a digit required somewhere past the first hyphen (lookahead), no trailing punctuation swallowed. A plain hyphenated word ("Follow-up") has no digit and is not an id; a segment that mixes letters and digits (`STYLE-PR1`, `WELCOME-A11Y-1`) or a letter suffix on the number (`T-1.2.3a` vs `T-1.2.3b`, `QF-10` vs `QF-10b`) must stay distinct — a prior regex requiring a pure-digit final segment silently dropped the former and merged the latter, the same disappearing-task failure PI-25 exists to catch. Verified by a per-file id comparison against `main` on a real ~400-file board: only word-only, digit-free headers change (id -> none); zero cases of two different ids collapsing to the same string. doctor.sh's duplicate check counts only a declared header id (never the filename-guess fallback); a summary EPIC/STORY file is excluded before the check even sees it (same pre-existing files filter). Do not tighten this regex again without running it file-by-file against a real board, not just counting errors.
- a test asserting 'no error/no duplicate' on a single, un-duplicated fixture is vacuous if the checked condition also produces no error when the id/shape is simply not recognised at all — it can't distinguish 'read and clean' from 'not read'. To prove a shape IS read, declare the same id twice (two files) and require the positive signal (the duplicate error) to fire.
- cleanup-merged.sh: ancestry or topology never proves a branch has work of its own — a fresh branch is an ancestor of its base, and the base it came from may since be merged and deleted. 'Commits of its own' is read from the branch's own reflog (a commit/cherry-pick/revert/am/merge-commit entry, or a rebase replaying one, still in the tip's history); fresh (only 'branch: Created from') and no-reflog branches are kept; 'Branch: copied'/'Branch: renamed' entries restart the reading (git branch -c/-m carry another ref's reflog, commit entries included). Commit criteria cannot tell a live agent on an already-merged branch from a leftover: liveness is the worktree lock (PI-31). A merged PR removes only if its headRefOid contains the local tip. Under set -o pipefail never 'producer | grep -q' (the early exit SIGPIPEs the producer and the pipe reads as false).
- PI-26: a task's Files list can miss occurrences of a repo-wide wording rule (planner didn't grep every phrasing) — before closing such a task, grep the mechanism with several phrasings across the whole repo, not just the cited files.
- guard.sh: redirections (`2>&1 | tail`, `&>/dev/null`, `>file`) are stripped with their fd and target before a push's positionals are counted, since PI-13 round 3; before that a bare push with a redirection stopped looking implicit and passed from the base branch.
- guard.sh push guard is NOT a security boundary: it stops a COOPERATIVE agent pushing to the base branch by MISTAKE in a normal shell form; deliberate evasions (eval, bash -c, env -i, wrappers, quoted/escaped git, on-the-fly aliases, push-affecting config, send-pack) are left to server-side branch protection, and the threat model is at the top of guard.sh. The classifier tokenises the RAW command quote-aware (never a regex split on raw text), with heredoc bodies removed, an unquoted newline and shell keywords (if/then/do/…) as boundaries and redirections stripped. Any git push in a command it cannot parse is DENIED whatever its target (task branches too), unless the exact prefix sits on that push; a backslash-newline is joined before newlines split commands. The audit prefix authorizes only by exact value on the push's own command word.

## Log (più recente in alto, ultime 40 righe)
- 2026-09-13 PI-25 PR #50 conflict resolved — union of handoff/archive (0 lines lost), next-wave.test both blocks kept; PI-26 fixtures T-HI/T-LO -> T-HI-1/T-LO-1 (digit-less ids are not ids under PI-25) — testCommand 357 ok
- 2026-09-13 PI-25 PR #50 approved (delta 5) — merge: user
- 2026-09-13 PI-25 PR #50 fix pushed round 5 — repo8 covers all three alnum-segment positions (prefix, middle, trailing)
- 2026-09-13 PI-25 PR #50 needs work (delta 4) — prefix-digit id shape untested in doctor — cause: example-not-class
- 2026-09-13 PI-25 PR #50 fix pushed round 4 — repo8's vacuous 'no error' assertions replaced with real duplicate pairs per id shape
- 2026-09-13 PI-25 PR #50 needs work (delta 3) — doctor alnum-id test is vacuous — cause: other: vacuous test
- 2026-09-13 PI-25 PR #50 fix pushed round 3 — id regex allows alnum segments and letter suffixes — file-by-file compare vs main on a real board
- 2026-09-13 PI-13 PR #47 approved round 4 — parse error denies every push, continuations joined — merge: user
- 2026-09-13 BUDGET PI-13 ~100 turns vs 120 over 4 review rounds (47/26/19/9) — progressing: 10 commits, 179 guard tests green — spec first framed the hook as a security boundary, each round found new shell grammar; reframed to cooperative-agent threat model in round 2
- 2026-09-13 PI-13 review round 4 pushed — unparseable commands deny every push, continuations joined — 179 guard cases
- 2026-09-13 PI-13 PR #47 delta needs work round 3 — parser fallback lets implicit push through
- 2026-09-13 PI-13 review round 3 pushed — redirections, newlines, keywords covered; lexer error denies — 161 guard cases, 4 mutations proven
- 2026-09-13 PI-22 PR #46 approved round 3 — copied/renamed branches kept, §5/§6 aligned — merge: user
- 2026-09-12 PI-25 PR #50 needs work (delta) — id regex drops alphanumeric real ids — cause: example-not-class
- 2026-09-12 PI-25 PR #50 fix pushed — id regex now requires a numeric segment, AC3 test hardened
- 2026-09-12 PI-25 PR #50 needs work — hyphenated words read as task ids — cause: first-round
- 2026-09-12 PI-25 PR draft — doctor.sh flags duplicate task ids as ERROR — 8 new tests
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
- 2026-09-12 PI-13 PR #47 delta needs work — redirections, newlines, lexer error reopen main
