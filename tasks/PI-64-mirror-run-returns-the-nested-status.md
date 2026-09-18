# PI-64 — `mirror_run` must return the nested run's status, not `rm -rf`'s

**Status**: Blocked
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: XS
**Budget**: 60
**Risk**: low
**Depends on**: PI-48
**Wave**: 1
**Files**: bin/doctor.test.sh
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**:
**PR**:

## Goal
`mirror_run` (bin/doctor.test.sh ~1541) ends with an `rm -rf` of its throwaway mirror, so the function
returns *that* command's status and not the nested suite's. Every caller that chains on it with `&&`
therefore chains on a cleanup that practically never fails.

The damage: **a control that reports success about a case that never ran.** The AC4 blocks around lines
1618 and 1633 write their completion marker with
`( … && mirror_run "$S/ac4.mut.sh" >/dev/null 2>&1 && : > "$S/ac4.completed" ) &` — the marker is written
whether or not the nested run reached its end, which is exactly the discrimination the marker exists to
make. Found in the review of PI-63 (PR #108) and judged non-blocking there because the interrupted vs
completed discrimination that AC4 needs still held by another route, and a stale fixture is caught loudly
in the same run by the recursion loop's anchor check. It is still a control that can be green without
having looked.

## Acceptance criteria
- [ ] AC1 — Given `mirror_run`, when the nested suite exits non-zero, then `mirror_run` returns that
      status; when it exits zero, `mirror_run` returns zero — and the throwaway mirror is removed in
      **both** cases, as it is today. Losing the cleanup to gain the status is not an acceptable trade.
- [ ] AC2 — Given a deliberately bogus nested case that cannot complete, when the AC4 control runs against
      it, then the control turns **red with exactly one FAIL**. Execute this, do not reason about it: the
      review of PI-63 measured exactly this probe and it is the evidence this task exists to lock in.
- [ ] AC3 — Given the whole of `bin/doctor.test.sh`, when it is searched for every other caller that
      chains on `mirror_run` with `&&`, `||` or `if`, then each one is listed in the report with a line
      saying whether its meaning changes once the real status comes back, and any that silently depended
      on the old always-zero behaviour is fixed. Derive the list by searching, not by memory: the two AC4
      blocks are the known callers, not the declared boundary of the class.
- [ ] AC4 — Given `bash bin/doctor.test.sh`, when it runs, then it is green and the `ok` count is not lower
      than the 219 measured on the merge commit of PI-63.

## Tests expected
The change is inside the test file; AC2 and AC3 are the evidence. Integration/E2E: not needed.

## Notes
Blocked on PI-48, which restructures the self-mutation gate in this same file: starting both at once puts
two branches on the same lines. Do not anticipate PI-48's shape — read what actually landed.
