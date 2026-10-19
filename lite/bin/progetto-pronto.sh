#!/usr/bin/env bash
# Controlla che il progetto abbia ciò che il flusso lite si aspetta (il «contratto»,
# lite/templates/README.md). La sessione principale lo lancia una volta, all'inizio di un
# progetto (la sua prima feature con il flusso); se è rosso, l'architect crea i pezzi mancanti dai modelli.
#   progetto-pronto.sh            (da dentro il repo)
#   progetto-pronto.sh --prova    lancia anche scripts/pre-merge.sh sul checkout
# Stampa una riga per ogni pezzo che manca o è sbagliato; esce con 1 se ce n'è almeno uno.
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "progetto-pronto: non sei in un repo git" >&2; exit 2; }
tpl="$(cd "$(dirname "$0")/../templates" && pwd)"
prova=0; [ "${1:-}" = --prova ] && prova=1
bad=()

# 1. Direttive: CLAUDE.md nomina il file delle direttive, e il file esiste.
if [ ! -f CLAUDE.md ]; then
  bad+=("manca CLAUDE.md, con la riga «File delle direttive tecniche: \`<percorso>\`»")
else
  dir=$(grep -oE '[Dd]irettive[^`]*`[^`]+`' CLAUDE.md | head -n 1 | sed -E 's/.*`([^`]+)`/\1/' || true)
  if [ -z "$dir" ]; then bad+=("CLAUDE.md non nomina il file delle direttive (riga «File delle direttive tecniche: \`<percorso>\`»)")
  elif [ ! -f "$dir" ]; then bad+=("CLAUDE.md nomina $dir, che non esiste")
  elif ! grep -qE '^#+ *Sicurezza' "$dir"; then bad+=("$dir non ha la sezione «Sicurezza» (architect.md; principi in lite/docs/sicurezza.md)")
  fi
fi

# 1b. E2E: CLAUDE.md dice quando si lanciano gli E2E (al rilascio, a fine onda, nessuno).
if [ -f CLAUDE.md ] && ! grep -qE '^E2E: (al rilascio|a fine onda|nessuno)$' CLAUDE.md; then
  bad+=("CLAUDE.md non ha la riga «E2E: al rilascio», «E2E: a fine onda» o «E2E: nessuno» (dice quando si lanciano gli E2E)")
fi

# 1c. Deploy: CLAUDE.md dice se un merge su main fa partire un deploy (build, crediti) prima del primo merge.
if [ -f CLAUDE.md ] && ! grep -qE '^Deploy da main: (sì|no)' CLAUDE.md; then
  bad+=("CLAUDE.md non ha la riga «Deploy da main: sì» o «Deploy da main: no» (dice se un merge su main pubblica e costa)")
fi

# 1c2. Comandi solo con ok: CLAUDE.md elenca i comandi che un agente non lancia da solo (hooks/comandi-costosi.sh), o «nessuno».
if [ -f CLAUDE.md ] && ! grep -qE '^Comandi solo con ok: .+' CLAUDE.md; then
  bad+=("CLAUDE.md non ha la riga «Comandi solo con ok: <regex>, <regex>, ...» (o «Comandi solo con ok: nessuno»): i comandi che un agente non lancia senza l'ok dell'utente, lite/templates/README.md")
fi

# 1d. Sicurezza: il progetto ha avuto la prima analisi dell'agente security (lavoro Audit).
if ! ls docs/sicurezza/audit-*.md >/dev/null 2>&1; then
  bad+=("manca docs/sicurezza/audit-<data>.md: la prima analisi di sicurezza la fa l'agente security (lavoro Audit)")
fi

# 1e. Sandbox: .claude/settings.json chiude i comandi Bash degli agenti nella sandbox di Claude Code
# (lite/templates/settings.json e README.md, «Sandbox»). Una chiave sbagliata fa ignorare tutto il file.
if [ ! -f .claude/settings.json ]; then
  bad+=("manca .claude/settings.json con la sandbox (modello: $tpl/settings.json)")
