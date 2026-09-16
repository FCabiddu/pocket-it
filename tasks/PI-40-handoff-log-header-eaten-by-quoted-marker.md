# PI-40 — handoff.sh must find its own Log heading, not a `## Log` quoted inside a fact

**Status**: Done
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: high
**Depends on**: none
**Wave**: 1
**Files**: bin/handoff.sh, bin/handoff.test.sh
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**: task/pi-40-handoff-log-header-anchor
**PR**: https://github.com/FCabiddu/pocket-it/pull/81

## Goal
`bin/handoff.sh log` splits the handoff file with `head,sep,tail = s.partition("## Log")` — unanchored, so it
matches the string `## Log` **anywhere**, including inside a fact that quotes it. It then keeps only the lines of
`tail` that start with `- `, which silently **drops the real `## Log` heading** (it does not start with `- `) and
merges the whole log into the facts section. Every later run repeats it.

Observed on a real project: a fact contains the snippet `` `awk '/^## Log/{f=1;next} …` `` (a rule telling agents
how to check their own handoff file). From that moment the heading was deleted, 40 log lines lived inside
`## Fatti che non scadono`, and any fact standing *after* the quoted marker would be reclassified as a log line
and rotated into the archive. The facts cap then trims real facts to make room for progress lines.

Reproduced in a disposable repo (2026-09-16): heading present → one `handoff.sh log` → heading count 0, the new
line written directly under the last fact.

`fact` and `compose` read the same file through `section_body(...)`/their own splits — check whether they carry
the same unanchored assumption and fix them in the same shape if they do.

## Acceptance criteria
- [x] AC1 — Given a handoff file whose **facts** section contains the literal `## Log` anywhere inside a fact's
      text (backticked, inline, mid-sentence — the whole class, not the one observed spelling), when
      `handoff.sh log "…"` runs, then the real `## Log` heading is still present exactly once afterwards, the new
      line is under it, and no fact line moved section.
- [x] AC2 — Given the same file, when `log` runs N times in a row, then the file is byte-stable in structure:
      heading count stays 1, the fact count never decreases, and no fact ever reaches the archive.
- [x] AC3 — Given a handoff file with **no** `## Log` heading at all (a fresh or hand-edited file), when `log`
      runs, then a heading is created once, at the end, and existing dated lines are not re-parented — the
      current create-if-missing behaviour keeps working and is not regressed into by AC1's anchor.
- [x] AC4 — Given the archive file, when rotation happens under AC1's conditions, then only genuine log lines
      rotate; the invariant "no line is lost, order oldest-at-top" from PI-8 still holds.
- [x] AC5 — Given `fact` and `compose` on the same file, when they run, then they classify the two sections the
      same way `log` does (one definition of where the log starts, used by every reader and the writer — the
      same "one home for a term" rule PI-39 applied to the date anchor).

## Tests expected
One test per criterion in `bin/handoff.test.sh`, each on a disposable file built inside the test, including the
adversarial fixture: a fact that quotes `## Log`, plus a fact placed **after** it. Prove the fix by mutation —
revert the anchor and AC1 must go red. Integration/E2E: not needed.

## Notes
The defect is the same family as PI-39: a reader anchored loosely over free text that legitimately contains its
own marker. PI-39's answer was to normalise at the write and keep the reader's anchor strict; the answer here is
the same shape — anchor on a heading at the start of a line (`^## Log`), never a substring match.

Damage to prevent, stated as damage: **a section heading or a fact must never be deleted or reclassified by
writing a log line.** Not "match at line start" — that is one implementation of it.

Already repaired by hand on the affected project (heading restored, 42 facts / 40 log lines verified); this task
fixes the cause so the repair holds.
