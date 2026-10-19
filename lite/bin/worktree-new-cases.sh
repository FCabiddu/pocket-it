#!/usr/bin/env bash
# Casi di prova di worktree-new.sh (hook di git nel worktree): `bash lite/bin/worktree-new-cases.sh`.
# Esce con 1 se un caso fallisce.
bin=$(cd "$(dirname "$0")" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P); fail=0
c() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (atteso $2, ottenuto $3)"; fail=1; fi; }
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }

# Repo con origin e hook alla husky: core.hooksPath relativo, cartella ignorata che esiste solo qui.
g init -q --bare "$tmp/origin.git"
g init -q "$tmp/repo"
mkdir -p "$tmp/repo/.husky/_"
printf '*\n' > "$tmp/repo/.husky/_/.gitignore"
printf '#!/bin/sh\ntouch "$(git rev-parse --show-toplevel)/hook-girato"\n' > "$tmp/repo/.husky/_/pre-commit"
chmod +x "$tmp/repo/.husky/_/pre-commit"
g -C "$tmp/repo" config core.hooksPath .husky/_
echo x > "$tmp/repo/a"; g -C "$tmp/repo" add a; g -C "$tmp/repo" commit -q -m a
rm -f "$tmp/repo/hook-girato"
g -C "$tmp/repo" remote add origin "$tmp/origin.git"; g -C "$tmp/repo" push -q origin main

wt=$(cd "$tmp/repo" && bash "$bin/worktree-new.sh" prova 2>/dev/null | tail -1)
c "worktree creato"                    "$tmp/repo/.claude/worktrees/prova" "$wt"
echo y > "$wt/b"; g -C "$wt" add b; g -C "$wt" commit -q -m b
c "il pre-commit gira nel worktree"    "si" "$([ -e "$wt/hook-girato" ] && echo si || echo no)"
echo punto > "$wt/NOTE.md"
c "NOTE.md nel worktree non è untracked" "" "$(g -C "$wt" status --porcelain | grep NOTE.md || true)"
c "NOTE.md escluso una volta sola"     1 "$(grep -cx NOTE.md "$tmp/repo/.git/info/exclude")"
rm -f "$wt/hook-girato"
c "la cartella degli hook non è untracked" "" "$(g -C "$wt" status --porcelain | grep -v '^?? hook-girato' || true)"
wt2=$(cd "$tmp/repo" && bash "$bin/worktree-new.sh" prova 2>/dev/null | tail -1)
c "rilanciato: riprende il worktree"   "$wt" "$wt2"

# Senza core.hooksPath non crea niente.
g -C "$tmp/repo" config --unset core.hooksPath
wt3=$(cd "$tmp/repo" && bash "$bin/worktree-new.sh" senza-hook 2>/dev/null | tail -1)
c "senza hooksPath: niente .husky/_"   "no" "$([ -e "$wt3/.husky/_" ] && echo si || echo no)"
c "NOTE.md escluso una volta sola anche dopo tre lanci" 1 "$(grep -cx NOTE.md "$tmp/repo/.git/info/exclude")"

rm -rf "$tmp"
exit $fail
