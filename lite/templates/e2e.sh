#!/usr/bin/env bash
# Template of the lite flow (lite/templates/e2e.sh): the architect copies it to scripts/e2e.sh
# and adapts only the «TO ADAPT» block. Usage: `bash scripts/e2e.sh <spec...> [runner options]`.
#
# What it guarantees, the same in every project:
#  - one E2E run at a time on the machine for every slot (port), shared by all the
#    worktrees of the repo: whoever arrives waits in the queue up to WAIT_MAX seconds. A slot whose
#    process is dead frees itself; a port taken by something else is skipped;
#  - one run at a time in the same worktree;
#  - if scripts/e2e-build.sh exists, it runs it after taking the slot (project build);
#  - the runner receives the slot's PORT and BASE_URL;
#  - every run leaves a line (time, exit, summary, arguments) in
#    <git-common-dir>/e2e-runs/<branch>.log, outside git and shared by the worktrees: the tester's
#    PR reports every run and the reviewer compares it with this file.
set -euo pipefail

# «E2E:» line of CLAUDE.md: with «E2E: at release» the E2E run only in the round before the release.
# E2E_FORCE=1 only for a run the user asks for.
if grep -qE '^E2E: at release' "$(git rev-parse --show-toplevel)/CLAUDE.md" 2>/dev/null && [ "${E2E_FORCE:-}" != 1 ]; then
  echo "e2e: CLAUDE.md says «E2E: at release», the E2E run only in the round before the release (E2E_FORCE=1)" >&2
  exit 1
fi

# --- TO ADAPT ------------------------------------------------------------------------
PORTS=(3101)      # one slot per port; more ports only if two runs together do not disturb each other (shared DB: one)
WAIT_MAX=3600     # maximum seconds in the queue
run_e2e() {       # the project's runner; receives the script's arguments
  npx playwright test "$@"
}
# Summary of the runner for the log (lines like «12 passed», «1 failed»).
summary() { grep -oE '^ +[0-9]+ (passed|failed|flaky|skipped|did not run)' "$1" | sed 's/^ *//' | paste -sd, - | sed 's/,/, /g'; }
# -----------------------------------------------------------------------------------------

cd "$(git rev-parse --show-toplevel)"
common=$(git rev-parse --path-format=absolute --git-common-dir)
here="$(git rev-parse --path-format=absolute --git-dir)/e2e-running"
if ! mkdir "$here" 2>/dev/null; then
  pid=$(cat "$here/pid" 2>/dev/null || true)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    echo "e2e: an e2e run is already going in this worktree (pid $pid)" >&2
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
  [ "$waited" -eq 0 ] && echo "e2e: all the slots (${PORTS[*]}) are taken, waiting..." >&2
  if [ "$waited" -ge "$WAIT_MAX" ]; then
    echo "e2e: no free slot after ${WAIT_MAX}s" >&2
    exit 1
  fi
  sleep 5
  waited=$((waited + 5))
done
trap 'rm -rf "$slots/$port" "$here"' EXIT
echo "e2e: slot on port $port" >&2

if [ -f scripts/e2e-build.sh ]; then bash scripts/e2e-build.sh >&2; fi

name=$(git rev-parse --abbrev-ref HEAD)
[ "$name" = HEAD ] && name=$(basename "$(git rev-parse --show-toplevel)")
log="$common/e2e-runs/${name//\//_}.log"
mkdir -p "$(dirname "$log")"
out=$(mktemp)
set +e
PORT=$port BASE_URL="http://localhost:$port" run_e2e "$@" 2>&1 | tee "$out"
code=${PIPESTATUS[0]}
set -e
outcome=$(summary "$out" || true)
printf '%s\texit=%s\t%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$code" "${outcome:-no summary}" "$*" >>"$log"
rm -f "$out"
exit "$code"
