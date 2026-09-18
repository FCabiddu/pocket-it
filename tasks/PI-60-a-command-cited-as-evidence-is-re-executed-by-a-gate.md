# PI-60 — A command cited as evidence in a report is re-executed by a gate, not trusted

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
**Files**: bin/report-evidence-check.sh (new), bin/report-evidence-check.test.sh (new), bin/verify.sh
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**: 
**PR**: 

## Goal
Three rules already in force say the same thing in three places: a measurement is **pasted** into the report; a claim a command could settle is run before it is written down; no assertion the diff contradicts. One PR violated all three, in three different ways, and every one of them was caught by a human reading the report afterwards — or not caught at all. A fourth copy of the rule in a fourth prose file is not the fix; the rule is read and then not applied, which means the missing half is mechanical.

Build the gate. A report that cites a command as evidence has that command re-executed, and the report is red when the output does not match what it claims.

## Acceptance criteria
- [ ] AC1 — Given a fenced block in a committed report containing lines of the shape `<command> → <number|path>`, when the check runs, then it parses them out. The exact shape is the developer's to fix from what reports actually contain today — read a handful first and say in the report which shape was chosen and how many existing lines it matches; a parser that matches nothing is not a gate.
- [ ] AC2 — Given a cited command containing `…` or `...` in place of a path or an argument, when the check runs, then it is **rejected without being run**: an abbreviated command is not evidence, whatever it would have returned. Measured on one PR: 2 of 5 evidence lines were abbreviated this way and nobody noticed until a retrospective re-ran them a day later.
- [ ] AC3 — Given a cited command whose executable is not on a read-only allowlist (`grep`, `rg`, `git grep`, `find`, `wc`, `ls`, `cut`, `sort`, `uniq`), when the check runs, then it is **not executed** and is reported as unverifiable rather than run anyway. The gate must never become a way to run arbitrary text from a committed file; state in the report how the allowlist is enforced against shell metacharacters, pipes and command substitution, and show the case that proves it.
- [ ] AC4 — Given an allowlisted, non-abbreviated command, when the check re-runs it, then the check is **red** if the output disagrees with the cited value and green if it agrees. Measured target: on `docs/reports/QF-30-2026-09-18.md` as originally merged, this gate goes red on 3 of 5 lines — one of them a `grep -rln 'a|b'` cited as returning 1 file, which without `-E` returns 0.
- [ ] AC5 — Given a report with no evidence lines at all, when the check runs, then it exits 0 silently. This gate must not become noise that gets switched off, which is how the three prose rules it replaces failed.
- [ ] AC6 — Given a command that is slow or hangs, when the check runs it, then it is bounded by a timeout and the timeout is reported as unverifiable, not as green. A gate that can hang a verify run gets removed.
- [ ] AC7 (mutation) — Given the gate wired into `bin/verify.sh`, when a fixture report's cited number is changed to a wrong one, then `verify.sh` goes red; when it is restored, green. Run it, paste both outputs.

## Tests expected
Unit tests in `bin/report-evidence-check.test.sh` following the conventions of the other `bin/*.test.sh` suites: the parse shape, the `…` rejection, a non-allowlisted executable, a metacharacter injection attempt, agreement, disagreement, the empty report, the timeout. Integration/E2E: not needed.

## Notes
- This task is the mechanical half of a class whose prose half is already written three times over. If the developer's analysis concludes the gate cannot be built usefully — the shapes in real reports are too irregular to parse without false reds — that is a legitimate outcome: say so with the sample of reports that shows it, and the fallback is `tasks/PI-61`-style widening of the **existing** line in `shared/implementing-common.md` §9, never a new rule beside it.
- AC3 is the part that decides whether this ships. Re-executing text from a committed file is a real hazard; design it as an allowlist with no shell involved (argv, not a string passed to `sh -c`) rather than as a blocklist of dangerous characters.
- pocket-it è pubblico: mechanism only, no consumer-project names, paths or anecdotes in code, tests, commits or PR text. The measured examples above stay in this task file and out of the shipped artefacts.
