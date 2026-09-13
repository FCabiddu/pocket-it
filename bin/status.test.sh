#!/usr/bin/env bash
# Self-test for status.sh's worktrees line against a scratch repo: every linked worktree is named by its branch, with
# " (locked)" beside the name — never in place of it — for a locked one (worktree.sh locks every agent worktree, PI-31);
# a detached worktree reads "detached"; no line at all with the main checkout alone.
cd "$(dirname "$0")" || exit 2
SCRIPT="$PWD/status.sh"
S=$(mktemp -d "${TMPDIR:-/tmp}/status-test.XXXXXX")
trap 'rm -rf "$S"' EXIT;
fail=0
ok(){ if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
q(){ "$@" >/dev/null 2>&1; }
mkdir -p "$S/bin"; printf '#!/usr/bin/env bash\nexit 1\n' > "$S/bin/gh"; chmod +x "$S/bin/gh"; export PATH="$S/bin:$PATH"   # no network, no PR lines

M="$S/main"; q git init -q -b main "$M"; echo base > "$M/f"; q git -C "$M" add f; q git -C "$M" commit -qm base
line(){ (cd "$M" && bash "$SCRIPT" 2>/dev/null) | grep '^worktrees:'; }
ok "main checkout alone: no worktrees line" "[[ -z \"\$(line)\" ]]"

q git -C "$M" worktree add -q -b task/locked-one "$S/wt-locked" main
q git -C "$M" worktree lock --reason "pocket-it: agent worktree for task/locked-one since 2026-01-01T00:00Z" "$S/wt-locked"
q git -C "$M" worktree add -q -b task/free "$S/wt-free" main
q git -C "$M" worktree add -q --detach "$S/wt-detached" main
q git -C "$M" worktree add -q -b task/nolockreason "$S/wt-noreason" main; q git -C "$M" worktree lock "$S/wt-noreason"
L=$(line)
ok "count of linked worktrees" "[[ \"$L\" == 'worktrees: 4 ('* ]]"
ok "locked worktree: branch name kept, (locked) beside it" "[[ \"$L\" == *'task/locked-one (locked)'* ]]"
ok "lock without a reason: branch name kept, (locked) beside it" "[[ \"$L\" == *'task/nolockreason (locked)'* ]]"
ok "unlocked worktree: branch name alone" "[[ \"$L\" == *'task/free,'* || \"$L\" == *'task/free)' ]] && [[ \"$L\" != *'task/free (locked)'* ]]"
ok "detached worktree: reads detached" "[[ \"$L\" == *detached* ]]"
names(){ local x="${1#worktrees: * (}"; tr ',' '\n' <<<"${x%)}"; }   # one entry per line
ok "every entry is a name, optionally followed by (locked) — the word never stands in for a name" "[[ \$(names \"$L\" | grep -cvE '^(task/[a-z-]+|detached)( \\(locked\\))?\$') -eq 0 && \$(names \"$L\" | wc -l | tr -d ' ') -eq 4 ]]"
ok "whole line" "[[ \"$L\" == 'worktrees: 4 (detached,task/free,task/locked-one (locked),task/nolockreason (locked))' ]]"
q git -C "$M" worktree unlock "$S/wt-locked"
ok "after unlock the marker goes, the name stays" "[[ \"\$(line)\" == 'worktrees: 4 (detached,task/free,task/locked-one,task/nolockreason (locked))' ]]"
exit $fail
