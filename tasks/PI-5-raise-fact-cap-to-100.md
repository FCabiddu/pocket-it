# PI-5 — Raise the handoff fact cap from 30 to 100

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: XS
**Budget**: 60
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: `bin/handoff.sh`, `bin/handoff.test.sh`, `CLAUDE.md`
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**: 
**PR**: 

## Goal
PI-2 made `handoff.sh fact` refuse a new fact at the cap instead of silently dropping the oldest — the right behaviour, but the cap of 30 is too small. A real project hit 30/30 today: two agents in one wave were refused, one of them worked around the refusal by deleting an older fact on its own initiative, which is exactly the decision the cap is meant to hand to the retro. The owner wants the cap raised to 100. The refusal behaviour at the cap must not change — only the number.

## Acceptance criteria
- [ ] AC1 — Given a handoff file with 99 facts, when `handoff.sh fact "new"` runs, then the fact lands, exit code is 0, and stderr prints `handoff: facts 100/100 — cap reached, next fact will be refused`.
- [ ] AC2 — Given a handoff file with 100 facts, when `handoff.sh fact "fact number 101"` runs, then the file is unchanged, exit code is 3, and stderr prints exactly one line: `handoff: facts at cap (100/100) — not added. Ask the retro to promote stable facts to best-practices, or remove one line by hand: fact number 101`.
- [ ] AC3 — Given `handoff.sh show` with facts at the cap, when it runs, then its output ends with `facts: 100/100 (cap)`; below the cap that marker is absent, as today.
- [ ] AC4 — Given an existing project handoff file whose HTML comment still says `max 30 righe`, when any `handoff.sh` subcommand runs against it, then the command works unchanged and the comment is updated to say 100 — no project is left with a comment that contradicts the enforced cap.
- [ ] AC5 — Given the change, when `bash bin/handoff.test.sh` runs, then it is green, and every 30-based number in it has been updated to the new cap rather than the cap being special-cased in the script to keep old tests passing.
- [ ] AC6 — Given `CLAUDE.md`, when the learning-loop row is read, then the facts layer says the new cap instead of `≤ 30`.

## Tests expected
Unit: `bin/handoff.test.sh` updated so each existing assertion covers the new cap (99 lands with the warning, 101 is refused with exit 3, the `show` marker, the comment normalisation). Integration/E2E: off for this repo.

## Notes
The cap lives in `bin/handoff.sh:46` (`CAP=30`), and the number is repeated in the header comment at line 7, the file-template comment at line 17, the `comment=` variable at line 53 and the `show` marker at line 64. Do not hard-code 100 in more places than needed — derive the messages from `CAP` where the script already can. The test file has the number in its own assertions and header comment. Filling a fixture to 99 facts in the test should be a loop, not 99 literal lines.
