# PI-44 — cleanup-merged.sh sotto-conta i "kept" e dichiara una causa che non ha accertato

**Status**: Done
**Label**: DevOps
**Epic**: pipeline-improvements
**Story**: pipeline-improvements
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/cleanup-merged.sh, bin/cleanup-merged.test.sh
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**: task/pi-44-cleanup-kept-count-and-cause
**PR**: https://github.com/FCabiddu/pocket-it/pull/84

## Goal
Two defects observed together on a real sweep of 228 remote branches.

**(a) The summary line under-reports.** Only `keep()` increments `kept`. The two other places
that print a `kept …` line — the local-branch delete failure and the remote-branch delete
failure — print the line and never touch the counter. Measured: one run printed 2 `kept` lines
and summarised `1 kept`; the next printed 3 and summarised `1 kept`. The summary is the single
line the orchestrator reports to the operator, so branches survive a sweep that is reported as
complete.

**(b) The failure message states a cause the script never determined.** The remote branch is
taken from `refs/remotes/origin`, the local remote-tracking cache. When that cache is stale the
ref is already gone from the remote, `git push --delete` fails, and the script prints
`delete failed: no permission or network` — a diagnosis it did not make. Verified: all five
branches reported that way were already absent from the remote; there was no permission problem
and no network problem. An operator reading that line goes hunting for a fault that does not
exist.

The damage to prevent: the summary must never report fewer kept branches than were kept, and no
message may assert a cause the script has not established.

## Acceptance criteria
- [ ] AC1 — Given any execution path that prints a line announcing a branch or worktree was kept,
      when the summary is printed, then the summary's count equals the number of such lines. This
      holds for every kept-path in the script, present and future — the invariant is the equality,
      not the three call sites that exist today.
- [ ] AC2 — Given a delete that fails, when the script reports it, then the message either names
      the cause it actually observed (the remote's own error) or says the cause is unknown; it
      never names a cause it did not establish.
- [ ] AC3 — Given a branch that is already absent from the remote, when the script processes it,
      then the outcome distinguishes "already gone" from "could not be deleted" — an already-gone
      branch is not a kept branch and does not inflate the kept count.
- [ ] AC4 — Given `--dry-run`, when it runs, then its summary obeys AC1 with the same equality.
- [ ] AC5 — Given a real permission or network failure, when it happens, then the script still
      reports it as a failure and still exits with its current exit-code behaviour — the fix for
      (b) must not turn genuine failures into silence.
- [ ] AC6 — The stale comment block above `reap_remote_branches()` (flagged as non-blocking by the
      PI-38 review) describes what the function now does.

## Tests expected
One case per criterion in `bin/cleanup-merged.test.sh`, each asserting on the script's own stdout —
for AC1, by counting the printed kept lines and parsing the summary, so a fourth kept-path added
later is covered without editing the test. Plus a mutation: reintroducing the un-incremented
counter must turn the suite red. Integration/E2E: not needed.

## Notes
The invariant, not a list of addresses: **every path that leaves a branch or a worktree in place
goes through `keep()`** — the one function that both announces it and counts it. A path that keeps
something while printing its own message, or while printing nothing at all, is the defect,
wherever it lives. Silence is a form of it: the PI-44 review found a fifth site
(`bin/cleanup-merged.sh`, the "prunable" branch of the main loop, worktree directory missing from
disk) that keeps a branch without printing anything, which the first fix never reached because the
Notes here enumerated four call sites instead of stating this rule.

Starting points only, not the boundary of the work: counter declared line ~218, `keep()` ~219,
local-branch failure ~223, remote-branch failure ~262 (inside `reap_remote_branches`, whose source
list is `g for-each-ref … refs/remotes/origin`), `locked_entry()`, the prunable branch of the main
loop, summary ~337-338.
