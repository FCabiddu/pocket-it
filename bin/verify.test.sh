#!/usr/bin/env bash
# Self-test for verify.sh — PI-11: the "test files in diff" check must recognise *.test.sh (this repo's own
# test convention, e.g. bin/*.test.sh and .claude/hooks/*.test.sh) alongside the already-supported
# JS/TS/Python/Go patterns, without widening the match to any *.sh file, and without changing the count or
# behaviour for the languages already covered.
cd "$(dirname "$0")"
SCRIPT="$PWD/verify.sh"
S=$(mktemp -d "${TMPDIR:-/tmp}/verify-test.XXXXXX")
S=$(cd "$S" && pwd -P)   # resolve any symlink (e.g. macOS /tmp) so it matches git's resolved toplevel
UNIQ=$(basename "$S")   # per-run id, also used by verify.sh to name its own worktree (basename of $ROOT)
# verify.sh drops its throwaway worktrees under a shared /tmp/pocket-it-verify — only remove the ones this
# run created ($UNIQ-prefixed), never the whole shared directory, so a parallel run isn't wiped out.
cleanup(){ rm -rf "$S" "/tmp/pocket-it-verify/${UNIQ}-"* 2>/dev/null; }
trap cleanup EXIT
fail=0
ok(){ if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
q(){ "$@" >/dev/null 2>&1; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null

q git init -q --bare "$S/origin.git"
q git init -q -b main "$S/$UNIQ"; M="$S/$UNIQ"
echo base > "$M/README.md"; q git -C "$M" add README.md; q git -C "$M" commit -qm base
q git -C "$M" remote add origin "$S/origin.git"; q git -C "$M" push -q -u origin main

# mkbranch <name> <file>... — a branch off main that adds one commit touching the given files
mkbranch(){
  local name="$1"; shift
  q git -C "$M" checkout -q -b "$name" main
  local f
  for f in "$@"; do mkdir -p "$M/$(dirname "$f")"; echo content > "$M/$f"; q git -C "$M" add "$f"; done
  q git -C "$M" commit -qm "$name"
  q git -C "$M" push -q -u origin "$name"
  q git -C "$M" checkout -q main
}

# AC1 — a diff with a *.test.sh file is reported as a test file, with the right count
mkbranch ac1-shell-test "bin/newthing.test.sh"
OUT1=$(cd "$M" && bash "$SCRIPT" ac1-shell-test main 2>&1)
ok "AC1 — reports the *.test.sh file as a test, count 1" "echo \"\$OUT1\" | grep -qE '^info  test files in diff: 1\$'"
ok "AC1 — no longer falsely warns of an empty diff" "! echo \"\$OUT1\" | grep -q 'warn  no test files in the diff'"

# AC2 — a diff with only a non-test *.sh file: the warning still fires, unchanged
mkbranch ac2-shell-nontest "bin/plainscript.sh"
OUT2=$(cd "$M" && bash "$SCRIPT" ac2-shell-nontest main 2>&1)
ok "AC2 — still warns when the diff has no test files" "echo \"\$OUT2\" | grep -q 'warn  no test files in the diff'"
ok "AC2 — a plain .sh is not misreported as a test file" "! echo \"\$OUT2\" | grep -q 'info  test files in diff'"

# AC3 — a diff with test files in the already-recognised languages: count and behaviour unchanged
mkbranch ac3-other-langs "src/foo.test.ts" "pkg/bar_test.go"
OUT3=$(cd "$M" && bash "$SCRIPT" ac3-other-langs main 2>&1)
ok "AC3 — still reports 2 test files for a JS/TS + Go diff" "echo \"\$OUT3\" | grep -qE '^info  test files in diff: 2\$'"

# mixed — a shell test alongside an already-recognised-language test: both counted together
mkbranch ac1-mixed "bin/other.test.sh" "src/foo.spec.tsx"
OUT4=$(cd "$M" && bash "$SCRIPT" ac1-mixed main 2>&1)
ok "mixed — shell test and JS/TS test are both counted" "echo \"\$OUT4\" | grep -qE '^info  test files in diff: 2\$'"

[[ $fail -eq 0 ]] && echo "verify.test.sh: ALL PASS" || echo "verify.test.sh: FAILURES"
exit $fail
