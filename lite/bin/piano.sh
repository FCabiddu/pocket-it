# The task plan of a feature: tasks/<slug>/INDEX.md, one table row per task,
# `| <onda> | <ID> (<tipo>) | <cosa fa> | <design> |`. A single source for who reads it
# (pulisci-onda.sh) and for who checks it before the merge (merge-pr.sh).
#   source piano.sh

# Plan rows from stdin: «<onda> <ID>», one per task.
piano_righe() { awk -F'|' '$2 ~ /^ *[0-9]+ *$/ { gsub(/ /, "", $2); split($3, w, " "); print $2, w[1] }'; }

# Checks the plan of <dir>/tasks/<slug>: prints nothing if it is fine, otherwise the reason.
piano_controlla() {
  local dir=$1 slug=$2 f="$1/tasks/$2/INDEX.md"
  if [ ! -f "$f" ]; then
    echo "tasks/$slug/INDEX.md is missing (that is the plan's name: there is $(cd "$dir/tasks/$slug" && ls | tr '\n' ' '))"
  elif [ -z "$(piano_righe < "$f")" ]; then
    echo "tasks/$slug/INDEX.md has no plan rows «| <onda> | <ID> (<tipo>) | <cosa fa> | <design> |»"
  fi
  return 0   # under set -e, `x=$(piano_controlla …)` must not exit when it is fine
}
