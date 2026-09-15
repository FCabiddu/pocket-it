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

# --- PI-15: the handoff lines go through bin/handoff.sh's read-only composer, never a direct awk/grep on
# docs/SESSION_HANDOFF.md — see .claude/agents/shared/implementing-common.md §3 and the TAD's AC1 grep.

# AC3 — a repo with no memory at all (no frozen file, no fragment) prints one line and touches nothing.
N="$S/nomem"; q git init -q -b main "$N"; echo base > "$N/f"; q git -C "$N" add f; q git -C "$N" commit -qm base
before_nomem=$(cd "$N" && git status --porcelain)
out_nomem=$(cd "$N" && bash "$SCRIPT" 2>/dev/null); rc_nomem=$?
after_nomem=$(cd "$N" && git status --porcelain)
ok "AC3 — no memory: exact single line" "[[ \"\$(grep '^handoff' <<<\"\$out_nomem\")\" == 'handoff: nessuna memoria' ]]"
ok "AC3 — no memory: exits 0" "[[ \$rc_nomem -eq 0 ]]"
ok "AC3 — no memory: no docs/ created, git status unchanged" "[[ ! -d \"$N/docs\" && \"\$before_nomem\" == \"\$after_nomem\" ]]"

# AC2 — with the frozen file present, the two handoff lines match byte-for-byte what the pre-task raw
# awk extraction produced (the oracle: the same awk this repo ran before the task, not status.sh's own code).
F="$S/withmem"; q git init -q -b main "$F"; echo base > "$F/f"; q git -C "$F" add f; q git -C "$F" commit -qm base
mkdir -p "$F/docs"
cat > "$F/docs/SESSION_HANDOFF.md" <<'EOF'
# Session handoff

## Fatti che non scadono
- fact one
- fact two

## Log (più recente in alto, ultime 40 righe)
- 2026-09-01 event one
- 2026-08-31 event two
- 2026-08-30 event three
- 2026-08-29 event four
EOF
exp_facts=$(awk '/^## Fatti/{f=1;next} /^## /{f=0} f && /^- /{print "  "$0}' "$F/docs/SESSION_HANDOFF.md" | head -8)
exp_log=$(awk '/^## Log/{f=1;next} f && /^- /{print "  "$0}' "$F/docs/SESSION_HANDOFF.md" | head -4)
out_mem=$(cd "$F" && bash "$SCRIPT" 2>/dev/null)
got_facts=$(sed -n '/^handoff facts:/,/^handoff log/p' <<<"$out_mem" | sed '1d;$d')
got_log=$(sed -n '/^handoff log (last 4):/,$p' <<<"$out_mem" | sed '1d')
ok "AC2 — facts line identical to the pre-task raw-awk extraction" "[[ \"\$got_facts\" == \"\$exp_facts\" ]]"
ok "AC2 — log (last 4) line identical to the pre-task raw-awk extraction" "[[ \"\$got_log\" == \"\$exp_log\" ]]"

# Forward-compat: memory made only of a fragment under docs/handoff/** (no frozen file at all, the PI-16
# shape) is still detected as memory, never "nessuna memoria" — a status.sh reverted to checking only
# `-f docs/SESSION_HANDOFF.md` goes red here.
G="$S/fragonly"; q git init -q -b main "$G"; echo base > "$G/f"; q git -C "$G" add f; q git -C "$G" commit -qm base
mkdir -p "$G/docs/handoff/2026-09"
cat > "$G/docs/handoff/2026-09/20260901T000000Z-x-a1a1.md" <<'EOF'
## Fatti
- a fact from a fragment

## Log
- 2026-09-01 an event from a fragment
EOF
out_frag=$(cd "$G" && bash "$SCRIPT" 2>/dev/null)
ok "fragment-only memory (no frozen file): detected, not 'nessuna memoria'" "[[ \"\$out_frag\" == *'handoff facts:'* && \"\$out_frag\" != *'nessuna memoria'* ]]"
ok "fragment-only memory: the fragment's fact is shown" "[[ \"\$out_frag\" == *'a fact from a fragment'* ]]"

exit $fail
