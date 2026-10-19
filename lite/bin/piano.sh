# Il piano dei task di una feature: tasks/<slug>/INDEX.md, una riga di tabella per task,
# `| <onda> | <ID> (<tipo>) | <cosa fa> | <design> |`. Una sola fonte per chi lo legge
# (pulisci-onda.sh) e per chi lo controlla prima del merge (merge-pr.sh).
#   source piano.sh

# Righe del piano da stdin: «<onda> <ID>», una per task.
piano_righe() { awk -F'|' '$2 ~ /^ *[0-9]+ *$/ { gsub(/ /, "", $2); split($3, w, " "); print $2, w[1] }'; }

# Controlla il piano di <dir>/tasks/<slug>: niente stampato se va bene, altrimenti il motivo.
piano_controlla() {
  local dir=$1 slug=$2 f="$1/tasks/$2/INDEX.md"
  if [ ! -f "$f" ]; then
    echo "manca tasks/$slug/INDEX.md (il piano si chiama così: c'è $(cd "$dir/tasks/$slug" && ls | tr '\n' ' '))"
  elif [ -z "$(piano_righe < "$f")" ]; then
    echo "tasks/$slug/INDEX.md non ha righe di piano «| <onda> | <ID> (<tipo>) | <cosa fa> | <design> |»"
  fi
  return 0   # sotto set -e, `x=$(piano_controlla …)` non deve uscire quando va bene
}
