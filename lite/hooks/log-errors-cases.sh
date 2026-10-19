#!/usr/bin/env bash
# Test cases of log-errors.sh + errors.sh: `bash lite/hooks/log-errors-cases.sh`. Exits with 1 if a case fails.
H=$(cd "$(dirname "$0")" && pwd)/log-errors.sh; E=$(cd "$(dirname "$0")/../bin" && pwd)/errors.sh
tmp=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$tmp"' EXIT
export ERRORS_DIR=$tmp/log; R=$tmp/repo; git init -q "$R"; fail=0
ev() { python3 -c 'import json,sys; d={"hook_event_name":"PermissionDenied","session_id":"s","cwd":sys.argv[1],"agent_type":"developer","tool_name":"Bash","tool_input":{"command":sys.argv[2]},"transcript_path":"/x","tool_use_id":"t"}; d.update(json.loads(sys.argv[3])); print(json.dumps(d))' "$R" "$1" "$2" | bash "$H"; }
ev "rm -rf x" '{"reason": "sample-reason"}'
ev "git push" '{}'
out=$(cd "$R" && bash "$E")
c() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (expected $2, got $3)"; fail=1; fi; }
has() { printf '%s' "$out" | grep -c -- "$1"; }
c "the reason appears under the command"    1 "$(has 'sample-reason')"
c "the denied command appears"              1 "$(has 'rm -rf x')"
c "known fields do not end up in other"     0 "$(has 'transcript_path')"
c "without new fields no other line"        1 "$(has '  → ')"
exit $fail
