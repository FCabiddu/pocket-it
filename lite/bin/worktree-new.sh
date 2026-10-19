#!/usr/bin/env bash
# Crea (o riprende) il worktree di un agente e ne stampa il percorso nell'ultima riga.
#   worktree-new.sh <branch> [base]   worktree del branch in <repo>/.claude/worktrees/<branch>.
#                                     Se il branch esiste (locale o remoto) lo riprende,
#                                     altrimenti lo crea da origin/<base> (default main).
#   worktree-new.sh --review <PR>     worktree del reviewer in <repo>/.claude/worktrees/rev-<PR>:
#                                     il branch della PR con la base già mergiata dentro.
#                                     Rilanciato, lo ricrea da capo (per riverificare dopo una correzione).
# Si lancia da dentro il repo (checkout principale o un suo worktree).
set -euo pipefail

die() { echo "worktree-new: $1" >&2; exit "${2:-1}"; }

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "non sei in un repo git"
repo=$(dirname "$common")
root="$repo/.claude/worktrees"

# Un solo worktree alla volta: due «git worktree add» insieme si contendono .git/config.
lock="$common/worktree-new.lock"
got=
for _ in $(seq 60); do if mkdir "$lock" 2>/dev/null; then got=1; break; fi; sleep 1; done
[ -n "$got" ] || die "lock $lock occupato da più di 60s"
trap 'rmdir "$lock" 2>/dev/null || true' EXIT

grep -qxF ".claude/worktrees/" "$common/info/exclude" 2>/dev/null || echo ".claude/worktrees/" >> "$common/info/exclude"
# NOTE.md: il punto del lavoro che developer, tester e task-writer tengono nel worktree, mai committato.
grep -qxF "NOTE.md" "$common/info/exclude" 2>/dev/null || echo "NOTE.md" >> "$common/info/exclude"

git -C "$repo" fetch -q --prune origin

if [ "${1:-}" = "--review" ]; then
  pr="${2:-}"; [ -n "$pr" ] || die "uso: worktree-new.sh --review <PR>"
  info=$(cd "$repo" && gh pr view "$pr" --json headRefName,baseRefName -q '.headRefName + " " + .baseRefName' 2>/dev/null) \
    || die "PR $pr non trovata nel repo $repo: lancia lo script da dentro il repo del progetto, per esempio (cd <Worktree> && worktree-new.sh --review $pr)" 2
  read -r branch base <<< "$info"
  path="$root/rev-$pr"
  if [ -e "$path" ]; then git -C "$repo" worktree remove --force "$path"; fi
  git -C "$repo" worktree add -q --detach "$path" "origin/$branch"
  if ! git -C "$path" merge -q --no-edit "origin/$base" >/dev/null 2>&1; then
    git -C "$path" merge --abort 2>/dev/null || true
    die "la PR $pr ha conflitti con $base: va aggiornata dal developer" 3
  fi
else
  branch="${1:-}"; [ -n "$branch" ] || die "uso: worktree-new.sh <branch> [base]"
  base="${2:-main}"
  path="$root/$branch"
  if [ ! -e "$path" ]; then
    if git -C "$repo" show-ref -q --verify "refs/heads/$branch"; then
      git -C "$repo" worktree add -q "$path" "$branch"
    elif git -C "$repo" show-ref -q --verify "refs/remotes/origin/$branch"; then
      git -C "$repo" worktree add -q --track -b "$branch" "$path" "origin/$branch"
    else
      git -C "$repo" worktree add -q --no-track -b "$branch" "$path" "origin/$base"
    fi
  fi
fi

# Dipendenze e segreti del checkout principale, con percorso assoluto
# (un branch con «/» aggiunge cartelle: un percorso relativo sbaglia livello).
for f in node_modules .env.local; do
  if [ -e "$repo/$f" ] && [ ! -e "$path/$f" ]; then
    ln -s "$repo/$f" "$path/$f"
    git -C "$path" check-ignore -q "$f" || echo "/$f" >> "$common/info/exclude"
  fi
done

# Hook di git con percorso relativo (husky: .husky/_, cartella ignorata che esiste solo
# nel checkout principale): senza, nel worktree il pre-commit non gira.
hooks=$(git -C "$repo" config --get core.hooksPath || true)
case "$hooks" in
  ""|/*) ;;
  *)
    hooks=${hooks%/}
    if [ -d "$repo/$hooks" ] && [ ! -e "$path/$hooks" ]; then
      mkdir -p "$(dirname "$path/$hooks")"
      ln -s "$repo/$hooks" "$path/$hooks"
      git -C "$path" check-ignore -q "$hooks" || echo "/$hooks" >> "$common/info/exclude"
    fi
    ;;
esac

echo "$path"
