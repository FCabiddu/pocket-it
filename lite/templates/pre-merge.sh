#!/usr/bin/env bash
# Modello del flusso lite (lite/templates/pre-merge.sh): l'architect lo copia in
# scripts/pre-merge.sh e adatta solo il blocco «DA ADATTARE».
#
# Lo lancia `merge-pr.sh` sul codice della PR unito alla base (main o il branch dell'onda),
# con PRE_MERGE_BASE=<base>: un exit diverso da 0 ferma il merge. Sono i controlli veloci
# (typecheck, lint, test unit) che il reviewer non rilancia: niente E2E, niente servizi
# esterni, niente dati veri. Stampa solo il riassunto o gli errori: chi lo legge è un agente.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

out=$(mktemp)
trap 'rm -f "$out"' EXIT

# Un controllo: nome, comando. Rosso → stampa le ultime righe e ferma tutto.
check() {
  local name=$1; shift
  if ! "$@" >"$out" 2>&1; then
    tail -n 60 "$out"
    echo "pre-merge: $name rosso"
    exit 1
  fi
  echo "pre-merge: $name verde"
}

# --- DA ADATTARE: i controlli veloci del progetto, nell'ordine dal più rapido ----------
# Esempi per un progetto Node; per altri stack: `cargo check`, `ruff check .`, `pytest -m "not e2e"`, …
check typecheck npx tsc --noEmit -p .
check lint      npx eslint . --quiet
check unit      npx vitest run
# -----------------------------------------------------------------------------------------
