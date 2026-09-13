#!/usr/bin/env bash
# pocket-it install-live — creates or updates the INSTALLED copy of pocket-it: the tree that hooks, skills and
# agents are read from, kept apart from the development checkout where agents write. A write that lands in a
# development checkout by mistake must never change what every session runs.
#
# WHEN TO RUN: after every merge into the base branch of pocket-it (main), so that reviewed fixes come into
# use. Nothing reaches the installed copy until this runs, and nothing else should ever write to it.
#
# Usage: bash install-live.sh [--dest DIR] [--remote URL] [--branch NAME] [--rebuild]
#   --dest    the installed copy (default: $POCKET_IT_LIVE, else $HOME/.claude/pocket-it-live)
#   --remote  the published repository. First install: default is the origin URL of the checkout this script
#             is run from. Update: the installed copy's own origin; a different --remote is refused.
#   --branch  the base branch to install (default: main)
#   --rebuild replace a drifted installed copy (local modifications or commits) with a fresh copy of the
#             published branch; the drifted copy is kept aside as <dest>.drifted-<timestamp>
#
# Source: only the published branch, through git clone of <remote> <branch> — never files from a working tree,
# so uncommitted or unpushed changes in any development checkout cannot arrive. A remote that is a local
# repository with a working tree (a checkout rather than a published repository) is refused.
#
# Never rewrites the installed copy in place. The new copy is built beside it (<dest>.next.<pid>), checked, and
# then exchanged with the installed one in a single atomic directory swap (renamex_np RENAME_SWAP on macOS,
# renameat2 RENAME_EXCHANGE on Linux): a hook reading <dest>/.claude/hooks/guard.sh sees the old file or the new
# one, never no file. Without an atomic swap available the script refuses rather than fall back to a gap.
#
# Checks on the new copy, all before the swap: .claude/hooks/guard.sh, .claude/agents, .claude/skills and
# bin/install-live.sh exist; every *.sh under .claude/hooks and bin parses (bash -n); and the new guard.sh
# ANSWERS correctly — it blocks a forbidden command (exit 2) and allows a harmless one (exit 0). A guard that
# lets everything through, or blocks everything (which would lock every session out of Bash), is refused.
#
# Update refuses, changing nothing, if the installed copy has local modifications (tracked or untracked), is not
# on <branch>, has linked worktrees (a development checkout), is itself a linked worktree, or is not an ancestor
# of the published branch (local commits, or the published branch was rewritten) — --rebuild overrides only the
# first and the last two, never the checks on the new copy.
# Exit 0 installed, updated or already up to date · 1 refused or failed (installed copy left as it was) · 2 usage.
set -uo pipefail

REQUIRED_PATHS=".claude/hooks/guard.sh .claude/agents .claude/skills bin/install-live.sh"
GUARD_BLOCK_PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"killall node"}}'
GUARD_ALLOW_PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"ls"}}'

