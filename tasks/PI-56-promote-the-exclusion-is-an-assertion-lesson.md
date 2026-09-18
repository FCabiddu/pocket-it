# PI-56 — Promote the "an exclusion is an assertion" lesson into §7 and delete its line

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
**Files**: .claude/agents/shared/implementing-common.md, .claude/agents/shared/lessons.md
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**: 
**PR**: 

## Goal
One line of `.claude/agents/shared/lessons.md` — dated 2026-09-17, `provisional`, the one whose `WHEN` reads *"a report offers a full classification as completeness evidence"* (find it with `grep -n 'full classification' .claude/agents/shared/lessons.md`; its line number moves whenever another line is added or removed above it) — already declares its destination: `shared/implementing-common.md §7`. A second occurrence has now been measured on a different kind of task, which is what the `provisional` state was waiting for. The lesson is therefore due for promotion, and promotion means **both** halves: the rule is written at the destination **and** the line is deleted from `lessons.md`. A `confirmed` line that stays in the file is a defect, not a state — every line there is read at every agent launch, so a duplicate is paid for on each one.

The rule generalises past the two cases that produced it: it is about any list or classification handed over as evidence of completeness, not about a particular kind of file.

## Acceptance criteria
- [ ] AC1 — Given `shared/implementing-common.md` §7, when the rule is added, then it says: a list or classification offered as evidence of completeness carries, for every row, the command that produced it or excluded it; an exclusion is an assertion, and a row excluded by reasoning counts as **not looked at**; a justification in place of a measurement is a defect even when the conclusion turns out to be right.
- [ ] AC2 — Given `.claude/agents/shared/lessons.md`, when AC1 has landed, then that line — identified by its `WHEN` text, not by a line number — is **deleted in the same commit**, not reworded and not marked `confirmed`. `git diff` shows the file one line shorter than the head this branch started from, and nothing else changed in it.
- [ ] AC3 — Given the new §7 text, when it is read next to what §7 already says, then it does not duplicate a rule already there: if an existing bullet covers part of it, the two are merged into one instead of sitting side by side. The report says which case it was.
- [ ] AC4 — Given the repo's 300-**byte** guard on lesson lines and the lesson count, when the change is done, then `awk '/^- 20/{if (length($0) > 300) print NR, length($0)}' .claude/agents/shared/lessons.md` prints nothing and `grep -c '^- 20' .claude/agents/shared/lessons.md` returns exactly one less than it returned on the head this branch started from — take that number yourself at the start, do not carry one in from this file.
- [ ] AC5 — Given the change, when `bin/doctor.sh` and the repo's test command run, then both stay green.

## Tests expected
None — text only. Integration/E2E: not needed.

## Notes
- Suggested wording, already free of any project name — improve it if §7's voice differs, but do not weaken it: «Un elenco o una classificazione consegnati come prova di completezza portano, per ogni riga, il comando che l'ha prodotta o l'ha esclusa: un'esclusione è un'affermazione, e una riga esclusa a ragionamento si conta come non guardata. Una motivazione al posto di una misura è un difetto anche quando la conclusione è giusta.»
- `shared/implementing-common.md` is also edited by PI-16 (§6, in review on PR #93). Start from a base that has it, or expect to resolve the same file twice.
- pocket-it is public: the rule is stated as a mechanism, with no consumer-project names, paths or anecdotes — the two occurrences that produced it stay out of the text.
