#!/usr/bin/env bash
# Test cases for plan.sh: `bash lite/bin/plan-cases.sh`. Exits with 1 if a case fails.
. "$(cd "$(dirname "$0")" && pwd)/plan.sh"
tmp=$(mktemp -d); fail=0
c() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (expected $2, got $3)"; fail=1; fi; }
esito() { [ -z "$(plan_check "$tmp/$1" x)" ] && echo pass || echo stop; }
mkdir -p "$tmp"/{indice,elenco,tabella}/tasks/x
printf '| Wave | Task | What it does | Design |\n|---|---|---|---|\n| 1 | E2E-1 (e2e) | spec | `a.md` |\n' > "$tmp/indice/tasks/x/indice.md"
printf '## Onda 1\n\n- **E2E-1** (e2e) — spec — `a.md`\n' > "$tmp/elenco/tasks/x/INDEX.md"
printf '| Wave | Task | What it does | Design |\n|---|---|---|---|\n| 1 | T1 (frontend) | x | `a.md` |\n| 1 | E2E-1 (e2e) | spec | `a.md` |\n' > "$tmp/tabella/tasks/x/INDEX.md"
c "plan in indice.md"             stop   "$(esito indice)"
c "INDEX.md as a list"            stop   "$(esito elenco)"
c "INDEX.md as a table"           pass   "$(esito tabella)"
c "rows read from the table"      "1 T1,1 E2E-1" "$(plan_rows < "$tmp/tabella/tasks/x/INDEX.md" | paste -sd, -)"
c "set -e does not exit if fine"  pass   "$(bash -c 'set -euo pipefail; . "$1"; e=$(plan_check "$2" x); [ -z "$e" ] && echo pass' _ "$(dirname "$0")/plan.sh" "$tmp/tabella")"
rm -rf "$tmp"
exit $fail
