#!/usr/bin/env bash
# Mergia una PR approvata e pulisce tutto, nell'ordine giusto:
#   -. si ferma se il branch porta l'ID di un task (T10, E2E-3, R19) e il corpo della PR non lo nomina;
#   -. si ferma se la PR porta un'onda (onda/*) su main senza lo stato «security» = success
#      sul commit di testa (sicurezza-ok.sh, dopo il SICUREZZA OK dell'agente security);
#   -. si ferma se la PR aggiunge o cambia file in tasks/<slug>/ e il piano tasks/<slug>/INDEX.md
#      manca o non ha righe che pulisci-onda.sh sa leggere (piano.sh);
#   0. lancia scripts/pre-merge.sh del progetto sulla PR unita alla base, con
#      PRE_MERGE_BASE=<base>, e si ferma se è rosso, se la PR va in conflitto o se lo
#      script manca (modello: lite/templates/pre-merge.sh);
#   1. rimuove i worktree del branch e rev-<PR> (si ferma se il worktree ha modifiche non committate),
#      dopo aver fermato i processi rimasti accesi dentro (stop-worktree-procs.sh);
#   2. merge e cancellazione del branch remoto: squash, ma merge vero se la base è onda/*
#      (lo squash appiattirebbe il merge di main fatto nel branch, e l'onda andrebbe
#      in conflitto con main);
#   3. controlla che il branch remoto non ci sia più;
#   4. cancella il branch locale;
#   5. fetch, main locale in pari (--ff-only), worktree prune.
#   I comandi verso GitHub (gh, git fetch/push/ls-remote) si ripetono se cade la rete (rete.sh).
#   merge-pr.sh <PR>     (da dentro il repo)
set -euo pipefail

bin=$(cd "$(dirname "$0")" && pwd)   # prima del cd nel repo: $0 può essere relativo
. "$bin/piano.sh"
. "$bin/rete.sh"

die() { echo "merge-pr: $1" >&2; exit "${2:-1}"; }

pr="${1:-}"; [ -n "$pr" ] || die "uso: merge-pr.sh <PR>"
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "non sei in un repo git"
repo=$(dirname "$common")
root="$repo/.claude/worktrees"
cd "$repo"

read -r state branch base head < <(rete gh pr view "$pr" --json state,headRefName,baseRefName,headRefOid -q '.state + " " + .headRefName + " " + .baseRefName + " " + .headRefOid')
[ "$state" = "OPEN" ] || die "la PR $pr è $state, non OPEN"

# Il corpo è della PR giusta: se il branch porta l'ID di un task (feat/<x>-T10-…,
# test/<x>-E2E-3, fix/<x>-R19-…), il corpo deve nominarlo. Un corpo copiato da un
# altro task fa decidere il reviewer sui risultati sbagliati.
task=$(sed -nE 's#^.*[/-](E2E-[0-9]+|[TR][0-9]+[a-z]?)(-.*)?$#\1#p' <<< "$branch")
if [ -n "$task" ]; then
  body=$(rete gh pr view "$pr" --json body -q .body)
  grep -qwF -- "$task" <<< "$body" \
    || die "il corpo della PR $pr non nomina il task $task del branch $branch: è il corpo di un'altra PR? Correggilo (gh pr edit $pr --body-file …) e rilancia"
fi

# Un'onda arriva su main solo con l'ok dell'agente security sul commit che si mergia
# (stato «security» messo da sicurezza-ok.sh): un commit aggiunto dopo l'ok chiede un nuovo controllo.
if [ "$base" = main ] && [ "${branch#onda/}" != "$branch" ]; then
  sec=$(rete gh api "repos/{owner}/{repo}/commits/$head/statuses" -q '[.[] | select(.context == "security")][0].state // ""')
  [ "$sec" = success ] || die "l'onda $branch non ha l'ok dell'agente security sul commit ${head:0:8}: lancia security (lavoro Onda), poi sicurezza-ok.sh $pr"
fi

# Toglie le cartelle rimaste vuote tra il worktree rimosso e .claude/worktrees.
prune_parents() { local d; d=$(dirname "$1"); while [ "$d" != "$root" ] && [ "${d#"$root"/}" != "$d" ] && rmdir "$d" 2>/dev/null; do d=$(dirname "$d"); done; }

