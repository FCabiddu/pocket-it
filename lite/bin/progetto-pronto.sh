#!/usr/bin/env bash
# Checks that the project has what the lite flow expects (the «contract»,
# lite/templates/README.md). The main session runs it once, at the start of a
# project (its first feature with the flow); if it is red, the architect creates the missing pieces from the templates.
#   progetto-pronto.sh            (from inside the repo)
#   progetto-pronto.sh --prova    also runs scripts/pre-merge.sh on the checkout
# Prints one line for every piece that is missing or wrong; exits with 1 if there is at least one.
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "progetto-pronto: not inside a git repo" >&2; exit 2; }
tpl="$(cd "$(dirname "$0")/../templates" && pwd)"
prova=0; [ "${1:-}" = --prova ] && prova=1
bad=()

# 1. Directives: CLAUDE.md names the directives file, and the file exists.
if [ ! -f CLAUDE.md ]; then
  bad+=("CLAUDE.md is missing, with the line «File delle direttive tecniche: \`<path>\`»")
else
  dir=$(grep -oE '[Dd]irettive[^`]*`[^`]+`' CLAUDE.md | head -n 1 | sed -E 's/.*`([^`]+)`/\1/' || true)
  if [ -z "$dir" ]; then bad+=("CLAUDE.md does not name the directives file (line «File delle direttive tecniche: \`<path>\`»)")
  elif [ ! -f "$dir" ]; then bad+=("CLAUDE.md names $dir, which does not exist")
  elif ! grep -qE '^#+ *Sicurezza' "$dir"; then bad+=("$dir has no «Sicurezza» section (architect.md; principles in lite/docs/sicurezza.md)")
  fi
fi

# 1b. E2E: CLAUDE.md says when the E2E run (al rilascio, a fine onda, nessuno).
if [ -f CLAUDE.md ] && ! grep -qE '^E2E: (al rilascio|a fine onda|nessuno)$' CLAUDE.md; then
  bad+=("CLAUDE.md has no «E2E: al rilascio», «E2E: a fine onda» or «E2E: nessuno» line (it says when the E2E run)")
fi

# 1c. Deploy: CLAUDE.md says whether a merge to main triggers a deploy (build, credits), before the first merge.
if [ -f CLAUDE.md ] && ! grep -qE '^Deploy da main: (sì|no)' CLAUDE.md; then
  bad+=("CLAUDE.md has no «Deploy da main: sì» or «Deploy da main: no» line (it says whether a merge to main publishes and costs)")
fi

# 1c2. Comandi solo con ok: CLAUDE.md lists the commands an agent does not run on its own (hooks/comandi-costosi.sh), or «nessuno».
if [ -f CLAUDE.md ] && ! grep -qE '^Comandi solo con ok: .+' CLAUDE.md; then
  bad+=("CLAUDE.md has no «Comandi solo con ok: <regex>, <regex>, ...» line (or «Comandi solo con ok: nessuno»): the commands an agent does not run without the user's ok, lite/templates/README.md")
fi

# 1d. Security: the project has had the first audit by the security agent (Audit job).
if ! ls docs/sicurezza/audit-*.md >/dev/null 2>&1; then
  bad+=("docs/sicurezza/audit-<date>.md is missing: the first security audit is done by the security agent (Audit job)")
fi

# 1e. Sandbox: .claude/settings.json confines the agents' Bash commands in the Claude Code sandbox
# (lite/templates/settings.json and README.md, «Sandbox»). One wrong key makes the whole file ignored.
if [ ! -f .claude/settings.json ]; then
  bad+=(".claude/settings.json with the sandbox is missing (template: $tpl/settings.json)")
else
  err=$(python3 -I - .claude/settings.json <<'PY'
import json, sys
try:
    s = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"is not valid JSON ({e}): Claude Code ignores the whole file, sandbox included"); sys.exit()
sb = s.get("sandbox") or {}; net = sb.get("network") or {}; fs = sb.get("filesystem") or {}; perm = s.get("permissions") or {}
manca = []
if sb.get("enabled") is not True: manca.append("sandbox.enabled: true")
if "gh *" not in (sb.get("excludedCommands") or []): manca.append("«gh *» in sandbox.excludedCommands (gh does not get through TLS inside the sandbox)")
for d in ("github.com", "api.github.com"):
    if d not in (net.get("allowedDomains") or []): manca.append(f"«{d}» in sandbox.network.allowedDomains")
if net.get("allowLocalBinding") is not True: manca.append("sandbox.network.allowLocalBinding: true (dev server on localhost)")
if "**/.env*" not in (fs.get("denyRead") or []): manca.append("«**/.env*» in sandbox.filesystem.denyRead")
if "Read(**/.env*)" not in (perm.get("deny") or []): manca.append("«Read(**/.env*)» in permissions.deny (denyRead does not stop the Read tool)")
tipi = {("sandbox", "excludedCommands"): list, ("sandbox.network", "allowedDomains"): list, ("sandbox.network", "allowMachLookup"): list,
        ("sandbox.network", "allowUnixSockets"): list, ("sandbox.network", "allowLocalBinding"): bool, ("sandbox.filesystem", "denyRead"): list,
        ("sandbox.filesystem", "allowWrite"): list}
for (dove, k), t in tipi.items():
    obj = {"sandbox": sb, "sandbox.network": net, "sandbox.filesystem": fs}[dove]
    if k in obj and not isinstance(obj[k], t):
        manca.append(f"{dove}.{k} must be {'a list' if t is list else 'true or false'}: with the wrong type Claude Code ignores the whole file, sandbox included")
print("; ".join(manca))
PY
)
  [ -z "$err" ] || bad+=(".claude/settings.json: $err (template: $tpl/settings.json; in the session «/sandbox» says whether it is active)")
fi

# 2. Checks before the merge: without them, merge-pr.sh stops.
if [ ! -f scripts/pre-merge.sh ]; then
  bad+=("scripts/pre-merge.sh is missing (template: $tpl/pre-merge.sh)")
elif [ "$prova" = 1 ]; then
  if ! PRE_MERGE_BASE=main bash scripts/pre-merge.sh >/dev/null 2>&1; then bad+=("scripts/pre-merge.sh is red on the current checkout"); fi
fi

# 3. E2E: unless «E2E: nessuno» in CLAUDE.md (project with no interface to test from the outside).
if [ -f CLAUDE.md ] && grep -qE '^E2E: nessuno' CLAUDE.md; then
  :
else
  if [ ! -f scripts/e2e.sh ]; then
    bad+=("scripts/e2e.sh is missing (template: $tpl/e2e.sh; a project without E2E writes «E2E: nessuno» in CLAUDE.md)")
  elif ! grep -q 'e2e-slots' scripts/e2e.sh || ! grep -q 'e2e-giri' scripts/e2e.sh; then
    bad+=("scripts/e2e.sh has no local queue (e2e-slots) or run log (e2e-giri) from the template $tpl/e2e.sh")
  fi
  if [ ! -f scripts/e2e-scelta.sh ]; then
    bad+=("scripts/e2e-scelta.sh is missing (template: $tpl/e2e-scelta.sh and $tpl/spec-per-cartella.txt)")
  elif ! bash scripts/e2e-scelta.sh --verifica >/dev/null 2>&1; then
    bad+=("scripts/e2e-scelta.sh --verifica is red: the spec map has wrong lines")
  fi
fi

if [ ${#bad[@]} -eq 0 ]; then
  echo "progetto-pronto: ok"
  exit 0
fi
printf 'progetto-pronto: %s\n' "${bad[@]}"
exit 1
