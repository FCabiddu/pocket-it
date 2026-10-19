#!/usr/bin/env bash
# Rebuilds ~/.claude/skills as a directory of symlinks to every pack's skills (every */.claude/skills/*).
set -euo pipefail
HUB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; DEST="$HOME/.claude/skills"
[[ -L "$DEST" ]] && rm "$DEST"; mkdir -p "$DEST"
find "$DEST" -maxdepth 1 -type l -exec rm {} +
n=0
for s in "$HUB"/*/.claude/skills/*/; do
  [[ -f "$s/SKILL.md" ]] || continue
  name=$(basename "$s"); ln -s "${s%/}" "$DEST/$name"; n=$((n+1))
done
echo "linked $n skills into $DEST"; ls "$DEST"
