# PI-42 — doctor must check the TAD sections the board actually cites, not a hardcoded list

**Status**: Needs Work
**Label**: DevOps
**Epic**: quickfix
**Story**: quickfix
**Priority**: Must
**Estimate**: S
**Budget**: 120
**Risk**: low
**Depends on**: none
**Wave**: 1
**Files**: bin/doctor.sh, bin/doctor.test.sh
**TAD**: none — follow existing conventions
**Contract**: none
**Branch**:
**PR**:

## Goal
`bin/doctor.sh` §4b warns `{tad}: subsections referenced by agents missing: [...]` against a set of
subsection numbers **hardcoded in the script** (`expected = {"5.2","6.2","7.6","8.1","9.3","11.1"}`).
Nothing is actually looked up: the message says "referenced by agents" and no reference is read.

Two consequences, both observed on a real board:
- A valid TAD whose numbering simply differs warns on every run, and **no edit to the board can ever
  clear it** — the only way out is to renumber a finished document to match a list in another repo.
- The warning fires for subsections the tasks never cite, while the sections they **do** cite live in
  a feature delta (`{NAME}_TECH_DELTA.md`) that §4b does not even open — a task line reading
  `**TAD**: DELTA §11.1` is resolved against the project TAD, where 11.1 was never meant to be.

A permanent warning that cannot be cleared is worse than no warning: `doctor.sh` gates every launch,
and a board whose baseline is "8 warnings, ignore them" cannot surface the ninth.

## Acceptance criteria
- [ ] AC1 — Given a board whose task files cite TAD sections, when `doctor.sh` runs, then the sections
      it checks are exactly the ones the board cites — read from the task files — and the hardcoded
      `expected` set is gone. No task citing a section ⇒ nothing to warn about.
- [ ] AC2 — Given a citation that names which document it belongs to (the project TAD or a feature
      delta), when `doctor.sh` resolves it, then it resolves against **that** document. Cover the whole
      class of qualifiers the boards actually use, not the two spellings this task happens to name:
      derive them from the task files, and say in the report which forms you found.
- [ ] AC3 — Given a citation that resolves to a heading that does not exist in the document it names,
      when `doctor.sh` runs, then it warns once, naming the citing task, the document and the section —
      so the warning says who to fix, not only that something is missing.
- [ ] AC4 — Given a TAD with a numbering scheme different from any other project's, when no task cites
      a missing section, then `doctor.sh` is silent about subsections. A document is not required to
      contain a section merely because some other project has one.
- [ ] AC5 — Given the rest of §4b (top-level sections out of order is an `err`), when this change lands,
      then that check is untouched and still errors on an out-of-order document.
- [ ] AC6 — Given a citation naming a document that does not exist at all, when `doctor.sh` runs, then
      it warns about the missing document rather than silently skipping the citation.

## Tests expected
One test per criterion in `bin/doctor.test.sh`, each on a disposable project tree the test builds:
a TAD with unusual numbering and no citations (must be silent), a task citing a section that exists in
a delta (silent), one citing a section missing from the document it names (one warning, naming the task),
one citing an absent document. Prove it by mutation: restore the hardcoded set and AC4 must go red.

## Notes
Damage to prevent, stated as damage: **`doctor.sh` must never print a warning that the board it is
checking has no way to clear.** Every warning names something a person or an agent can go and fix.

The false positive was found on a real board where the check's own message was the misleading part —
it claimed a reference that it had never read. When you rewrite the message, make it quote the citation
it actually found.

Same family as PI-40 and PI-41: a check asserting something about an artefact without going to look.