# 0. Controlli del progetto: scripts/pre-merge.sh gira sul codice della PR unito alla
#    base, in un worktree temporaneo. Rosso, conflitto o script assente: niente merge.
ref="refs/merge-pr/$pr"
check="$root/pre-merge-$pr"
remove_check() { if [ -e "$check" ]; then git worktree remove --force "$check"; prune_parents "$check"; fi; }
cleanup_check() { remove_check; git update-ref -d "$ref" 2>/dev/null || true; }
rete git fetch -q origin "$base" "+refs/pull/$pr/head:$ref"
if git cat-file -e "$ref:scripts/pre-merge.sh" 2>/dev/null || git cat-file -e "origin/$base:scripts/pre-merge.sh" 2>/dev/null; then
  trap 'rc=$?; cleanup_check; exit $rc' EXIT
  remove_check
  git worktree add -q --detach "$check" "$ref"
  git -C "$check" -c user.name=merge-pr -c user.email=merge-pr@localhost merge -q --no-edit "origin/$base" \
    || die "la PR $pr va in conflitto con $base: fai il merge di $base nel branch"
  # Il piano dei task si controlla quando entra, non a fine onda in pulisci-onda.sh.
  for slug in $(git -C "$check" diff --name-only --diff-filter=d "origin/$base" HEAD -- tasks/ | awk -F/ 'NF > 2 { print $2 }' | sort -u); do
    errore=$(piano_controlla "$check" "$slug")
    [ -z "$errore" ] || die "PR $pr: $errore. Il task-writer lo corregge sul branch, poi rilancia"
  done
  # Una PR che cambia le dipendenze non si controlla con i node_modules del checkout
  # principale (sono quelli della base): npm ci installa quelli della PR.
  links="node_modules .env.local"
  if [ -e "$check/package-lock.json" ] && ! git diff --quiet "origin/$base" "$ref" -- package.json package-lock.json; then
    echo "merge-pr: la PR $pr cambia le dipendenze, npm ci nel worktree di controllo…"
    (cd "$check" && npm ci --no-audit --no-fund --loglevel=error >/dev/null) || die "npm ci fallito sulla PR $pr"
    links=".env.local"
  fi
  for f in $links; do
    if [ -e "$repo/$f" ] && [ ! -e "$check/$f" ]; then ln -s "$repo/$f" "$check/$f"; fi
  done
  echo "merge-pr: scripts/pre-merge.sh sulla PR $pr unita a ${base}…"
  (cd "$check" && PRE_MERGE_BASE="$base" bash scripts/pre-merge.sh) || die "scripts/pre-merge.sh è rosso sulla PR $pr: merge fermato"
  cleanup_check
  trap - EXIT
else
  git update-ref -d "$ref"
  die "il progetto non ha scripts/pre-merge.sh: senza controlli non si mergia. Lo crea l'architect da $bin/../templates/pre-merge.sh (progetto-pronto.sh dice cosa manca)"
fi

# 1. Worktree: quelli sul branch della PR, più rev-<PR>.
paths=$(git worktree list --porcelain | awk -v b="refs/heads/$branch" '/^worktree /{p=substr($0,10)} $0=="branch " b {print p}')
[ -e "$root/rev-$pr" ] && paths=$(printf '%s\n%s' "$paths" "$root/rev-$pr")
while IFS= read -r p; do
  [ -n "$p" ] || continue
  [ "$p" != "$repo" ] || die "il branch $branch è in uso nel checkout principale"
  if [ "$p" != "$root/rev-$pr" ] && [ -n "$(git -C "$p" status --porcelain --untracked-files=no)" ]; then
    die "$p ha modifiche non committate: fermati e riferisci"
  fi
  bash "$bin/stop-worktree-procs.sh" "$p"
  git worktree remove --force "$p"   # --force toglie solo file non tracciati (test-results, link)
  prune_parents "$p"
done <<< "$paths"

# 2. Merge.
case "$base" in onda/*) how=--merge ;; *) how=--squash ;; esac
# Se la rete cade dopo il merge, il nuovo tentativo dice «già mergiata»: decide lo stato.
rete gh pr merge "$pr" "$how" --delete-branch >/dev/null || true
merged=$(rete gh pr view "$pr" --json state -q .state)
[ "$merged" = "MERGED" ] || die "la PR $pr non risulta mergiata"
if [ "$how" = --merge ]; then
  rete git fetch -q origin "$base"
  git merge-base --is-ancestor "$head" "origin/$base" || die "merge vero atteso: $head non è antenato di origin/$base"
fi

# 3. Branch remoto.
remoto=$(rete git ls-remote --heads origin "$branch")
if [ -n "$remoto" ]; then
  rete git push -q origin --delete "$branch"
fi
remoto=$(rete git ls-remote --heads origin "$branch")
[ -z "$remoto" ] || die "il branch remoto $branch è ancora presente"

# 4. Branch locale.
if git show-ref -q --verify "refs/heads/$branch"; then git branch -q -D "$branch"; fi

# 5. Base locale in pari.
rete git fetch -q --prune origin
if [ "$(git branch --show-current)" = "$base" ]; then git merge -q --ff-only "origin/$base"; fi
git worktree prune

echo "PR $pr mergiata; $base a $(git rev-parse --short "origin/$base")"
