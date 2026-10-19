#!/usr/bin/env bash
# Casi di prova di stop-worktree-procs.sh: `bash lite/bin/stop-worktree-procs-cases.sh`. Esce con 1 se un caso fallisce.
S=$(cd "$(dirname "$0")" && pwd)/stop-worktree-procs.sh
tmp=$(cd "$(mktemp -d)" && pwd -P); fail=0
W=$tmp/repo/.claude/worktrees/task/foo; A=$tmp/repo/.claude/worktrees/task/foobar
mkdir -p "$W/sub" "$A"
(cd "$W" && exec sleep 600) & p1=$!
(cd "$W/sub" && exec sleep 600) & p2=$!
(cd "$A" && exec sleep 600) & p3=$!          # stesso prefisso, altro worktree: resta vivo
(cd "$W" && trap '' TERM && exec sleep 600) & p4=$!   # ignora TERM: serve il KILL
sleep 1
(cd "$W" && bash "$S" "$W") >/dev/null        # chiamato da dentro il worktree: non ferma sé stesso
c() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (atteso $2, ottenuto $3)"; fail=1; fi; }
st() { kill -0 "$1" 2>/dev/null && echo vivo || echo fermo; }
c "processo nel worktree"             fermo "$(st $p1)"
c "processo in una sottocartella"     fermo "$(st $p2)"
c "worktree con lo stesso prefisso"   vivo  "$(st $p3)"
c "processo che ignora TERM"          fermo "$(st $p4)"
kill -9 $p1 $p2 $p3 $p4 2>/dev/null; wait 2>/dev/null; rm -rf "$tmp"
exit $fail