usage() {
  echo "usage: install-live.sh [--dest DIR] [--remote URL] [--branch NAME] [--rebuild]" >&2
  echo "Run it after every merge into the base branch of pocket-it, so reviewed fixes come into use." >&2
  exit 2
}
say()  { echo "install-live.sh: $*"; }
when() { say "run this again after every merge into $BRANCH of pocket-it, so reviewed fixes come into use."; }
refuse() {
  [[ -n "${NEXT:-}" ]] && rm -rf "$NEXT"
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

# check_copy <dir>: the tree about to go live has what hooks, skills and agents need, its scripts parse, and its
# guard answers like a guard. Runs on the copy built beside the installed one, before the swap.
check_copy() {
  local dir="$1" p f rc bad=""
  for p in $REQUIRED_PATHS; do
    [[ -e "$dir/$p" ]] || bad="$bad missing:$p"
  done
  while IFS= read -r f; do
    [[ "$f" == *.sh ]] || continue
    bash -n "$dir/$f" 2>/dev/null || bad="$bad syntax:$f"
  done < <(git -C "$dir" ls-files -- .claude/hooks bin 2>/dev/null)
  if [[ -f "$dir/.claude/hooks/guard.sh" ]]; then
    printf '%s' "$GUARD_BLOCK_PAYLOAD" | bash "$dir/.claude/hooks/guard.sh" >/dev/null 2>&1; rc=$?
    [[ $rc -eq 2 ]] || bad="$bad guard-does-not-block:exit-$rc"
    printf '%s' "$GUARD_ALLOW_PAYLOAD" | bash "$dir/.claude/hooks/guard.sh" >/dev/null 2>&1; rc=$?
    [[ $rc -eq 0 ]] || bad="$bad guard-blocks-harmless-command:exit-$rc"
  fi
  [[ -z "$bad" ]] && return 0
  echo "install-live.sh: published commit $(git -C "$dir" rev-parse --short HEAD 2>/dev/null) fails the checks:$bad" >&2
  return 1
}

# swap_dirs <a> <b>: exchange two directories in one atomic rename. No fallback: a two-step rename leaves a
# moment with no guard.sh, and a missing guard is a guard that lets commands through.
swap_dirs() {
  python3 -c '
import ctypes, os, sys
a, b = os.fsencode(sys.argv[1]), os.fsencode(sys.argv[2])
libc = ctypes.CDLL(None, use_errno=True)
if sys.platform == "darwin":
    r = libc.renamex_np(a, b, ctypes.c_uint(0x2))                    # RENAME_SWAP
elif hasattr(libc, "renameat2"):
    r = libc.renameat2(-100, a, -100, b, ctypes.c_uint(0x2))         # AT_FDCWD, RENAME_EXCHANGE
else:
    sys.stderr.write("no atomic directory swap on this platform\n"); sys.exit(1)
if r != 0:
    sys.stderr.write(os.strerror(ctypes.get_errno()) + "\n"); sys.exit(1)
' "$1" "$2"
}

# build_next: a fresh clone of the published branch beside the installed copy, checked. Sets NEXT.
build_next() {
  NEXT="$DEST.next.$$"
  rm -rf "$NEXT"
  git clone -q --branch "$BRANCH" --single-branch "$REMOTE" "$NEXT" >/dev/null 2>&1 \
    || refuse "cannot clone branch $BRANCH of $REMOTE"
  check_copy "$NEXT" || refuse "the published $BRANCH is not installable"
}

install_fresh() {
  if [[ -z "$REMOTE" ]]; then
    REMOTE=$(git -C "$SELF" remote get-url origin 2>/dev/null) \
      || refuse "no --remote given and $SELF has no origin to install from"
  fi
  check_remote "$REMOTE"
  build_next
  [[ -e "$DEST" ]] && refuse "$DEST appeared while installing"
  mv "$NEXT" "$DEST" || refuse "cannot move the new copy into $DEST"
  NEXT=""
  say "installed $BRANCH@$(git -C "$DEST" rev-parse --short HEAD) from $REMOTE into $DEST"
  when
}

update() {
  local top common origin cur dirty old new n published aside
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
  old=$(git -C "$DEST" rev-parse HEAD)
  if [[ "$REBUILD" -eq 0 ]]; then
    cur=$(git -C "$DEST" symbolic-ref -q --short HEAD) || refuse "$DEST is on a detached HEAD, not on $BRANCH — use --rebuild"
    [[ "$cur" == "$BRANCH" ]] || refuse "$DEST is on branch $cur, not on $BRANCH — use --rebuild"
    dirty=$(git -C "$DEST" status --porcelain --untracked-files=all)
    [[ -z "$dirty" ]] || refuse "$DEST has local modifications — an installed copy is never edited by hand; replace it with --rebuild:
$(printf '%s\n' "$dirty" | head -10)"
    published=$(git ls-remote "$REMOTE" "refs/heads/$BRANCH" 2>/dev/null | cut -f1)
    [[ -n "$published" ]] || refuse "cannot read $BRANCH from $REMOTE"
    if [[ "$published" == "$old" ]]; then
      say "already up to date: $BRANCH@${old:0:7} in $DEST"
      when
      return 0
    fi
  fi
  build_next
  new=$(git -C "$NEXT" rev-parse HEAD)
  if [[ "$REBUILD" -eq 0 ]]; then
    { git -C "$NEXT" cat-file -e "$old^{commit}" 2>/dev/null && git -C "$NEXT" merge-base --is-ancestor "$old" "$new"; } \
      || refuse "not a fast-forward: the installed ${old:0:7} is not an ancestor of the published ${new:0:7} (commits made in the installed copy, or the published $BRANCH was rewritten) — use --rebuild"
  fi
  swap_dirs "$NEXT" "$DEST" || refuse "atomic swap of $NEXT and $DEST failed"
  # $NEXT now holds the previous installed copy
  if [[ "$REBUILD" -eq 1 ]]; then
    aside="$DEST.drifted-$(date +%Y%m%d%H%M%S)"
    mv "$NEXT" "$aside" && say "previous copy kept at $aside"
  else
    rm -rf "$NEXT"
  fi
  NEXT=""
  [[ "$(git -C "$DEST" rev-parse HEAD)" == "$new" ]] || { echo "install-live.sh: FAILED: $DEST is not at ${new:0:7} after the swap" >&2; exit 1; }
  if [[ "$REBUILD" -eq 1 ]]; then
    say "rebuilt $DEST at ${new:0:7} from $REMOTE $BRANCH (was ${old:0:7})"
  else
    n=$(git -C "$DEST" rev-list --count "$old..$new")
    say "updated $DEST: ${old:0:7} → ${new:0:7} ($n commit(s) from $REMOTE $BRANCH)"
  fi
  when
}

# Everything runs inside main, parsed in full before the first command: the script may be run from the copy it
# replaces, and bash reads a script lazily.
main() {
  DEST="${POCKET_IT_LIVE:-$HOME/.claude/pocket-it-live}"; REMOTE=""; BRANCH="main"; REBUILD=0; NEXT=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dest)   [[ $# -ge 2 && -n "$2" ]] || usage; DEST="$2"; shift 2 ;;
      --remote) [[ $# -ge 2 && -n "$2" ]] || usage; REMOTE="$2"; shift 2 ;;
      --branch) [[ $# -ge 2 && -n "$2" ]] || usage; BRANCH="$2"; shift 2 ;;
      --rebuild) REBUILD=1; shift ;;
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
    [[ "$REBUILD" -eq 1 ]] && refuse "--rebuild needs an existing installed copy at $DEST"
    install_fresh
  fi
}
main "$@"; exit $?
