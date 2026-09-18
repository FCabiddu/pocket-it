# PI-58 — BUDGET and STALL must be derived from measured usage, not asked of the agent

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: M
**Budget**: 200
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/usage-report.py, bin/verify.sh, bin/verify.test.sh, possibly a new bin/ script and its test
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**: 
**PR**: 

## Goal
Agents are told to log a `BUDGET …` line when they overrun their turn budget and a `STALL …` line when they stop making progress. Measured over 13 days: **zero** such lines, against five developers that went past 150 turns in a single day. The rule is read, the line is not written — and the one signal the retrospective has for "this estimate was wrong" is therefore blind, which makes every estimate correction it proposes rest on nothing.

Self-reporting is the wrong mechanism for this: the moment an agent is furthest past its budget is the moment it is least likely to stop and say so. The data already exists — `bin/usage-report.py` reads what each session actually spent. Derive the line from the measurement and make the derivation a gate at task closing, so a task cannot close with an unrecorded overrun.

## Acceptance criteria
- [ ] AC1 — Given a finished task whose measured turns exceed its `**Budget**`, when the closing gate runs, then it emits the `BUDGET` line itself, with the measured number and the budget it exceeded — no agent is asked to volunteer it, and the line's shape is the one the retrospective already parses today (verify what that is before changing it).
- [ ] AC2 — Given a finished task within its budget, when the gate runs, then it emits nothing and exits 0: the gate must not turn into noise that gets ignored, which is how the current rule failed.
- [ ] AC3 — Given a measurable definition of a stall, when it is chosen, then the report states it in one sentence and says why it is measurable from the available data — and if it is **not** derivable from what `usage-report.py` can see, the report says so plainly and AC3 is closed as not-doable rather than approximated. A stall detector that fires on the wrong thing is worse than none.
- [ ] AC4 — Given the gate, when a task closes with an overrun that it did not record, then the gate is **red**: this is the half that makes it different from the rule it replaces. Where the gate lives (`verify.sh`, the closing step of the lane, or a new script) is the developer's call, argued in the report against where the data is actually available at that moment.
- [ ] AC5 — Given a session whose transcript `usage-report.py` cannot resolve — measured three times in a row on one project, because the work ran from another session's working directory — when the gate runs, then it says it could not measure, and **does not** report zero as if it had measured zero. A missing measurement is not a green.
- [ ] AC6 (mutation) — Given the gate, when an overrun is injected into a fixture, then the gate goes red; when the fixture is restored, green. A gate that cannot be made to fire is not installed.

## Tests expected
Unit tests for the derivation (over/under/at the budget boundary, and the unmeasurable case of AC5) and for the gate's red/green wiring. Integration/E2E: not needed.

## Notes
- Origin: a retrospective's own count — 0 `BUDGET`/`STALL` lines in 13 days against five developers over 150 turns in one day. The number is the measurement that justifies this task; re-take it before starting, because it moves.
- AC5's failure mode is already known to be real: `usage-report.py --days 14 .` has returned no transcript for a project three passes in a row, and each time the retrospective carried on with the other signals. That is the right behaviour for a report and the wrong behaviour for a gate.
- Estimate is M, not S, because the honest answer to AC3 may be "not derivable", and finding that out is most of the work.
- pocket-it is public: mechanism only, no consumer-project names, paths or anecdotes in code, tests, commits or PR text.
