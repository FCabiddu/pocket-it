#!/usr/bin/env bash
# Test cases for project-ready.sh (sandbox check, 1e): `bash flow/bin/project-ready-cases.sh`.
# Exits with 1 if a case fails.
bin=$(cd "$(dirname "$0")" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P); fail=0
c() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (expected $2, got $3)"; fail=1; fi; }
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }

# Project with everything else in place (E2E: none, so e2e.sh and e2e-select.sh are not needed).
r="$tmp/repo"; g init -q "$r"; mkdir -p "$r/docs/security" "$r/scripts" "$r/.claude"
printf 'Technical directives file: `docs/directives.md`\nE2E: none\nDeploy from main: no\nCommands only with approval: none\n' > "$r/CLAUDE.md"
printf '# Directives\n## Security\n' > "$r/docs/directives.md"
echo audit > "$r/docs/security/audit-2026-01-01.md"
printf '#!/usr/bin/env bash\nexit 0\n' > "$r/scripts/pre-merge.sh"
pp() { (cd "$r" && bash "$bin/project-ready.sh" 2>&1); }
# sb <python that modifies s> : starts from the template and changes it.
sb() { python3 -I - "$bin/../templates/settings.json" "$r/.claude/settings.json" "$1" <<'PY'
import json, sys
s = json.load(open(sys.argv[1])); exec(sys.argv[3]); json.dump(s, open(sys.argv[2], "w"))
PY
}

out=$(pp); rc=$?
c "without settings.json: red"            1 "$rc"
c "without settings.json: names the template"  yes "$(grep -q '.claude/settings.json with the sandbox is missing (template: .*templates/settings.json)' <<< "$out" && echo yes || echo no)"
sb ""; out=$(pp); rc=$?
c "template copied: green"                0 "$rc"
c "template copied: one ok line"          "project-ready: ok" "$out"
sb 's["sandbox"]["enabled"] = False'; out=$(pp); rc=$?
c "enabled false: red"                    1 "$rc"
c "enabled false: says what is missing"   yes "$(grep -q 'sandbox.enabled: true' <<< "$out" && echo yes || echo no)"
sb 's["sandbox"]["excludedCommands"] = ["docker *"]'; out=$(pp)
c "without gh *: says so"                 yes "$(grep -q '«gh \*» in sandbox.excludedCommands' <<< "$out" && echo yes || echo no)"
sb 's["sandbox"]["network"]["allowedDomains"] = ["github.com"]'; out=$(pp)
c "without api.github.com: says so"       yes "$(grep -q '«api.github.com» in sandbox.network.allowedDomains' <<< "$out" && echo yes || echo no)"
sb 'del s["sandbox"]["network"]["allowLocalBinding"]'; out=$(pp)
c "without allowLocalBinding: says so"    yes "$(grep -q 'allowLocalBinding: true' <<< "$out" && echo yes || echo no)"
sb 's["sandbox"]["filesystem"]["denyRead"] = ["~/.ssh"]'; out=$(pp)
c "without denyRead .env: says so"        yes "$(grep -q '«\*\*/.env\*» in sandbox.filesystem.denyRead' <<< "$out" && echo yes || echo no)"
sb 's["permissions"] = {}'; out=$(pp)
c "without Read deny: says so"            yes "$(grep -q '«Read(\*\*/.env\*)» in permissions.deny' <<< "$out" && echo yes || echo no)"
sb 's["sandbox"]["network"]["allowMachLookup"] = True'; out=$(pp); rc=$?
c "allowMachLookup boolean: red"          1 "$rc"
c "allowMachLookup boolean: says the type" yes "$(grep -q 'sandbox.network.allowMachLookup must be a list: with the wrong type Claude Code ignores the whole file' <<< "$out" && echo yes || echo no)"
sb 's["sandbox"]["network"]["allowLocalBinding"] = "yes"'; out=$(pp)
c "allowLocalBinding string: says the type" yes "$(grep -q 'allowLocalBinding must be true or false' <<< "$out" && echo yes || echo no)"
printf '{ "sandbox": { "enabled": true, }' > "$r/.claude/settings.json"; out=$(pp); rc=$?
c "broken JSON: red"                      1 "$rc"
c "broken JSON: says so"                  yes "$(grep -q 'is not valid JSON' <<< "$out" && echo yes || echo no)"
sb 's["sandbox"]["enabled"] = False; s["permissions"] = {}'; out=$(pp)
c "two gaps: one single line with both"   1 "$(grep -c 'sandbox.enabled: true; .*«Read(\*\*/.env\*)» in permissions.deny' <<< "$out")"

rm -rf "$tmp"
exit $fail
