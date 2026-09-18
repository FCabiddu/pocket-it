#!/usr/bin/env bash
# Shared gate for every self-mutating block in this repo's bin/*.test.sh files. Built by PI-45 inside
# bin/doctor.test.sh; moved here by PI-48 so bin/cleanup-merged.test.sh's own self-mutation blocks (four of
# them, not the two an earlier review happened to read) use it instead of a second copy that can drift —
# a copy that happens to be correct today is the defect one layer up, per PI-48's own task. Source this
# file after `SCRIPT_SRC` is set (the caller's frozen, once-captured copy of the live script's content —
# see below); it defines functions and MUT_WHY, nothing else, and runs nothing on its own.
#
# Threat model. A self-mutation block builds a patched copy of a live script by matching its source text —
# a single-line substitution (`s/OLD/NEW/`) or a `/A/,/B/c\...`/`/A/,/B/d` range address — runs that copy,
# and asserts on what it printed (or, for a delete, on what is now absent). The text it matches can be
# gone, edited in place or doubled — most often because the live script was modified outside this run,
# which is exactly what a reviewer does to prove the self-test is not vacuous. When that happens the
# patched copy must never reach the downstream assertion: that assertion would then report a real-looking
# regression against a check that never ran — a test failure naming the wrong test, which is the damage
# this gate exists to close. Covered here: the mutation did not apply, applied to a different span than
# its address assumes, or produced a fragment instead of a script. Deliberately left to the assertions
# themselves: a mutation that lands exactly where it was aimed but whose intent has gone stale. Left to the
# live script's own checks: any defect in the script being tested.
#
# The rule, and why "the marker is in the output" is not it. `sed '/A/,/B/c\...'` (or `d`) whose B no
# longer matches does not fail: the range opens at A, never closes, and runs to end of file — sed applies
# the range's effect and drops every line after A. Measured on bin/doctor.sh's own _classify_base block
# (PI-45), with one trailing comment appended to the closing anchor and nothing else touched: 446 lines in,
# 74 out, the marker present in all of it, and `bash -n` on that fragment still exiting 0. A doubled
# opening anchor does the same thing one range later; a doubled closing anchor closes the range early, over
# a span the block never meant. So no block may conclude "applied" from its own output alone. Every block
# declares the anchor(s) its address uses, they are counted in the SOURCE before sed runs (src_anchors),
# the address is then built from those same strings (sed_lit, so the line counted and the line matched
# cannot drift apart), and what came out is checked to still be a whole script (mutant_whole). Both layers,
# at every site: the count catches the doubled anchor that produces a perfectly whole file over the wrong
# span, and mutant_whole catches the runaway of a future block whose author forgets to declare an anchor
# at all.
#
# One measured limit, so it is not rediscovered as a surprise: mutant_whole below proves the mutant is
# still a whole, parseable script with an intact tail (and, when the pristine source carries a python
# heredoc, with that heredoc still closed and its body still compiling) — it says nothing about whether
# that script still
# RUNS. A mutation that deletes a function definition the script still calls elsewhere is a whole,
# syntactically valid file that fails only at run time (a NameError / "command not found", surfaced by
# whatever the block's own downstream assertion does with the mutant's output) — this gate does not claim
# to catch that class, on either side of PI-45/PI-48's sites.
MUT_WHY=""   # why the last gate refused -- quoted verbatim in that block's own named failure
MUT_LEDGER="${MUT_LEDGER:-}"   # optional: a file this gate appends the path of every APPROVED patched copy
  # to, one per line, as it approves it. Unset (the default, and what bin/doctor.test.sh uses) the gate
  # records nothing and behaves exactly as before. Set, the ledger becomes a RUNTIME record of what the
  # gate let through -- a source independent of any pattern a test could grep for itself, which is what
  # bin/cleanup-merged.test.sh's census compares against the patched copies actually found on disk, and
  # what its run_mutant() consults before executing one. A ledger is written, never read, by this file.
