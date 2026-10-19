#!/usr/bin/env bash
# Test cases for read-limit.sh: `bash lite/hooks/read-limit-cases.sh`. Exits with 1 if a case fails.
H=$(dirname "$0")/read-limit.sh
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/src"
seq 1 301 > "$tmp/src/long.ts"
seq 1 300 > "$tmp/src/short.ts"
fail=0
t() {
  local exp=$1 agent=$2 tool=$3 json=$4 rc got
  printf '%s' "$(python3 -c 'import json,sys; print(json.dumps({"agent_type":sys.argv[1] or None,"tool_name":sys.argv[2],"tool_input":json.loads(sys.argv[3]),"cwd":sys.argv[4]}))' "$agent" "$tool" "$json" "$tmp")" | bash "$H" >/dev/null 2>&1; rc=$?
  got=$([ $rc -eq 2 ] && echo BLOCK || echo ok)
  if [ "$got" = "$exp" ]; then r=PASS; else r=FAIL; fail=1; fi
  printf '%s  expected %-5s got %-5s  %-10s %s %s\n' "$r" "$exp" "$got" "${agent:-main}" "$tool" "$json"
}
t BLOCK developer Read '{"file_path":"src/long.ts"}'
t BLOCK reviewer  Read "{\"file_path\":\"$tmp/src/long.ts\"}"
t BLOCK developer Read '{"file_path":"src/long.ts","offset":1,"limit":2000}'
t ok    developer Read '{"file_path":"src/long.ts","offset":100,"limit":300}'
t ok    developer Read '{"file_path":"src/short.ts"}'
t ok    developer Read '{"file_path":"src/missing.ts"}'
t ok    architect Read '{"file_path":"src/long.ts"}'
t ok    ""        Read '{"file_path":"src/long.ts"}'
t BLOCK developer Bash '{"command":"cat src/long.ts"}'
t BLOCK developer Bash "{\"command\":\"cd $tmp/src && cat long.ts\"}"
t BLOCK developer Bash '{"command":"sed -n 1,400p src/long.ts"}'
t ok    developer Bash '{"command":"sed -n 1,120p src/long.ts"}'
t ok    developer Bash '{"command":"cat src/long.ts | grep 5"}'
t ok    developer Bash '{"command":"cat src/short.ts"}'
t ok    developer Bash '{"command":"grep -n foo src/long.ts"}'
t ok    task-writer Bash '{"command":"cat src/long.ts"}'
exit $fail
