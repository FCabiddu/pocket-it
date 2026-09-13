#!/usr/bin/env bash
# pocket-it install-live — creates or updates the INSTALLED copy of pocket-it: the tree that hooks, skills and
# agents are read from, kept apart from the development checkout where agents write. A write that lands in a
# development checkout by mistake must never change what every session runs.
#
# WHEN TO RUN: after every merge into the base branch of pocket-it (main), so that reviewed fixes come into
# use. Nothing reaches the installed copy until this runs, and nothing else should ever write to it.
#
# Usage: bash install-live.sh [--dest DIR] [--remote URL] [--branch NAME]
#   --dest    the installed copy (default: $POCKET_IT_LIVE, else $HOME/.claude/pocket-it-live)
#   --remote  the published repository. First install: default is the origin URL of the checkout this script
#             is run from. Update: the installed copy's own origin; a different --remote is refused.
#   --branch  the base branch to install (default: main)
#
# Source: only the published branch, through git clone/fetch of <remote> <branch> — never files from a working
# tree, so uncommitted or unpushed changes in any development checkout cannot arrive. A remote that is a local
# repository with a working tree (a checkout rather than a published repository) is refused.
# First install: clone into a temporary sibling, validate, rename into place.
# Update: fast-forward only. Refuses, changing nothing, if the installed copy has local modifications (tracked or
# untracked), is not on <branch>, has linked worktrees (a development checkout), is itself a linked worktree,
# or is not an ancestor of the published branch (local commits, or the published branch was rewritten).
# Before anything moves, the target commit is validated: .claude/hooks/guard.sh, .claude/agents, .claude/skills
# and bin/install-live.sh exist, and every *.sh under .claude/hooks and bin parses (bash -n). A published
# commit that fails validation is refused and the last working copy stays in use.
# Exit 0 installed, updated or already up to date · 1 refused or failed (installed copy left as it was) · 2 usage.
set -uo pipefail

REQUIRED_PATHS=".claude/hooks/guard.sh .claude/agents .claude/skills bin/install-live.sh"

usage() {
  echo "usage: install-live.sh [--dest DIR] [--remote URL] [--branch NAME]" >&2
  echo "Run it after every merge into the base branch of pocket-it, so reviewed fixes come into use." >&2
  exit 2
}
say()  { echo "install-live.sh: $*"; }
when() { say "run this again after every merge into $BRANCH of pocket-it, so reviewed fixes come into use."; }
refuse() {
  echo "install-live.sh: REFUSED: $*" >&2
  echo "install-live.sh: nothing was changed; the installed copy is as it was." >&2
  exit 1
}

# A published repository is a URL or a bare repository. A local path with a working tree is a checkout, and a
# checkout is exactly what must never be installed from.
check_remote() {
  local path="${1#file://}"
  if [[ -d "$path" ]] && [[ "$(git -C "$path" rev-parse --is-bare-repository 2>/dev/null)" == "false" ]]; then
    refuse "remote $1 is a local checkout with a working tree, not a published repository — install from its origin instead"
  fi
}

# validate_tree <repo> <rev>: the commit about to be installed carries what the hooks, skills and agents need,
# and its shell scripts parse. Runs against the git object, before any file in the installed copy changes.
validate_tree() {
  local repo="$1" rev="$2" p f bad=""
  for p in $REQUIRED_PATHS; do
    git -C "$repo" cat-file -e "$rev:$p" 2>/dev/null || bad="$bad missing:$p"
  done
  while IFS= read -r f; do
    [[ "$f" == *.sh ]] || continue
    git -C "$repo" show "$rev:$f" | bash -n 2>/dev/null || bad="$bad syntax:$f"
  done < <(git -C "$repo" ls-tree -r --name-only "$rev" -- .claude/hooks bin 2>/dev/null)
  [[ -z "$bad" ]] && return 0
  echo "install-live.sh: published commit $(git -C "$repo" rev-parse --short "$rev" 2>/dev/null) fails validation:$bad" >&2
  return 1
}

install_fresh() {
  local tmp sha
  if [[ -z "$REMOTE" ]]; then
    REMOTE=$(git -C "$SELF" remote get-url origin 2>/dev/null) \
      || refuse "no --remote given and $SELF has no origin to install from"
  fi
  check_remote "$REMOTE"
  tmp="$DEST.installing.$$"
  rm -rf "$tmp"
  if ! git clone -q --branch "$BRANCH" --single-branch "$REMOTE" "$tmp" >/dev/null 2>&1; then
    rm -rf "$tmp"; refuse "cannot clone branch $BRANCH of $REMOTE"
  fi
  if ! validate_tree "$tmp" HEAD; then
    rm -rf "$tmp"; refuse "the published $BRANCH is not installable"
  fi
  if [[ -e "$DEST" ]]; then
    rm -rf "$tmp"; refuse "$DEST appeared while installing"
  fi
  mv "$tmp" "$DEST" || { rm -rf "$tmp"; refuse "cannot move the new copy into $DEST"; }
  sha=$(git -C "$DEST" rev-parse --short HEAD)
  say "installed $BRANCH@$sha from $REMOTE into $DEST"
  when
}

