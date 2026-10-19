#!/usr/bin/env bash
# Casi di prova di rete.sh: `bash lite/bin/rete-cases.sh`. Esce con 1 se un caso fallisce.
. "$(cd "$(dirname "$0")" && pwd)/rete.sh"
export RETE_ATTESE="0 0 0"
tmp=$(mktemp -d); fail=0
c() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (atteso $2, ottenuto $3)"; fail=1; fi; }
# finto <errori prima di riuscire> <messaggio>: conta i lanci in $tmp/n, stampa «ok» quando riesce.
finto() {
  local n; n=$(( $(cat "$tmp/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$tmp/n"
  if [ "$n" -le "$1" ]; then echo "$2" >&2; return 4; fi
  echo ok
}
prova() { rm -f "$tmp/n"; out=$(rete finto "$@" 2>/dev/null); rc=$?; echo "$out/$rc/$(cat "$tmp/n")"; }
c "riesce subito"                       "ok/0/1" "$(prova 0 x)"
c "DNS caduto due volte, poi riesce"    "ok/0/3" "$(prova 2 'Could not resolve host: github.com')"
c "gh senza rete, poi riesce"           "ok/0/2" "$(prova 1 'error connecting to api.github.com')"
c "rete giù sempre: si arrende"         "/4/4"   "$(prova 9 'Could not resolve host: github.com')"
c "errore non di rete: niente retry"    "/4/1"   "$(prova 9 'GraphQL: Could not resolve to a PullRequest')"
c "merge rifiutato: niente retry"       "/4/1"   "$(prova 9 'Pull request is not mergeable')"
c "errore mostrato a chi chiama"        "Pull request is not mergeable" "$(rm -f "$tmp/n"; rete finto 9 'Pull request is not mergeable' 2>&1 >/dev/null)"
c "set -e: il retry non esce prima"     "ok"     "$(rm -f "$tmp/n"; bash -c 'set -euo pipefail; . "$1"; RETE_ATTESE=0; f() { [ -e "$2/x" ] || { touch "$2/x"; echo "Could not resolve host" >&2; return 1; }; echo ok; }; rete f _ "$2"' _ "$(dirname "$0")/rete.sh" "$tmp")"
rm -rf "$tmp"
exit $fail