mut_record(){ [[ -n "$MUT_LEDGER" ]] && printf '%s\n' "$1" >> "$MUT_LEDGER"; return 0; }
sed_lit(){ # sed_lit <literal> -- BRE-escape <literal> so /^<it>$/ (or /<it>/) matches exactly that text
  # and nothing else. Used to build a sed address from the same string src_anchors counted, so the line
  # counted and the line matched cannot drift apart.
  printf '%s' "$1" | sed 's|[][\.*^$/]|\\&|g'
}
sed_rhs(){ # sed_rhs <literal> -- escape <literal> for the REPLACEMENT side of `s/.../<it>/`, where `&`
  # means "the whole match", `\` starts an escape and `/` closes the substitution. The pair with sed_lit:
  # a block that builds both sides of its substitution from the same declared strings cannot have its
  # replacement silently rewritten by a character it never meant as syntax (a replacement carrying `&`
  # would otherwise re-inject the matched text and the mutation would land as something else).
  printf '%s' "$1" | sed -e 's|[\\/&]|\\&|g' -e 's|$|\\|' -e '$s|\\$||'
}
src_anchors(){ # src_anchors <file> <line|substr|occur> <count> <anchor>... -- 0 iff every <anchor> is
  # found exactly <count> times in <file>, counted in the UNIT sed will use for the address (or the LHS
  # of a plain `s/.../.../`) built from that same string:
  #   line   /^...$/ -- whole lines (grep -x), so a comment appended to that line does NOT count: the
  #          substring match a plain grep -F would accept is what lets a range run away, or lets a
  #          single-line substitution silently target the wrong line.
  #   substr /.../   -- LINES containing it, the unit a range address works in: a second occurrence on
  #          the same line does not open a second range, so it must not count as a second anchor.
  #   occur  s/.../.../ -- OCCURRENCES, anywhere, the unit a plain substitution works in: sed patches the
  #          first match of EVERY matching line, so two occurrences mean the address no longer identifies
  #          one span, whether they sit on two lines (both get patched) or on one (only the first does,
  #          which may not be the one the block meant). Added by PI-48 after executing the doubled-anchor
  #          case against a real substitution site: `substr` counts lines and reported a same-line
  #          doubling as one, which is right for the range it models and wrong for a substitution.
  # A range address declares BOTH of its anchors here, or the gate is only guessing which lines the range
  # will actually span; a single-anchor substitution declares its one anchor, so a doubled occurrence is
  # caught the same way a lost one is.
  local f="$1" mode="$2" want="$3"; shift 3
  local a n
  for a in "$@"; do
    case "$mode" in
      line)  n=$(grep -cxF -- "$a" "$f");;
      occur) n=$(grep -oF -- "$a" "$f" | grep -c '');;
      *)     n=$(grep -cF -- "$a" "$f");;
    esac
    if [[ "$n" != "$want" ]]; then
      MUT_WHY="anchor found $n times, not $want, in the captured source: ${a:0:60}"
      return 1
    fi
  done
  MUT_WHY=""
}
TAIL_LINES=3   # how many trailing lines mutant_whole compares -- see its own comment below
mutant_whole(){ # mutant_whole <file> [pristine, default $SCRIPT_SRC] -- <file> is still a whole script
  # and not a fragment: it parses as bash (`bash -n`), and its own tail -- the last $TAIL_LINES lines, the
  # ones a runaway range never reaches, wherever in the file it happens to open -- is byte-identical to
  # the pristine source's tail. Shape-agnostic on purpose, unlike the check it replaces: doctor.sh's
  # original mutant_whole re-parsed the python heredoc doctor.sh always carries (re-opening it, checking
  # its own delimiter closes it, then `compile()`-ing what is inside), which proves the same thing for a
  # script whose whole tail lives inside one heredoc but refuses EVERY mutant -- valid ones included --
  # for a script that has no such heredoc at all, such as cleanup-merged.sh (pure bash, zero `python3`, zero
  # `<<` heredocs of any kind: grep confirms it). A `c\`/`d` range that never finds its closing anchor
  # applies its effect once and runs to EOF, so whatever sits at the true end of the pristine source is
  # gone from the mutant; a single-line `s/.../.../` substitution never touches any line but the one it
  # matches, so the tail cannot move at all. Anchor-independent on purpose, exactly like the check it
  # replaces: being whole is the property a runaway range destroys whatever anchors it used, and it also
  # covers an address whose anchors nobody declared.
  #
  # Nothing the landed check did is dropped. doctor.sh's original layer -- re-open the python heredoc the
  # script carries, require its own delimiter to close it, `compile()` what is inside -- is kept below,
  # word for word, and merely made conditional on the PRISTINE source opening such a heredoc in the first
  # place: for bin/doctor.sh that condition holds and the layer runs exactly as it did before this file
  # existed (so a mutation that breaks the python INSIDE the heredoc, which leaves the tail and `bash -n`
  # perfectly happy, is still refused); for a script that has no python heredoc at all it is skipped
  # instead of refusing every mutant, valid ones included, on the grounds that a heredoc it never had is
  # missing. The tail comparison is the layer this file ADDS, and it is the one that holds for both.
  local f="$1" src="${2:-$SCRIPT_SRC}" want got why
  if ! bash -n "$f" 2>/dev/null; then MUT_WHY="the patched copy no longer parses as bash"; return 1; fi
  want=$(tail -n "$TAIL_LINES" "$src")
  got=$(tail -n "$TAIL_LINES" "$f")
  if [[ "$got" != "$want" ]]; then
    MUT_WHY="the patched copy is a fragment: its last $TAIL_LINES line(s) no longer match the pristine source -- a runaway range applied its effect and dropped (or replaced) everything physically after it"
    return 1
  fi
  if grep -qE "^python3 .*<<'[A-Za-z_][A-Za-z0-9_]*'[[:space:]]*\$" "$src"; then
    why=$(python3 - "$f" <<'MWEOF'
import re, sys
lines = open(sys.argv[1], errors="ignore").read().splitlines(True)
start = delim = None
for i, line in enumerate(lines):
    m = re.match(r"^python3 .*<<'([A-Za-z_][A-Za-z0-9_]*)'\s*$", line)
    if m:
        start, delim = i + 1, m.group(1); break
if start is None:
    print("the patched copy no longer opens a python heredoc at all"); sys.exit(1)
end = None
for j in range(start, len(lines)):
    if lines[j].rstrip("\n") == delim:
        end = j; break
if end is None:
    print("the patched copy is a fragment: its python heredoc is never closed by %s" % delim); sys.exit(1)
try:
    compile("".join(lines[start:end]), "<mutant>", "exec")
except SyntaxError as e:
    print("the patched copy's python no longer compiles: line %s: %s" % (e.lineno, e.msg)); sys.exit(1)
MWEOF
    ) || { MUT_WHY="$why"; return 1; }
  fi
  MUT_WHY=""
  mut_record "$f"
}
mutation_applied(){ # mutation_applied <mutant> <marker> [pristine, default $SCRIPT_SRC] -- the only way a
  # block below may conclude the mutation applied: the marker landed AND what carries it is still a whole
  # script. Not for a delete-shaped mutation, whose "applied" is a marker's ABSENCE -- those call
  # mutant_whole directly, then check the marker is gone.
  if ! grep -qF -- "$2" "$1"; then MUT_WHY="the mutation marker never landed in the patched copy"; return 1; fi
  mutant_whole "$1" "$3"
}
