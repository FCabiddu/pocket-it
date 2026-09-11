# PI-6 — Align the retro thresholds and the agent read budget to the 100-fact cap

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
**Files**: `.claude/agents/retro.md`, `.claude/agents/shared/implementing-common.md`
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**: task/pi-6-retro-thresholds
**PR**: PENDING

## Goal
PI-5 raised the handoff fact cap from 30 to 100 in `bin/handoff.sh`, but three prose lines elsewhere still assume 30 and now contradict it. Left as they are, the retro would prune a 100-line facts section down to 20 on its next run — undoing PI-5 — and every implementing agent would read only the first 30 of up to 100 facts, which is the memory loss the cap raise exists to prevent. The owner has set the new thresholds; this task writes them in.

## Acceptance criteria
- [ ] AC1 — Given `.claude/agents/retro.md:47` ("Keep the section ≤ 30 lines"), when it is read after this change, then it says ≤ 100 lines and still tells the retro to replace a fact now covered by a rule.
- [ ] AC2 — Given the "Facts hygiene (every run)" paragraph at `.claude/agents/retro.md:57`, when it is read after this change, then it states the cap as 100, triggers the hygiene pass at **≥ 85 facts**, and targets **≤ 70 facts** — replacing the old 30 / ≥ 25 / ≤ 20 numbers. Everything else in that paragraph (what gets moved to best-practices, what gets deleted, listing every moved or deleted fact in the report so the user can veto) is unchanged.
- [ ] AC3 — Given `.claude/agents/shared/implementing-common.md:39` ("at most 30 lines"), when it is read after this change, then the read budget is the whole facts section up to the cap of 100 one-line facts, and the `awk` command on that line is unchanged.
- [ ] AC4 — Given the repository after this change, when `grep -rn "30" .claude/agents/retro.md .claude/agents/shared/implementing-common.md` runs, then no remaining hit refers to the facts cap or to a facts threshold (hits about other subjects, such as the "older than 30 days" rule for promoting a stable fact, stay as they are — that one is a date, not a count).
- [ ] AC5 — Given the change, when `bash bin/handoff.test.sh` and the other test files in `testCommand` run, then all are green — this task touches prose only and must not change any script behaviour.

## Tests expected
No new tests: the files are agent prose, not code. Run the repository's `testCommand` unchanged to prove nothing regressed. Integration/E2E: off for this repo.

## Notes
These three lines were found by the reviewer of PI-5, who correctly refused to edit them inside that PR. The numbers in AC2 keep the old proportions at the new cap: the old pass triggered at 83% of the cap and targeted 67% of it. Do not touch `bin/handoff.sh` — `CAP=100` there is already the single source of truth, and this task only makes the prose agree with it.
