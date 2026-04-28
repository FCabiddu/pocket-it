#!/usr/bin/env bash
# Installs the pre-push security hook into your project's .git/hooks/.
# Run this once after cloning: bash .claude/hooks/install.sh

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: not inside a git repository." >&2
  exit 1
fi

SRC="$REPO_ROOT/.claude/hooks/pre-push"
DEST="$REPO_ROOT/.git/hooks/pre-push"

if [[ ! -f "$SRC" ]]; then
  echo "Error: $SRC not found." >&2
  exit 1
fi

cp "$SRC" "$DEST"
chmod +x "$DEST"

echo "Installed: .git/hooks/pre-push"
