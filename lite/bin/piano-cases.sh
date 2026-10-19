#!/usr/bin/env bash
# Test cases for piano.sh: `bash lite/bin/piano-cases.sh`. Exits with 1 if a case fails.
. "$(cd "$(dirname "$0")" && pwd)/piano.sh"
tmp=$(mktemp -d); fail=0
c() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (expected $2, got $3)"; fail=1; fi; }
esito() { [ -z "$(piano_controlla "$tmp/$1" x)" ] && echo pass || echo stop; }
mkdir -p "$tmp"/{indice,elenco,tabella}/tasks/x
printf '| Onda | Task | Cosa fa | Design |\n|---|---|---|---|\n| 1 | E2E-1 (e2e) | spec | `a.md` |\n' > "$tmp/indice/tasks/x/indice.md"
printf '## Onda 1\n\n- **E2E-1** (e2e) — spec — `a.md`\n' > "$tmp/elenco/tasks/x/INDEX.md"
printf '| Onda | Task | Cosa fa | Design |\n|---|---|---|---|\n| 1 | T1 (frontend) | x | `a.md` |\n| 1 | E2E-1 (e2e) | spec | `a.md` |\n' > "$tmp/tabella/tasks/x/INDEX.md"
c "plan in indice.md"             stop   "$(esito indice)"
c "INDEX.md as a list"            stop   "$(esito elenco)"
c "INDEX.md as a table"           pass   "$(esito tabella)"
c "rows read from the table"      "1 T1,1 E2E-1" "$(piano_righe < "$tmp/tabella/tasks/x/INDEX.md" | paste -sd, -)"
c "set -e does not exit if fine"  pass   "$(bash -c 'set -euo pipefail; . "$1"; e=$(piano_controlla "$2" x); [ -z "$e" ] && echo pass' _ "$(dirname "$0")/piano.sh" "$tmp/tabella")"
rm -rf "$tmp"
exit $fail
