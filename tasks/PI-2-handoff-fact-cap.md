# PI-2 — handoff.sh: refuse a new fact at the cap instead of silently dropping the oldest

**Status**: Done
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: XS
**Budget**: 60
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: `bin/handoff.sh`, `bin/handoff.test.sh`
**TAD**: none
**Contract**: none
**Branch**: task/PI-2-handoff-fact-cap
**PR**: 

## Goal
`bin/handoff.sh fact "…"` caps the facts section at 30 lines by dropping the oldest with only a warning. A project reached 30/30 today, so the next fact would erase knowledge silently. At the cap the command must fail loudly so the agent reports it and the retro prunes (retro promotes stable facts to best-practices; that is a separate change).

## Acceptance criteria
- [x] AC1 — Given a handoff file with 30 facts, when `handoff.sh fact "new"` runs, then the file is unchanged, exit code is 3, and stderr prints one line: `handoff: facts at cap (30/30) — not added. Ask the retro to promote stable facts to best-practices, or remove one line by hand: <the new fact text>`.
- [x] AC2 — Given 29 facts, when a fact is added, then it lands (exit 0) and stderr prints `handoff: facts 30/30 — cap reached, next fact will be refused`.
- [x] AC3 — Given any count, when `handoff.sh log "…"` runs, then behaviour is unchanged (log still rotates at 40 silently — the log is history, facts are knowledge).
- [x] AC4 — Given `handoff.sh show`, when facts are at cap, then the output ends with the line `facts: 30/30 (cap)`.
- [x] AC5 — Given `bin/handoff.test.sh` (new), when it runs, then it covers AC1–AC4 on a temp file, `ok`/`FAIL` per case, exit 1 on FAIL; add it to `testCommand` in `.pocket-it.json`.

## Non-goals
No change to the fact format, the section headers, or the log cap.

## Tests expected
`bin/handoff.test.sh`. Integration/E2E: not needed.

## Notes
The python block inside `handoff.sh` does the cap logic (search `30`). Facts are the `- ` lines under `## Fatti che non scadono`.
