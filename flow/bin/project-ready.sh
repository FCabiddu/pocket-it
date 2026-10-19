#!/usr/bin/env bash
# Checks that the project has what the flow expects (the «contract»,
# flow/templates/README.md). The main session runs it once, at the start of a
# project (its first feature with the flow); if it is red, the architect creates the missing pieces from the templates.
#   project-ready.sh            (from inside the repo)
#   project-ready.sh --dry-run    also runs scripts/pre-merge.sh on the checkout
# Prints one line for every piece that is missing or wrong; exits with 1 if there is at least one.
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "project-ready: not inside a git repo" >&2; exit 2; }
tpl="$(cd "$(dirname "$0")/../templates" && pwd)"
dry_run=0; [ "${1:-}" = --dry-run ] && dry_run=1
bad=()

# 1. Directives: CLAUDE.md names the directives file, and the file exists.
if [ ! -f CLAUDE.md ]; then
  bad+=("CLAUDE.md is missing, with the line «Technical directives file: \`<path>\`»")
else
  dir=$(grep -oE '[Dd]irectives[^`]*`[^`]+`' CLAUDE.md | head -n 1 | sed -E 's/.*`([^`]+)`/\1/' || true)
  if [ -z "$dir" ]; then bad+=("CLAUDE.md does not name the directives file (line «Technical directives file: \`<path>\`»)")
  elif [ ! -f "$dir" ]; then bad+=("CLAUDE.md names $dir, which does not exist")
  elif ! grep -qE '^#+ *Security' "$dir"; then bad+=("$dir has no «Security» section (architect.md; principles in flow/docs/security.md)")
  fi
fi

# 1b. E2E: CLAUDE.md says when the E2E run (at release, end of wave, none).
if [ -f CLAUDE.md ] && ! grep -qE '^E2E: (at release|end of wave|none)$' CLAUDE.md; then
  bad+=("CLAUDE.md has no «E2E: at release», «E2E: end of wave» or «E2E: none» line (it says when the E2E run)")
fi

# 1c. Deploy: CLAUDE.md says whether a merge to main triggers a deploy (build, credits), before the first merge.
if [ -f CLAUDE.md ] && ! grep -qE '^Deploy from main: (yes|no)' CLAUDE.md; then
  bad+=("CLAUDE.md has no «Deploy from main: yes» or «Deploy from main: no» line (it says whether a merge to main publishes and costs)")
fi

# 1c2. Commands only with approval: CLAUDE.md lists the commands an agent does not run on its own (hooks/costly-commands.sh), or «none».
if [ -f CLAUDE.md ] && ! grep -qE '^Commands only with approval: .+' CLAUDE.md; then
  bad+=("CLAUDE.md has no «Commands only with approval: <regex>, <regex>, ...» line (or «Commands only with approval: none»): the commands an agent does not run without the user's ok, flow/templates/README.md")
fi

# 1d. Security: the project has had the first audit by the security agent (Audit job).
if ! ls docs/security/audit-*.md >/dev/null 2>&1; then
  bad+=("docs/security/audit-<date>.md is missing: the first security audit is done by the security agent (Audit job)")
fi

# 1e. Sandbox: .claude/settings.json confines the agents' Bash commands in the Claude Code sandbox
# (flow/templates/settings.json and README.md, «Sandbox»). One wrong key makes the whole file ignored.
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
missing = []
if sb.get("enabled") is not True: missing.append("sandbox.enabled: true")
if "gh *" not in (sb.get("excludedCommands") or []): missing.append("«gh *» in sandbox.excludedCommands (gh does not get through TLS inside the sandbox)")
for d in ("github.com", "api.github.com"):
    if d not in (net.get("allowedDomains") or []): missing.append(f"«{d}» in sandbox.network.allowedDomains")
if net.get("allowLocalBinding") is not True: missing.append("sandbox.network.allowLocalBinding: true (dev server on localhost)")
if "**/.env*" not in (fs.get("denyRead") or []): missing.append("«**/.env*» in sandbox.filesystem.denyRead")
if "Read(**/.env*)" not in (perm.get("deny") or []): missing.append("«Read(**/.env*)» in permissions.deny (denyRead does not stop the Read tool)")
types = {("sandbox", "excludedCommands"): list, ("sandbox.network", "allowedDomains"): list, ("sandbox.network", "allowMachLookup"): list,
        ("sandbox.network", "allowUnixSockets"): list, ("sandbox.network", "allowLocalBinding"): bool, ("sandbox.filesystem", "denyRead"): list,
        ("sandbox.filesystem", "allowWrite"): list}
for (where, k), t in types.items():
    obj = {"sandbox": sb, "sandbox.network": net, "sandbox.filesystem": fs}[where]
    if k in obj and not isinstance(obj[k], t):
        missing.append(f"{where}.{k} must be {'a list' if t is list else 'true or false'}: with the wrong type Claude Code ignores the whole file, sandbox included")
print("; ".join(missing))
PY
)
  [ -z "$err" ] || bad+=(".claude/settings.json: $err (template: $tpl/settings.json; in the session «/sandbox» says whether it is active)")
fi

# 2. Checks before the merge: without them, merge-pr.sh stops.
if [ ! -f scripts/pre-merge.sh ]; then
  bad+=("scripts/pre-merge.sh is missing (template: $tpl/pre-merge.sh)")
elif [ "$dry_run" = 1 ]; then
  if ! PRE_MERGE_BASE=main bash scripts/pre-merge.sh >/dev/null 2>&1; then bad+=("scripts/pre-merge.sh is red on the current checkout"); fi
fi

# 3. E2E: unless «E2E: none» in CLAUDE.md (project with no interface to test from the outside).
if [ -f CLAUDE.md ] && grep -qE '^E2E: none' CLAUDE.md; then
  :
else
  if [ ! -f scripts/e2e.sh ]; then
    bad+=("scripts/e2e.sh is missing (template: $tpl/e2e.sh; a project without E2E writes «E2E: none» in CLAUDE.md)")
  elif ! grep -q 'e2e-slots' scripts/e2e.sh || ! grep -q 'e2e-runs' scripts/e2e.sh; then
    bad+=("scripts/e2e.sh has no local queue (e2e-slots) or run log (e2e-runs) from the template $tpl/e2e.sh")
  fi
  if [ ! -f scripts/e2e-select.sh ]; then
    bad+=("scripts/e2e-select.sh is missing (template: $tpl/e2e-select.sh and $tpl/spec-per-folder.txt)")
  elif ! bash scripts/e2e-select.sh --check >/dev/null 2>&1; then
    bad+=("scripts/e2e-select.sh --check is red: the spec map has wrong lines")
  fi
fi

if [ ${#bad[@]} -eq 0 ]; then
  echo "project-ready: ok"
  exit 0
fi
printf 'project-ready: %s\n' "${bad[@]}"
exit 1
