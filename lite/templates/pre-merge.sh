#!/usr/bin/env bash
# Template of the lite flow (lite/templates/pre-merge.sh): the architect copies it to
# scripts/pre-merge.sh and adapts only the «DA ADATTARE» block.
#
# `merge-pr.sh` runs it on the PR's code merged with the base (main or the wave branch),
# with PRE_MERGE_BASE=<base>: an exit other than 0 stops the merge. These are the fast checks
# (typecheck, lint, unit tests) that the reviewer does not rerun: no E2E, no external
# services, no real data. It prints only the summary or the errors: the reader is an agent.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

out=$(mktemp)
trap 'rm -f "$out"' EXIT

# One check: name, command. Red → prints the last lines and stops everything.
check() {
  local name=$1; shift
  if ! "$@" >"$out" 2>&1; then
    tail -n 60 "$out"
    echo "pre-merge: $name red"
    exit 1
  fi
  echo "pre-merge: $name green"
}

# --- DA ADATTARE: the project's fast checks, from the quickest on ------------------------
# Examples for a Node project; for other stacks: `cargo check`, `ruff check .`, `pytest -m "not e2e"`, …
check typecheck npx tsc --noEmit -p .
check lint      npx eslint . --quiet
check unit      npx vitest run
# -----------------------------------------------------------------------------------------
