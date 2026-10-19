#!/usr/bin/env bash
# Casi di prova di log-errors.sh + errori.sh: `bash lite/hooks/log-errors-cases.sh`. Esce con 1 se un caso fallisce.
H=$(cd "$(dirname "$0")" && pwd)/log-errors.sh; E=$(cd "$(dirname "$0")/../bin" && pwd)/errori.sh
tmp=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$tmp"' EXIT
export ERRORI_DIR=$tmp/log; R=$tmp/repo; git init -q "$R"; fail=0
ev() { python3 -c 'import json,sys; d={"hook_event_name":"PermissionDenied","session_id":"s","cwd":sys.argv[1],"agent_type":"developer","tool_name":"Bash","tool_input":{"command":sys.argv[2]},"transcript_path":"/x","tool_use_id":"t"}; d.update(json.loads(sys.argv[3])); print(json.dumps(d))' "$R" "$1" "$2" | bash "$H"; }
ev "rm -rf x" '{"reason": "prova-motivo"}'
ev "git push" '{}'
out=$(cd "$R" && bash "$E")
c() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (atteso $2, ottenuto $3)"; fail=1; fi; }
has() { printf '%s' "$out" | grep -c -- "$1"; }
c "il motivo compare sotto il comando"      1 "$(has 'prova-motivo')"
c "il comando negato compare"               1 "$(has 'rm -rf x')"
c "i campi noti non finiscono in altro"     0 "$(has 'transcript_path')"
c "senza campi nuovi nessuna riga altro"    1 "$(has '  → ')"
exit $fail
