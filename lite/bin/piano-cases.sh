#!/usr/bin/env bash
# Casi di prova di piano.sh: `bash lite/bin/piano-cases.sh`. Esce con 1 se un caso fallisce.
. "$(cd "$(dirname "$0")" && pwd)/piano.sh"
tmp=$(mktemp -d); fail=0
c() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (atteso $2, ottenuto $3)"; fail=1; fi; }
esito() { [ -z "$(piano_controlla "$tmp/$1" x)" ] && echo passa || echo fermo; }
mkdir -p "$tmp"/{indice,elenco,tabella}/tasks/x
printf '| Onda | Task | Cosa fa | Design |\n|---|---|---|---|\n| 1 | E2E-1 (e2e) | spec | `a.md` |\n' > "$tmp/indice/tasks/x/indice.md"
printf '## Onda 1\n\n- **E2E-1** (e2e) — spec — `a.md`\n' > "$tmp/elenco/tasks/x/INDEX.md"
printf '| Onda | Task | Cosa fa | Design |\n|---|---|---|---|\n| 1 | T1 (frontend) | x | `a.md` |\n| 1 | E2E-1 (e2e) | spec | `a.md` |\n' > "$tmp/tabella/tasks/x/INDEX.md"
c "piano in indice.md"            fermo  "$(esito indice)"
c "INDEX.md a elenco"             fermo  "$(esito elenco)"
c "INDEX.md a tabella"            passa  "$(esito tabella)"
c "righe lette dalla tabella"     "1 T1,1 E2E-1" "$(piano_righe < "$tmp/tabella/tasks/x/INDEX.md" | paste -sd, -)"
c "set -e non esce se va bene"    passa  "$(bash -c 'set -euo pipefail; . "$1"; e=$(piano_controlla "$2" x); [ -z "$e" ] && echo passa' _ "$(dirname "$0")/piano.sh" "$tmp/tabella")"
rm -rf "$tmp"
exit $fail
