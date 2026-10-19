#!/usr/bin/env bash
# Test cases of worktree-new.sh (git hooks in the worktree): `bash lite/bin/worktree-new-cases.sh`.
# Exits with 1 if a case fails.
bin=$(cd "$(dirname "$0")" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P); fail=0
c() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (expected $2, got $3)"; fail=1; fi; }
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }

# Repo with origin and husky-style hooks: relative core.hooksPath, ignored folder that exists only here.
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
c "worktree created"                   "$tmp/repo/.claude/worktrees/prova" "$wt"
echo y > "$wt/b"; g -C "$wt" add b; g -C "$wt" commit -q -m b
c "the pre-commit runs in the worktree" "yes" "$([ -e "$wt/hook-girato" ] && echo yes || echo no)"
echo punto > "$wt/NOTE.md"
c "NOTE.md in the worktree is not untracked" "" "$(g -C "$wt" status --porcelain | grep NOTE.md || true)"
c "NOTE.md excluded only once"         1 "$(grep -cx NOTE.md "$tmp/repo/.git/info/exclude")"
rm -f "$wt/hook-girato"
c "the hooks folder is not untracked" "" "$(g -C "$wt" status --porcelain | grep -v '^?? hook-girato' || true)"
wt2=$(cd "$tmp/repo" && bash "$bin/worktree-new.sh" prova 2>/dev/null | tail -1)
c "run again: resumes the worktree"    "$wt" "$wt2"

# Without core.hooksPath it creates nothing.
g -C "$tmp/repo" config --unset core.hooksPath
wt3=$(cd "$tmp/repo" && bash "$bin/worktree-new.sh" senza-hook 2>/dev/null | tail -1)
c "without hooksPath: no .husky/_"     "no" "$([ -e "$wt3/.husky/_" ] && echo yes || echo no)"
c "NOTE.md excluded only once even after three runs" 1 "$(grep -cx NOTE.md "$tmp/repo/.git/info/exclude")"

rm -rf "$tmp"
exit $fail
