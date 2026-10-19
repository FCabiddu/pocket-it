# The task plan of a feature: tasks/<slug>/INDEX.md, one table row per task,
# `| <wave> | <ID> (<type>) | <what it does> | <design> |`. A single source for who reads it
# (clean-wave.sh) and for who checks it before the merge (merge-pr.sh).
#   source plan.sh

# Plan rows from stdin: «<wave> <ID>», one per task.
plan_rows() { awk -F'|' '$2 ~ /^ *[0-9]+ *$/ { gsub(/ /, "", $2); split($3, w, " "); print $2, w[1] }'; }

# Checks the plan of <dir>/tasks/<slug>: prints nothing if it is fine, otherwise the reason.
plan_check() {
  local dir=$1 slug=$2 f="$1/tasks/$2/INDEX.md"
  if [ ! -f "$f" ]; then
    echo "tasks/$slug/INDEX.md is missing (that is the plan's name: there is $(cd "$dir/tasks/$slug" && ls | tr '\n' ' '))"
  elif [ -z "$(plan_rows < "$f")" ]; then
    echo "tasks/$slug/INDEX.md has no plan rows «| <wave> | <ID> (<type>) | <what it does> | <design> |»"
  fi
  return 0   # under set -e, `x=$(plan_check …)` must not exit when it is fine
}
