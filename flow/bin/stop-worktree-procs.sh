#!/usr/bin/env bash
# Stops the processes whose working directory is inside <dir> (next dev servers, watchers left running),
# except the caller and its ancestors. First TERM, then KILL after 5 seconds. Prints what it stops.
#   stop-worktree-procs.sh <dir>     (used by merge-pr.sh before removing a worktree)
set -uo pipefail

dir=$(cd "${1:?usage: stop-worktree-procs.sh <dir>}" 2>/dev/null && pwd -P) || exit 0

keep=" "; p=$$
while [ -n "$p" ] && [ "$p" -gt 1 ]; do keep="$keep$p "; p=$(ps -o ppid= -p "$p" | tr -d ' '); done

pids=$(lsof -nP -d cwd -Fpn 2>/dev/null | awk -v d="$dir" '
  /^p/ {pid=substr($0,2)} /^n/ {n=substr($0,2); if (n==d || index(n, d "/")==1) print pid}' | sort -u)

todo=""
for pid in $pids; do
  case "$keep" in *" $pid "*) continue ;; esac
  echo "stop-worktree-procs: stopping $pid ($(ps -o command= -p "$pid" | cut -c1-80))"
  kill "$pid" 2>/dev/null && todo="$todo $pid"
done
[ -z "$todo" ] && exit 0
for _ in 1 2 3 4 5; do
  alive=""; for pid in $todo; do kill -0 "$pid" 2>/dev/null && alive="$alive $pid"; done
  [ -z "$alive" ] && exit 0
  sleep 1
done
for pid in $alive; do echo "stop-worktree-procs: $pid did not stop, KILL"; kill -9 "$pid" 2>/dev/null; done
exit 0
