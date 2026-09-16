# QF-1 — A cause found inside an approval must raise a signal too

**Status**: Todo
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: high
**Depends on**: none
**Wave**: 1
**Files**: bin/retro-due.sh, bin/retro-due.test.sh, .claude/agents/reviewer.md
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**:
**PR**:

## Goal
`reviewer.md:21` orders the cause taxonomy to be named **"on every NEEDS WORK"**, and `bin/retro-due.sh`
counts a signal only from a "needs work" log line whose cause is present and is not `first-round`. Between
them, a defect found and reported inside an **approval** carries no cause field anywhere and raises nothing.

This is not hypothetical. On 2026-09-17 the PI-44 delta review approved PR #84 and, in the same report,
established that the developer's completeness evidence — a classification of all 43 `continue`/`return`
sites in `bin/cleanup-merged.sh` — contained a false row. The behaviour was correct; the claim about it was
not. That is a pipeline defect of a kind the taxonomy has no word for, it was non-blocking, and it reached a
retrospective **only because the orchestrator carried it by hand**. `retro-due.sh` said `nothing` before and
after. The pipeline's memory depends on a human relay for exactly the findings that do not block a merge.

Add `false-coverage-evidence` to the taxonomy — a coverage argument offered as proof of completeness
containing a row that was never established — and, more importantly, close the structural gap that made a
cause invisible because it arrived attached to a good outcome.

## Acceptance criteria
- [ ] AC1 — Given a review that approves a PR and names a cause, when the reviewer writes its report and its
      log line, then the cause is carried in both, in a shape `bin/retro-due.sh` recognises. The outcome word
      and the cause must be independent: no shape may require an approval to be re-spelled as a rework, and
      no shape may make a cause readable only when the outcome is "needs work".
- [ ] AC2 — Given `bin/retro-due.sh`, when it reads the handoff log and archive, then a cause on an approval
      raises a signal on the same terms a cause on a rework does — present, and not `first-round`.
- [ ] AC3 — Given the anchoring history of this script, when the new recogniser is written, then it is
      anchored on the cause being the line's own cause field and never on a substring appearing somewhere in
      the line. `bin/retro-due.sh:20-24` and `:61-67` record three prior rounds of exactly this defect: a
      skill's own PR-closing line counted as a second round; "no em-dash before needs work" still matching a
      verb elsewhere in the line; "needs work (delta)" with no number missed entirely. Show the mutation for
      each of those three historical shapes against your new recogniser, executed, and state whether each is
      still correctly classified. A recogniser that passes the suite but reopens one of them is the defect.
- [ ] AC4 — Given a log line that mentions a cause word inside prose — a PR title, a fact, a description of
      a cause that was closed — when `retro-due.sh` reads it, then no signal is raised. The frozen-source
      rule the script already relies on must keep holding; do not weaken an anchor to make a new one fit.
- [ ] AC5 — Given `reviewer.md`, when an approval carries no cause because there is nothing to name, then
      nothing changes for it: naming a cause must not become a field the reviewer has to fill with something.
      An empty cause and an absent cause must not be the same value as `first-round`.
- [ ] AC6 — Given `bin/retro-due.test.sh`, when it runs, then it is green and asserts the new class by
      construction rather than by the four example lines this task happens to quote; the `ok` count is not
      lower than before.

## Tests expected
Assertions in `bin/retro-due.test.sh` for AC2, AC3, AC4 and AC5. AC1's reviewer-side wording is prose and
needs no test, but the log shape it prescribes must be one the AC2 assertions actually exercise — a rule in
`reviewer.md` describing a shape the script does not recognise is the same gap in a new place.
Integration/E2E: not needed.

## Notes
Starting points only, not the boundary of the work: `bin/retro-due.sh:7-10` lists what counts as a signal;
`:71` carries the needs-work anchor regex; `.claude/agents/reviewer.md:21` is the taxonomy paragraph, and
its Step 6 report line is where a cause reaches the orchestrator.

The rule behind the whole task: **a cause is a property of the finding, not of the verdict.** The pipeline
learns from causes; tying their visibility to a bad outcome means it only learns from failures loud enough
to block a merge, and the quiet ones — which are the ones a human is least likely to relay — are lost by
construction.

`Risk: high` because this script is the trigger for the pipeline's whole learning loop: a recogniser that
over-fires launches retrospectives on noise, and one that under-fires silently disarms the loop, which is
how PI-43 was found. Both directions cost, and the second is invisible.

Out of scope: `bin/retro-due.sh`'s section-splitting defect (PI-43 — it reads the wrong section on a file
that quotes the `## Log` marker inside a fact). Do not fix it here and do not build on its current splitting
behaviour more than the existing code already does; PI-43 is blocked on PI-16 and will reuse a shared home.
