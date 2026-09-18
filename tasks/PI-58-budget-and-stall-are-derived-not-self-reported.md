# PI-58 — BUDGET and STALL must be derived from measured usage, not asked of the agent

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: M
**Budget**: 200
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/usage-report.py, bin/verify.sh, bin/verify.test.sh, bin/doctor.sh, bin/doctor.test.sh, possibly a new bin/ script and its test
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**: 
**PR**: 

## Goal
Agents are told to log a `BUDGET …` line when they overrun their turn budget and a `STALL …` line when they stop making progress. Measured over 13 days: **zero** such lines, against five developers that went past 150 turns in a single day. The rule is read, the line is not written — and the one signal the retrospective has for "this estimate was wrong" is therefore blind, which makes every estimate correction it proposes rest on nothing.

Self-reporting is the wrong mechanism for this: the moment an agent is furthest past its budget is the moment it is least likely to stop and say so. The data already exists — `bin/usage-report.py` reads what each session actually spent. Derive the line from the measurement and make the derivation a gate at task closing, so a task cannot close with an unrecorded overrun.

**Correction to the premise, measured 2026-09-18 and more precise than the count above.** The failure is not only that agents stay silent. One developer overran its budget by 60% — **194 turns against a `Budget` of 120** — and reported "Effort: 72 min … no BUDGET" in good faith: it had converted a budget written in **turns** into **minutes** and compared against the wrong unit, so by its own arithmetic it was well inside. An agent asked to compare its spend against its budget cannot be trusted to agree with the board on what the number even measures. This makes the derivation mandatory rather than merely better.

## Acceptance criteria
- [ ] AC1 — Given a finished task whose measured turns exceed its `**Budget**`, when the closing gate runs, then it emits the `BUDGET` line itself, with the measured number and the budget it exceeded — no agent is asked to volunteer it, and the line's shape is the one the retrospective already parses today (verify what that is before changing it).
- [ ] AC2 — Given a finished task within its budget, when the gate runs, then it emits nothing and exits 0: the gate must not turn into noise that gets ignored, which is how the current rule failed.
- [ ] AC3 — Given a measurable definition of a stall, when it is chosen, then the report states it in one sentence and says why it is measurable from the available data — and if it is **not** derivable from what `usage-report.py` can see, the report says so plainly and AC3 is closed as not-doable rather than approximated. A stall detector that fires on the wrong thing is worse than none.
- [ ] AC4 — Given the gate, when a task closes with an overrun that it did not record, then the gate is **red**: this is the half that makes it different from the rule it replaces. Where the gate lives (`verify.sh`, the closing step of the lane, or a new script) is the developer's call, argued in the report against where the data is actually available at that moment.
- [ ] AC5 — Given a session whose transcript `usage-report.py` cannot resolve — measured three times in a row on one project, because the work ran from another session's working directory — when the gate runs, then it says it could not measure, and **does not** report zero as if it had measured zero. A missing measurement is not a green.
- [ ] AC6 (mutation) — Given the gate, when an overrun is injected into a fixture, then the gate goes red; when the fixture is restored, green. A gate that cannot be made to fire is not installed.
- [ ] AC7 — Given the unit the board writes `**Budget**` in, when the gate compares, then both sides of the comparison are in that same unit and the unit is **named in the emitted line** ("194 turns against a budget of 120 turns"), never left implicit. A comparison whose two sides are in different units is the defect this task exists to remove, not an edge case of it: measured once, it turned a 60% overrun into a clean report.
- [ ] AC8 — Given a task whose spend must be attributed, when the gate measures it, then it resolves the spend **by agent id** rather than by session or by working directory. The two are not the same thing: several agents run against one project at once, and the working directory a session was launched from is what made `usage-report.py` return nothing four times in a row (AC5).

## Tests expected
Unit tests for the derivation (over/under/at the budget boundary, and the unmeasurable case of AC5) and for the gate's red/green wiring. Integration/E2E: not needed.

