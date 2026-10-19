#!/usr/bin/env bash
# Test cases for stop-worktree-procs.sh: `bash flow/bin/stop-worktree-procs-cases.sh`. Exits with 1 if a case fails.
S=$(cd "$(dirname "$0")" && pwd)/stop-worktree-procs.sh
tmp=$(cd "$(mktemp -d)" && pwd -P); fail=0
W=$tmp/repo/.claude/worktrees/task/foo; A=$tmp/repo/.claude/worktrees/task/foobar
mkdir -p "$W/sub" "$A"
(cd "$W" && exec sleep 600) & p1=$!
(cd "$W/sub" && exec sleep 600) & p2=$!
(cd "$A" && exec sleep 600) & p3=$!          # same prefix, another worktree: stays alive
(cd "$W" && trap '' TERM && exec sleep 600) & p4=$!   # ignores TERM: KILL needed
sleep 1
(cd "$W" && bash "$S" "$W") >/dev/null        # called from inside the worktree: does not stop itself
c() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (expected $2, got $3)"; fail=1; fi; }
st() { kill -0 "$1" 2>/dev/null && echo alive || echo stopped; }
c "process in the worktree"           stopped "$(st $p1)"
c "process in a subdirectory"         stopped "$(st $p2)"
c "worktree with the same prefix"     alive   "$(st $p3)"
c "process ignoring TERM"             stopped "$(st $p4)"
kill -9 $p1 $p2 $p3 $p4 2>/dev/null; wait 2>/dev/null; rm -rf "$tmp"
exit $fail