update() {
  local top common origin cur dirty old new n
  top=$(git -C "$DEST" rev-parse --show-toplevel 2>/dev/null) || refuse "$DEST exists but is not a git repository"
  [[ "$(cd "$top" && pwd -P)" == "$DEST" ]] || refuse "$DEST is inside another repository, not the top of an installed copy"
  common=$(cd "$DEST" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
  [[ "$common" == "$DEST/.git" ]] || refuse "$DEST is a linked worktree of another checkout, not an installed copy"
  n=$(git -C "$DEST" worktree list --porcelain | grep -c '^worktree ')
  [[ "$n" -eq 1 ]] || refuse "$DEST has linked worktrees: it is a development checkout, not an installed copy"
  origin=$(git -C "$DEST" remote get-url origin 2>/dev/null) || refuse "$DEST has no origin remote"
  [[ -z "$REMOTE" || "$REMOTE" == "$origin" ]] || refuse "--remote $REMOTE differs from the installed copy's origin $origin"
  REMOTE="$origin"
  check_remote "$REMOTE"
  cur=$(git -C "$DEST" symbolic-ref -q --short HEAD) || refuse "$DEST is on a detached HEAD, not on $BRANCH"
  [[ "$cur" == "$BRANCH" ]] || refuse "$DEST is on branch $cur, not on $BRANCH"
  dirty=$(git -C "$DEST" status --porcelain --untracked-files=all)
  [[ -z "$dirty" ]] || refuse "$DEST has local modifications — an installed copy is never edited by hand:
$(printf '%s\n' "$dirty" | head -10)"
  old=$(git -C "$DEST" rev-parse HEAD)
  git -C "$DEST" fetch -q origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" >/dev/null 2>&1 \
    || refuse "cannot fetch $BRANCH from $REMOTE"
  new=$(git -C "$DEST" rev-parse "refs/remotes/origin/$BRANCH")
  if [[ "$old" == "$new" ]]; then
    say "already up to date: $BRANCH@${old:0:7} in $DEST"
    when
    return 0
  fi
  git -C "$DEST" merge-base --is-ancestor "$old" "$new" \
    || refuse "not a fast-forward: the installed ${old:0:7} is not an ancestor of the published ${new:0:7} (commits made in the installed copy, or the published $BRANCH was rewritten)"
  validate_tree "$DEST" "$new" || refuse "the published $BRANCH is not installable"
  if ! git -C "$DEST" merge -q --ff-only "$new" >/dev/null 2>&1; then
    echo "install-live.sh: FAILED: fast-forward of $DEST to ${new:0:7} did not complete. State now:" >&2
    git -C "$DEST" status --short | head -10 >&2
    echo "install-live.sh: restore the last working copy with: git -C \"$DEST\" reset -q --hard $old" >&2
    exit 1
  fi
  [[ "$(git -C "$DEST" rev-parse HEAD)" == "$new" ]] || { echo "install-live.sh: FAILED: HEAD is not ${new:0:7} after the fast-forward" >&2; exit 1; }
  n=$(git -C "$DEST" rev-list --count "$old..$new")
  say "updated $DEST: ${old:0:7} → ${new:0:7} ($n commit(s) from $REMOTE $BRANCH)"
  when
}

# Everything runs inside main, parsed in full before the first command: an update rewrites this very file when
# the script is run from the installed copy, and bash reads a script lazily.
main() {
  DEST="${POCKET_IT_LIVE:-$HOME/.claude/pocket-it-live}"; REMOTE=""; BRANCH="main"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dest)   [[ $# -ge 2 && -n "$2" ]] || usage; DEST="$2"; shift 2 ;;
      --remote) [[ $# -ge 2 && -n "$2" ]] || usage; REMOTE="$2"; shift 2 ;;
      --branch) [[ $# -ge 2 && -n "$2" ]] || usage; BRANCH="$2"; shift 2 ;;
      -h|--help) usage ;;
      *) echo "install-live.sh: unknown argument: $1" >&2; usage ;;
    esac
  done
  SELF=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
  mkdir -p "$(dirname "$DEST")" 2>/dev/null || refuse "cannot create the parent folder of $DEST"
  DEST="$(cd "$(dirname "$DEST")" && pwd -P)/$(basename "$DEST")"
  if [[ -e "$DEST" || -L "$DEST" ]]; then
    [[ -L "$DEST" ]] && DEST=$(cd "$DEST" 2>/dev/null && pwd -P || echo "$DEST")
    update
  else
    install_fresh
  fi
}
main "$@"; exit $?
