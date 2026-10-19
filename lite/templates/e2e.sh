#!/usr/bin/env bash
# Modello del flusso lite (lite/templates/e2e.sh): l'architect lo copia in scripts/e2e.sh
# e adatta solo il blocco «DA ADATTARE». Uso: `bash scripts/e2e.sh <spec...> [opzioni del runner]`.
#
# Cosa garantisce, uguale in ogni progetto:
#  - un solo giro E2E alla volta sulla macchina per ogni posto (porta), condiviso da tutti i
#    worktree del repo: chi arriva aspetta in fila fino a WAIT_MAX secondi. Un posto il cui
#    processo è morto si libera da solo; una porta occupata da altro si salta;
#  - un solo giro alla volta nello stesso worktree;
#  - se c'è scripts/e2e-build.sh, lo lancia dopo aver preso il posto (build del progetto);
#  - il runner riceve PORT e BASE_URL del posto;
#  - ogni giro lascia una riga (ora, exit, riepilogo, argomenti) in
#    <git-common-dir>/e2e-giri/<branch>.log, fuori da git e comune ai worktree: la PR del
#    tester riporta ogni giro e il reviewer lo confronta con questo file.
set -euo pipefail

# Riga «E2E:» di CLAUDE.md: con «E2E: al rilascio» gli E2E si lanciano solo nel giro prima del rilascio.
# E2E_FORZA=1 solo per un giro che l'utente chiede.
if grep -qE '^E2E: al rilascio' "$(git rev-parse --show-toplevel)/CLAUDE.md" 2>/dev/null && [ "${E2E_FORZA:-}" != 1 ]; then
  echo "e2e: CLAUDE.md dice «E2E: al rilascio», gli E2E si lanciano solo nel giro prima del rilascio (E2E_FORZA=1)" >&2
  exit 1
fi

# --- DA ADATTARE ------------------------------------------------------------------------
PORTS=(3101)      # un posto per porta; più porte solo se due giri insieme non si disturbano (DB condiviso: una)
WAIT_MAX=3600     # secondi di fila al massimo
run_e2e() {       # il runner del progetto; riceve gli argomenti dello script
  npx playwright test "$@"
}
# Riepilogo del runner per il registro (righe tipo «12 passed», «1 failed»).
summary() { grep -oE '^ +[0-9]+ (passed|failed|flaky|skipped|did not run)' "$1" | sed 's/^ *//' | paste -sd, - | sed 's/,/, /g'; }
# -----------------------------------------------------------------------------------------

cd "$(git rev-parse --show-toplevel)"
common=$(git rev-parse --path-format=absolute --git-common-dir)
here="$(git rev-parse --path-format=absolute --git-dir)/e2e-running"
if ! mkdir "$here" 2>/dev/null; then
  pid=$(cat "$here/pid" 2>/dev/null || true)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    echo "e2e: in questo worktree gira già un e2e (pid $pid)" >&2
    exit 1
  fi
fi
echo $$ >"$here/pid"
slots="$common/e2e-slots"
mkdir -p "$slots"

port_busy() { lsof -nP -iTCP:"$1" -sTCP:LISTEN -t >/dev/null 2>&1; }

take_slot() {
  local port dir pid
  for port in "${PORTS[@]}"; do
    dir="$slots/$port"
    if ! mkdir "$dir" 2>/dev/null; then
      pid=$(cat "$dir/pid" 2>/dev/null || true)
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
        rm -rf "$dir"
        mkdir "$dir" 2>/dev/null || continue
      else
        continue
      fi
    fi
    echo $$ >"$dir/pid"
    if port_busy "$port"; then
      rm -rf "$dir"
      continue
    fi
    echo "$port"
    return 0
  done
  return 1
}

trap 'rm -rf "$here"' EXIT

waited=0
until port=$(take_slot); do
  [ "$waited" -eq 0 ] && echo "e2e: tutti i posti (${PORTS[*]}) sono occupati, aspetto..." >&2
  if [ "$waited" -ge "$WAIT_MAX" ]; then
    echo "e2e: nessun posto libero dopo ${WAIT_MAX}s" >&2
    exit 1
  fi
  sleep 5
  waited=$((waited + 5))
done
trap 'rm -rf "$slots/$port" "$here"' EXIT
echo "e2e: posto sulla porta $port" >&2

if [ -f scripts/e2e-build.sh ]; then bash scripts/e2e-build.sh >&2; fi

name=$(git rev-parse --abbrev-ref HEAD)
[ "$name" = HEAD ] && name=$(basename "$(git rev-parse --show-toplevel)")
log="$common/e2e-giri/${name//\//_}.log"
mkdir -p "$(dirname "$log")"
out=$(mktemp)
set +e
PORT=$port BASE_URL="http://localhost:$port" run_e2e "$@" 2>&1 | tee "$out"
code=${PIPESTATUS[0]}
set -e
esito=$(summary "$out" || true)
printf '%s\texit=%s\t%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$code" "${esito:-nessun riepilogo}" "$*" >>"$log"
rm -f "$out"
exit "$code"
