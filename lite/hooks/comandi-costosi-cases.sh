#!/usr/bin/env bash
# Test cases of comandi-costosi.sh: `bash lite/hooks/comandi-costosi-cases.sh`. Exits with 1 if a case fails.
H=$(dirname "$0")/comandi-costosi.sh
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P)
R=$tmp/repo; git init -q "$R"; mkdir -p "$R/.claude/worktrees/task" "$R/src"
printf 'File delle direttive tecniche: `docs/direttive.md`\nComandi solo con ok: netlify deploy , supabase db push,node scripts/genera-.*\\.mjs\n' > "$R/CLAUDE.md"
S=$tmp/senza; git init -q "$S"; printf 'E2E: nessuno\n' > "$S/CLAUDE.md"
N=$tmp/nessuno; git init -q "$N"; printf 'Comandi solo con ok: nessuno\n' > "$N/CLAUDE.md"
mkdir -p "$tmp/fuori"
fail=0
t() {
  local exp=$1 agent=$2 cwd=$3 cmd=$4 rc got
  printf '%s' "$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","agent_type":sys.argv[1] or None,"tool_input":{"command":sys.argv[3]},"cwd":sys.argv[2]}))' "$agent" "$cwd" "$cmd")" | bash "$H" >/dev/null 2>"$tmp/err"; rc=$?
  got=$([ $rc -eq 2 ] && echo BLOCK || echo ok)
  if [ "$got" = "$exp" ]; then r=PASS; else r=FAIL; fail=1; fi
  printf '%s  expected %-5s got %-5s  %-10s %-18s %s\n' "$r" "$exp" "$got" "${agent:-main}" "${cwd#$tmp/}" "$(printf '%s' "$cmd" | head -c 60)"
}
t BLOCK developer "$R"                        'netlify deploy --prod'
t ok    ""        "$R"                        'netlify deploy --prod'
t ok    developer "$R"                        'npm test'
t ok    developer "$R"                        'echo netlify'
t BLOCK developer "$R"                        'supabase db push'
t BLOCK developer "$R"                        'node scripts/genera-immagini.mjs --tutte'
t ok    developer "$R"                        'node scripts/genera-immagini.ts'
t BLOCK tester    "$R"                        "bash -c 'cd app && netlify deploy'"
t BLOCK developer "$R/.claude/worktrees/task" 'netlify deploy'
t BLOCK developer "$tmp/fuori"                "cd $R/src && netlify deploy"
t BLOCK developer "$tmp"                      "(cd repo/src && npm run build && netlify deploy)"
t ok    developer "$tmp/fuori"                'netlify deploy'
t ok    developer "$S"                        'netlify deploy'
t ok    developer "$N"                        'netlify deploy'
t ok    developer "$N"                        'echo nessuno'
t ok    developer "$R"                        ''
printf '{rotto' | bash "$H" >/dev/null 2>&1; rc=$?
if [ $rc -eq 0 ]; then echo "PASS  broken JSON → exit 0"; else echo "FAIL  broken JSON → exit $rc"; fail=1; fi
printf '%s' "$(python3 -c 'import json; print(json.dumps({"tool_name":"Bash","agent_type":"developer","tool_input":{"command":"netlify deploy"},"cwd":"'"$R"'"}))')" | bash "$H" 2>&1 >/dev/null | grep -q 'stop and ask for it in the report' && echo "PASS  stop message on stderr" || { echo "FAIL  stop message on stderr"; fail=1; }
exit $fail
