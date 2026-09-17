# PI-53 — A check that refuses `lessons.md` when a lesson is over the cap, still `confirmed`, or has no `WHERE`

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: S
**Budget**: 90
**Risk**: low
**Depends on**: PI-52
**Wave**: 1
**Files**: `bin/lessons-check.sh`, `bin/lessons-check.test.sh`, `.pocket-it.json` (add the new test to `testCommand`), `.claude/agents/retro.md` (one line: the retro runs the check before opening its PR)
**TAD**: none — follow the conventions of `bin/doctor.sh` and its test
**Contract**: none
**Branch**: 
**PR**: 

## Goal

`.claude/agents/shared/lessons.md` is read at Step 0 by developer, qa-engineer, reviewer and implementation-planner, so every byte in it is paid for at every launch. Three properties keep it cheap and keep the promotion pipeline moving, and all three are today only discipline: a lesson line stays within **300 bytes**; no line is in state `confirmed` (confirming a lesson means writing its rule at its `WHERE` and deleting the line in the same PR — a `confirmed` line left in the file is a defect, not a state); every line carries a `WHERE` naming the destination of its future rule. Discipline is not enough, and the evidence is the pass that introduced the cap: its own author shipped five lines 1 to 6 bytes over it, having measured characters where the reader measured bytes. This task builds `bin/lessons-check.sh`, a read-only check that exits non-zero and prints the accepted form, so the file goes red on the author's own gate instead of being audited by hand afterwards.

**Threat model.** It protects against a `lessons.md` that silently grows past what agents can afford to read, and against lessons that accumulate as `confirmed` instead of becoming rules. It deliberately does **not** judge the content of a lesson (whether it is true, useful, or belongs in a project's best-practices instead), does not check that the `WHERE` destination exists or that the rule was actually written there, and does not touch any other file. Those stay with the retro and its reviewer.

## Acceptance criteria

- [ ] AC1 — Given a `lessons.md` where every lesson line is ≤ 300 bytes, none is `confirmed` and each carries a `WHERE` field, when `bash bin/lessons-check.sh` runs, then it exits 0 and prints one summary line with the number of lessons, the maximum and the average byte length.
- [ ] AC2 — Given a file holding a lesson line of 301 bytes, when the check runs, then it exits non-zero and names that line by its file line number and its measured byte length, and prints the accepted form once.
- [ ] AC3 — Given a file holding a line whose status field is `confirmed`, when the check runs, then it exits non-zero and says that confirming a lesson means writing its rule at its `WHERE` and deleting the line in the same PR.
- [ ] AC4 — Given a lesson line with no `WHERE` field, when the check runs, then it exits non-zero and names that line.
- [ ] AC5 — Given a file with several defects at once, when the check runs, then it reports **every** offending line, not only the first, and exits non-zero once.
- [ ] AC6 — Given a lesson line of exactly 300 bytes, when the check runs, then it is accepted: the cap is inclusive, and the boundary is asserted on both sides (300 passes, 301 fails).
- [ ] AC7 — Given the check is pointed at a path, when it runs, then it reads that path and writes nothing anywhere: the file is left byte-identical, and the check works on a file given as its first argument (default: the repo's own `lessons.md`) so the test can run it against fixtures.
- [ ] AC8 — Given the repository's current `lessons.md`, when the check runs, then it exits 0 — the check is added to `testCommand` in `.pocket-it.json` in the same PR, so the repo's own suite carries it from then on.

## Non-goals

- No edit to `bin/verify.sh` or `bin/verify.test.sh` — PI-51 and PI-52 own those files. The wiring of this check into `verify.sh` is done by whoever lands after **PI-52**, which is why this task depends on it; until then `testCommand` (AC8) is what runs it.
- No rewriting, sorting, truncating or auto-fixing of `lessons.md`: the check refuses, it never repairs. A tool that silently rewrites shared memory is a worse defect than the one it fixes.
- No judgement on the content, the date, the status vocabulary beyond `confirmed`, or the existence of the `WHERE` destination.

## Tests expected

`bin/lessons-check.test.sh`, in the shape of `bin/doctor.test.sh` (fixtures in a temporary directory, one `ok`/`FAIL` line per assertion, exit non-zero on any FAIL). The cases are generated from the class, not hand-picked: the three rules (byte cap, status, `WHERE`) × the three positions (first lesson line, a middle one, the last) × valid/invalid, plus the boundary pair 300/301 bytes of AC6, plus a fixture holding one defect of each kind at once (AC5), plus a byte-identical check of the fixture after the run (AC7), plus the real `lessons.md` (AC8). Every rule's test runs the mutation that must turn it red — a fixture that satisfies the rule, mutated by one byte or one word into the violation — and asserts the exit code **and** the offending line number in the output, never just "non-zero". Integration/E2E: not needed for this task.

## Notes

- Measure with `awk '{print length($0)}'` under the C locale, or `wc -c` on the single line: bytes, because that is what every check in `bin/` already counts and because the separators in the fixed form (`·`, `—`) are multi-byte — the character count reads up to 14 lower on a full line and that gap is exactly how five over-cap lines shipped.
- A "lesson line" is a line matching `^- 20[0-9][0-9]-` at the top level of the `## Lessons` section; the header, the rules bullets and blank lines are not lessons and are not measured. Do not anchor to the list of statuses or to the field order: anchor to that line shape and to the presence of ` · WHERE ` and ` · confirmed · ` as fields between separators, so a lesson mentioning the word "confirmed" inside its `BECAUSE` clause is not a false positive — that case is its own test.
- The file's own header states the cap, the form and the lifecycle; the check's failure output points at that header rather than restating the rules, so there is one home for them.
- Exit codes: 0 clean, 1 at least one defect found, 2 the file is missing or unreadable (a missing file is a broken invocation, never a silent pass).