else
  err=$(python3 -I - .claude/settings.json <<'PY'
import json, sys
try:
    s = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"non è JSON valido ({e}): Claude Code ignora tutto il file, sandbox compresa"); sys.exit()
sb = s.get("sandbox") or {}; net = sb.get("network") or {}; fs = sb.get("filesystem") or {}; perm = s.get("permissions") or {}
manca = []
if sb.get("enabled") is not True: manca.append("sandbox.enabled: true")
if "gh *" not in (sb.get("excludedCommands") or []): manca.append("«gh *» in sandbox.excludedCommands (gh non supera il TLS dentro la sandbox)")
for d in ("github.com", "api.github.com"):
    if d not in (net.get("allowedDomains") or []): manca.append(f"«{d}» in sandbox.network.allowedDomains")
if net.get("allowLocalBinding") is not True: manca.append("sandbox.network.allowLocalBinding: true (server di sviluppo su localhost)")
if "**/.env*" not in (fs.get("denyRead") or []): manca.append("«**/.env*» in sandbox.filesystem.denyRead")
if "Read(**/.env*)" not in (perm.get("deny") or []): manca.append("«Read(**/.env*)» in permissions.deny (denyRead non ferma il tool Read)")
tipi = {("sandbox", "excludedCommands"): list, ("sandbox.network", "allowedDomains"): list, ("sandbox.network", "allowMachLookup"): list,
        ("sandbox.network", "allowUnixSockets"): list, ("sandbox.network", "allowLocalBinding"): bool, ("sandbox.filesystem", "denyRead"): list,
        ("sandbox.filesystem", "allowWrite"): list}
for (dove, k), t in tipi.items():
    obj = {"sandbox": sb, "sandbox.network": net, "sandbox.filesystem": fs}[dove]
    if k in obj and not isinstance(obj[k], t):
        manca.append(f"{dove}.{k} dev'essere {'una lista' if t is list else 'true o false'}: con il tipo sbagliato Claude Code ignora tutto il file, sandbox compresa")
print("; ".join(manca))
PY
)
  [ -z "$err" ] || bad+=(".claude/settings.json: $err (modello: $tpl/settings.json; nella sessione «/sandbox» dice se è attiva)")
fi

# 2. Controlli prima del merge: senza, merge-pr.sh si ferma.
if [ ! -f scripts/pre-merge.sh ]; then
  bad+=("manca scripts/pre-merge.sh (modello: $tpl/pre-merge.sh)")
elif [ "$prova" = 1 ]; then
  if ! PRE_MERGE_BASE=main bash scripts/pre-merge.sh >/dev/null 2>&1; then bad+=("scripts/pre-merge.sh è rosso sul checkout attuale"); fi
fi

# 3. E2E: salvo «E2E: nessuno» in CLAUDE.md (progetto senza interfaccia da provare dall'esterno).
if [ -f CLAUDE.md ] && grep -qE '^E2E: nessuno' CLAUDE.md; then
  :
else
  if [ ! -f scripts/e2e.sh ]; then
    bad+=("manca scripts/e2e.sh (modello: $tpl/e2e.sh; un progetto senza E2E scrive «E2E: nessuno» in CLAUDE.md)")
  elif ! grep -q 'e2e-slots' scripts/e2e.sh || ! grep -q 'e2e-giri' scripts/e2e.sh; then
    bad+=("scripts/e2e.sh non ha la fila sul posto (e2e-slots) o il registro dei giri (e2e-giri) del modello $tpl/e2e.sh")
  fi
  if [ ! -f scripts/e2e-scelta.sh ]; then
    bad+=("manca scripts/e2e-scelta.sh (modello: $tpl/e2e-scelta.sh e $tpl/spec-per-cartella.txt)")
  elif ! bash scripts/e2e-scelta.sh --verifica >/dev/null 2>&1; then
    bad+=("scripts/e2e-scelta.sh --verifica è rosso: la mappa degli spec ha righe sbagliate")
  fi
fi

if [ ${#bad[@]} -eq 0 ]; then
  echo "progetto-pronto: ok"
  exit 0
fi
printf 'progetto-pronto: %s\n' "${bad[@]}"
exit 1
