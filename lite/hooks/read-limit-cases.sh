#!/usr/bin/env bash
# Casi di prova di read-limit.sh: `bash lite/hooks/read-limit-cases.sh`. Esce con 1 se un caso fallisce.
H=$(dirname "$0")/read-limit.sh
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/src"
seq 1 301 > "$tmp/src/lungo.ts"
seq 1 300 > "$tmp/src/corto.ts"
fail=0
t() {
  local exp=$1 agent=$2 tool=$3 json=$4 rc got
  printf '%s' "$(python3 -c 'import json,sys; print(json.dumps({"agent_type":sys.argv[1] or None,"tool_name":sys.argv[2],"tool_input":json.loads(sys.argv[3]),"cwd":sys.argv[4]}))' "$agent" "$tool" "$json" "$tmp")" | bash "$H" >/dev/null 2>&1; rc=$?
  got=$([ $rc -eq 2 ] && echo BLOCK || echo ok)
  if [ "$got" = "$exp" ]; then r=PASS; else r=FAIL; fail=1; fi
  printf '%s  atteso %-5s ottenuto %-5s  %-10s %s %s\n' "$r" "$exp" "$got" "${agent:-principale}" "$tool" "$json"
}
t BLOCK developer Read '{"file_path":"src/lungo.ts"}'
t BLOCK reviewer  Read "{\"file_path\":\"$tmp/src/lungo.ts\"}"
t BLOCK developer Read '{"file_path":"src/lungo.ts","offset":1,"limit":2000}'
t ok    developer Read '{"file_path":"src/lungo.ts","offset":100,"limit":300}'
t ok    developer Read '{"file_path":"src/corto.ts"}'
t ok    developer Read '{"file_path":"src/non-esiste.ts"}'
t ok    architect Read '{"file_path":"src/lungo.ts"}'
t ok    ""        Read '{"file_path":"src/lungo.ts"}'
t BLOCK developer Bash '{"command":"cat src/lungo.ts"}'
t BLOCK developer Bash "{\"command\":\"cd $tmp/src && cat lungo.ts\"}"
t BLOCK developer Bash '{"command":"sed -n 1,400p src/lungo.ts"}'
t ok    developer Bash '{"command":"sed -n 1,120p src/lungo.ts"}'
t ok    developer Bash '{"command":"cat src/lungo.ts | grep 5"}'
t ok    developer Bash '{"command":"cat src/corto.ts"}'
t ok    developer Bash '{"command":"grep -n foo src/lungo.ts"}'
t ok    task-writer Bash '{"command":"cat src/lungo.ts"}'
exit $fail