## Notes
- Origin: two retrospectives. The first counted 0 `BUDGET`/`STALL` lines in 13 days against five developers over 150 turns in one day; the second, one window later, measured a third empty window against seven such developers and found the unit confusion in the Goal. Re-take both numbers before starting, because they move.
- AC5's failure mode is already known to be real: `usage-report.py --days 14 .` has returned no transcript for a project three passes in a row, and each time the retrospective carried on with the other signals. That is the right behaviour for a report and the wrong behaviour for a gate.
- Estimate is M, not S, because the honest answer to AC3 may be "not derivable", and finding that out is most of the work.
- pocket-it is public: mechanism only, no consumer-project names, paths or anecdotes in code, tests, commits or PR text.

## Second correction, measured 2026-09-18 — the input side of AC7, and what `elapsed` cannot see

Three measurements from the retrospective of 2026-09-18. None of them changes this task's purpose; two of them make an existing AC unsatisfiable as written, so they arrive as ACs rather than as notes.

**1. The board does not name the unit, so AC7 has nothing to compare against.** `**Budget**` is specified in **minutes** by the planner template and by the shared rules §8, but **58 of the 61 task files on this board carry a bare number** (`grep -cE '^\*\*Budget\*\*: [0-9]+$'` over `tasks/*.md` = 58; with an explicit `min` = 3), and the bare values are the old turn-era table (60 / 120 / 200), not the minute table (45 / 90 / 150 / 240). The cause was a one-line contradiction between templates — the quickfix skill still emitted `turns from the estimate` while two other start-read files said minutes — and it is fixed in the same retrospective PR that adds this section. The **existing 58 files keep their bare numbers**: this task is what stops the next one.

- [ ] AC9 — Given a task file whose `**Budget**` value carries no unit, when `bin/doctor.sh` runs, then it is a **warning naming the file** (not an error: 58 such files exist and they are history, so an error would make `doctor.sh` unusable and it would be switched off — the failure mode this whole task exists to avoid). Given a `**Budget**` value that does carry a unit, nothing is said. Mutation: add a unitless `Budget` to a fixture task → the warning appears and names it; remove it → silent.
- [ ] AC10 — Given the gate of AC1 reading a bare `**Budget**: N`, when it compares, then it converts at the documented 47 s/turn rate rather than reading `N` as minutes, and the emitted line names **both** the raw field and the converted value ("140 min worked against a budget of 200 turns = 157 min"). This is AC7's requirement applied to the side the board owns; without it AC7 can only be satisfied by guessing.

**2. `elapsed` is not a measure of the agent, which is why AC3's honest answer may be "not derivable".** The one `BUDGET` line this correction was written from declares **238 min against 157**, and its own subtraction removes **~99** of them as a suspended machine — leaving roughly **140 worked, inside budget**. The 99 minutes are real and measurable (two consecutive commits, 01:34:05 and 03:13:21), but *what they were* is not: by §8's own definition — 20 minutes with no commit and no new passing test — that same gap is a **stall**, and nothing in the data distinguishes a stalled agent from a closed laptop. Only the agent's word separates them, and an agent's word about its own exception is precisely what this task replaces.

- [ ] AC11 — Given a gap in a task's timeline that no commit and no test result explains, when the derivation runs, then it is **excluded from the worked figure and reported as unattributed time with its length**, never silently counted as work and never silently counted as idle. If `usage-report.py` can attribute the gap by agent id (AC8), attribute it; if it cannot, the line says `unattributed: N min` and the retrospective treats the overrun as unproven. An overrun computed from wall clock that contains an unexplained gap is not evidence, and the first line of this kind ever acted on would have produced a wrong estimate correction in exactly this way.

**3. The premise "zero such lines" is no longer true here, and the lines that exist are not comparable.** This repo's own memory holds **three** `BUDGET` lines (`handoff.sh grep "BUDGET|STALL"`), dated 2026-09-13 (x2) and 2026-09-18. Two are written in **turns** ("~100 turns vs 120", "4 review rounds vs S(120)") and one in **minutes**. So the instrumentation is not merely silent — when it does fire it fires in whichever unit the agent chose, which is the same defect as the Goal's and makes a trend across the three impossible to compute. AC7's "the unit is named in the emitted line" is what fixes this; keep it.
