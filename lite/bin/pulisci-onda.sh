#!/usr/bin/env bash
# Toglie da main i file di un'onda finita, con una PR mergiata da merge-pr.sh.
#   pulisci-onda.sh <slug> <onda> <PR>...   i task dell'onda (dal piano in tasks/<slug>/INDEX.md);
#                                           se è l'ultima onda, tutto tasks/<slug> e docs/features/<slug>
#   pulisci-onda.sh <slug> tutta [<PR>...]  tutto tasks/<slug> e docs/features/<slug> (feature chiusa)
#   --prova come primo argomento: stampa i controlli e i file, non scrive niente.
# Si ferma, senza toccare niente, se una PR data non è MERGED, se le PR sono meno dei task
# dell'onda, se c'è una PR aperta con lo slug nel branch, o se un task non ha il suo file.
# Si lancia dal checkout principale (lo usa merge-pr.sh). I controlli del progetto
# (scripts/pre-merge.sh) li lancia merge-pr.sh: se sono rossi la PR resta aperta.
set -euo pipefail

bin=$(cd "$(dirname "$0")" && pwd)
. "$bin/piano.sh"

die() { echo "pulisci-onda: $1" >&2; exit "${2:-1}"; }

prova=
if [ "${1:-}" = "--prova" ]; then prova=1; shift; fi
slug="${1:-}"; onda="${2:-}"
[ -n "$slug" ] && [ -n "$onda" ] || die "uso: pulisci-onda.sh [--prova] <slug> <onda|tutta> <PR>..."
shift 2
case "$slug" in *[!a-zA-Z0-9._-]*|.*) die "slug non valido: $slug" ;; esac
case "$onda" in tutta) ;; *[!0-9]*|"") die "onda non valida: $onda (un numero o «tutta»)" ;; esac
[ "$onda" = tutta ] || [ $# -gt 0 ] || die "servono le PR dell'onda $onda"

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "non sei in un repo git"
repo=$(dirname "$common")
cd "$repo"
git fetch -q --prune origin

# 1. Le PR date sono mergiate; nessuna PR aperta ha lo slug nel branch.
for pr in "$@"; do
  state=$(gh pr view "$pr" --json state -q .state) || die "PR $pr non trovata"
  [ "$state" = MERGED ] || die "la PR $pr è $state, non MERGED"
done
aperte=$(gh pr list --state open --limit 200 --json number,headRefName \
  -q ".[] | select(.headRefName | contains(\"$slug\")) | \"#\(.number) \(.headRefName)\"")
[ -z "$aperte" ] || die "PR aperte su $slug: $(echo "$aperte" | tr '\n' ' ')"

# 2. I file da togliere, letti da origin/main.
esiste() { git cat-file -e "origin/main:$1" 2>/dev/null; }
tutta() { for p in "tasks/$slug" "docs/features/$slug"; do if esiste "$p"; then echo "$p"; fi; done; }
if [ "$onda" = tutta ]; then
  paths=$(tutta)
else
  index="tasks/$slug/INDEX.md"
  esiste "$index" || die "manca $index su main: senza piano non so quali task sono dell'onda"
  piano=$(git show "origin/main:$index" | piano_righe)
  ultima=$(echo "$piano" | awk '{print $1}' | sort -n | tail -1)
  ids=$(echo "$piano" | awk -v o="$onda" '$1 == o {print $2}')
  [ -n "$ids" ] || die "l'onda $onda non è nel piano di $index"
  n=$(echo "$ids" | wc -l | tr -d ' ')
  [ $# -ge "$n" ] || die "l'onda $onda ha $n task ($(echo $ids)) ma le PR date sono $#"
  if [ "$onda" = "$ultima" ]; then
    paths=$(tutta)
  else
    files=$(git ls-tree --name-only "origin/main" "tasks/$slug/")
    paths=
    for id in $ids; do
      f=$(echo "$files" | awk -v a="tasks/$slug/$id.md" -v b="tasks/$slug/$id-" '$0 == a || (index($0, b) == 1 && /\.md$/)')
      [ "$(echo "$f" | grep -c .)" = 1 ] || die "il task $id non ha un solo file in tasks/$slug/: '$(echo $f)'"
      paths=$(printf '%s\n%s' "$paths" "$f")
    done
  fi
fi
paths=$(echo "$paths" | grep . || true)
[ -n "$paths" ] || die "niente da togliere per $slug onda $onda: già tolto?"

echo "pulisci-onda: $slug onda $onda, PR controllate: ${*:-nessuna}"
echo "$paths" | sed 's/^/  - /'
[ -z "$prova" ] || exit 0

# 3. Branch, commit, PR, merge con i controlli del progetto.
branch="docs/pulizia-$slug-onda-$onda"
wt=$("$bin/worktree-new.sh" "$branch" | tail -1)
echo "$paths" | while IFS= read -r p; do git -C "$wt" rm -r -q -- "$p"; done
msg="docs(pulizia): tolti i file di $slug, onda $onda"
body="Onda $onda di \`$slug\` mergiata (PR: ${*:-nessuna}). Tolti:
$(echo "$paths" | sed 's/^/- `/; s/$/`/')

Restano nella storia di git."
git -C "$wt" commit -q -m "$msg" -m "$body"
git -C "$wt" push -q -u origin "$branch"
pr=$(gh pr create --head "$branch" --base main --title "$msg" --body "$body" | grep -o '[0-9]*$')
echo "pulisci-onda: PR $pr aperta, merge…"
"$bin/merge-pr.sh" "$pr"
