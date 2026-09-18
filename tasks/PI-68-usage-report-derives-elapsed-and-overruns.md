# PI-68 — `usage-report.py` derives elapsed minutes and budget overruns, instead of waiting for the agent to declare them

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Should
**Estimate**: S
**Budget**: 45 min
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/usage-report.py, bin/usage-report.test.sh (new if absent)
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**:
**PR**:

## Goal
An overrun is currently known only if the agent that had it writes a `BUDGET` line about itself, and a retro
reading a silent window cannot tell "no overrun" from "nobody wrote it" without re-deriving the numbers by
hand — which is exactly what one retro had to do, with a throwaway script, to find that the thresholds were
above the 90th percentile of real runs. The transcripts already carry every number involved: each subagent
run has its own file, its `agentType` in the sibling `.meta.json`, a first and a last timestamp, and a
description that usually names the task id. The report should say it.

## Acceptance criteria
- [ ] AC1 — Given the transcripts of a project, when `usage-report.py` runs, then for each subagent run it can
      print elapsed minutes and seconds-per-call alongside the existing call and context columns. The elapsed
      figure is the span between the run's first and last record.
- [ ] AC2 — Given a run whose span contains an idle gap (a resumed agent, a suspended machine), when the span
      is printed, then the **largest gap between consecutive records** is printed with it and subtracted in a
      second "worked" figure, because a span with a 99-minute hole inside it is not evidence of an overrun and
      has twice been read as one. A gap above the stall threshold is flagged, never silently dropped.
- [ ] AC3 — Given a run whose description names a task id present under `tasks/`, when that task file carries
      a `**Budget**: N min`, then the report names the runs whose **worked** figure exceeds it, as a section of
      its own with the count. A unitless budget is reported as *not comparable* and never converted (shared
      rules §8).
- [ ] AC4 — Given a window with no `BUDGET` line in the handoff but runs over budget by AC3, when the report
      runs, then that discrepancy is stated in one line, since that is the signal a retro is looking for.
- [ ] AC5 — Given the new code, when its tests run, then fixtures cover: a run with no gap, a run with one
      large gap, a description with no task id, a task file with a unitless budget, and a task file with none.
      Mutation executed for each: break the derivation and show the case turns green without it.

## Tests expected
Script-level tests against fixture transcript directories built by the test itself. No network, no real
project transcripts checked in — fixtures are written by the test and removed by it.

## Notes
Keep the existing output shape stable: the new columns and the new section are additions, and nothing that
another script or agent already parses changes name or position.
