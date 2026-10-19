#!/usr/bin/env bash
# Casi di prova di progetto-pronto.sh (controllo della sandbox, 1e): `bash lite/bin/progetto-pronto-cases.sh`.
# Esce con 1 se un caso fallisce.
bin=$(cd "$(dirname "$0")" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P); fail=0
c() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (atteso $2, ottenuto $3)"; fail=1; fi; }
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }

# Progetto con tutto il resto a posto (E2E: nessuno, così non servono e2e.sh ed e2e-scelta.sh).
r="$tmp/repo"; g init -q "$r"; mkdir -p "$r/docs/sicurezza" "$r/scripts" "$r/.claude"
printf 'File delle direttive tecniche: `docs/direttive.md`\nE2E: nessuno\nDeploy da main: no\nComandi solo con ok: nessuno\n' > "$r/CLAUDE.md"
printf '# Direttive\n## Sicurezza\n' > "$r/docs/direttive.md"
echo audit > "$r/docs/sicurezza/audit-2026-01-01.md"
printf '#!/usr/bin/env bash\nexit 0\n' > "$r/scripts/pre-merge.sh"
pp() { (cd "$r" && bash "$bin/progetto-pronto.sh" 2>&1); }
# sb <python che modifica s> : parte dal modello e lo cambia.
sb() { python3 -I - "$bin/../templates/settings.json" "$r/.claude/settings.json" "$1" <<'PY'
import json, sys
s = json.load(open(sys.argv[1])); exec(sys.argv[3]); json.dump(s, open(sys.argv[2], "w"))
PY
}

out=$(pp); rc=$?
c "senza settings.json: rosso"            1 "$rc"
c "senza settings.json: dice il modello"  si "$(grep -q 'manca .claude/settings.json con la sandbox (modello: .*templates/settings.json)' <<< "$out" && echo si || echo no)"
sb ""; out=$(pp); rc=$?
c "modello copiato: verde"                0 "$rc"
c "modello copiato: una riga ok"          "progetto-pronto: ok" "$out"
sb 's["sandbox"]["enabled"] = False'; out=$(pp); rc=$?
c "enabled false: rosso"                  1 "$rc"
c "enabled false: dice cosa manca"        si "$(grep -q 'sandbox.enabled: true' <<< "$out" && echo si || echo no)"
sb 's["sandbox"]["excludedCommands"] = ["docker *"]'; out=$(pp)
c "senza gh *: lo dice"                   si "$(grep -q '«gh \*» in sandbox.excludedCommands' <<< "$out" && echo si || echo no)"
sb 's["sandbox"]["network"]["allowedDomains"] = ["github.com"]'; out=$(pp)
c "senza api.github.com: lo dice"         si "$(grep -q '«api.github.com» in sandbox.network.allowedDomains' <<< "$out" && echo si || echo no)"
sb 'del s["sandbox"]["network"]["allowLocalBinding"]'; out=$(pp)
c "senza allowLocalBinding: lo dice"      si "$(grep -q 'allowLocalBinding: true' <<< "$out" && echo si || echo no)"
sb 's["sandbox"]["filesystem"]["denyRead"] = ["~/.ssh"]'; out=$(pp)
c "senza denyRead .env: lo dice"          si "$(grep -q '«\*\*/.env\*» in sandbox.filesystem.denyRead' <<< "$out" && echo si || echo no)"
sb 's["permissions"] = {}'; out=$(pp)
c "senza Read deny: lo dice"              si "$(grep -q '«Read(\*\*/.env\*)» in permissions.deny' <<< "$out" && echo si || echo no)"
sb 's["sandbox"]["network"]["allowMachLookup"] = True'; out=$(pp); rc=$?
c "allowMachLookup booleano: rosso"       1 "$rc"
c "allowMachLookup booleano: dice il tipo" si "$(grep -q 'sandbox.network.allowMachLookup dev.essere una lista: con il tipo sbagliato Claude Code ignora tutto il file' <<< "$out" && echo si || echo no)"
sb 's["sandbox"]["network"]["allowLocalBinding"] = "si"'; out=$(pp)
c "allowLocalBinding stringa: dice il tipo" si "$(grep -q 'allowLocalBinding dev.essere true o false' <<< "$out" && echo si || echo no)"
printf '{ "sandbox": { "enabled": true, }' > "$r/.claude/settings.json"; out=$(pp); rc=$?
c "JSON rotto: rosso"                     1 "$rc"
c "JSON rotto: lo dice"                   si "$(grep -q 'non è JSON valido' <<< "$out" && echo si || echo no)"
sb 's["sandbox"]["enabled"] = False; s["permissions"] = {}'; out=$(pp)
c "due mancanze: una riga sola con tutte e due" 1 "$(grep -c 'sandbox.enabled: true; .*«Read(\*\*/.env\*)» in permissions.deny' <<< "$out")"

rm -rf "$tmp"
exit $fail
