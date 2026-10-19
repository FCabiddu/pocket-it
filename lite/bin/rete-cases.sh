#!/usr/bin/env bash
# Test cases of rete.sh: `bash lite/bin/rete-cases.sh`. Exits with 1 if a case fails.
. "$(cd "$(dirname "$0")" && pwd)/rete.sh"
export RETE_ATTESE="0 0 0"
tmp=$(mktemp -d); fail=0
c() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (expected $2, got $3)"; fail=1; fi; }
# finto <errors before succeeding> <message>: counts the runs in $tmp/n, prints «ok» when it succeeds.
finto() {
  local n; n=$(( $(cat "$tmp/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$tmp/n"
  if [ "$n" -le "$1" ]; then echo "$2" >&2; return 4; fi
  echo ok
}
prova() { rm -f "$tmp/n"; out=$(rete finto "$@" 2>/dev/null); rc=$?; echo "$out/$rc/$(cat "$tmp/n")"; }
c "succeeds at once"                    "ok/0/1" "$(prova 0 x)"
c "DNS down twice, then succeeds"       "ok/0/3" "$(prova 2 'Could not resolve host: github.com')"
c "gh without network, then succeeds"   "ok/0/2" "$(prova 1 'error connecting to api.github.com')"
c "network always down: gives up"       "/4/4"   "$(prova 9 'Could not resolve host: github.com')"
c "non-network error: no retry"         "/4/1"   "$(prova 9 'GraphQL: Could not resolve to a PullRequest')"
c "rejected merge: no retry"            "/4/1"   "$(prova 9 'Pull request is not mergeable')"
c "error shown to the caller"           "Pull request is not mergeable" "$(rm -f "$tmp/n"; rete finto 9 'Pull request is not mergeable' 2>&1 >/dev/null)"
c "set -e: the retry does not exit early" "ok"     "$(rm -f "$tmp/n"; bash -c 'set -euo pipefail; . "$1"; RETE_ATTESE=0; f() { [ -e "$2/x" ] || { touch "$2/x"; echo "Could not resolve host" >&2; return 1; }; echo ok; }; rete f _ "$2"' _ "$(dirname "$0")/rete.sh" "$tmp")"
rm -rf "$tmp"
exit $fail
