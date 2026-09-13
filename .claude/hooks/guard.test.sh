#!/usr/bin/env bash
# Self-test for guard.sh: each line is "expect|command" where expect is BLOCK or ALLOW.
cd "$(dirname "$0")"
HOOKDIR="$PWD"
fail=0
while IFS='|' read -r expect cmd; do
  [[ -z "$expect" || "$expect" == \#* ]] && continue
  payload=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")
  if printf '%s' "$payload" | bash ./guard.sh >/dev/null 2>&1; then got=ALLOW; else got=BLOCK; fi
  if [[ "$got" == "$expect" ]]; then echo "ok    $got  $cmd"; else echo "FAIL  want $expect got $got  $cmd"; fail=1; fi
done <<'CASES'
BLOCK|gh pr merge 12 --squash
BLOCK|cd repo && gh pr merge --auto 4
BLOCK|git push origin main
BLOCK|git push -u origin main
BLOCK|git push --force origin main
BLOCK|git push origin HEAD:main
BLOCK|pkill -f next-server
BLOCK|killall node
BLOCK|gh variable set APP_STATUS --body prod
BLOCK|sleep 30 && gh pr checks 3
BLOCK|sleep 5; gh pr view 163
ALLOW|gh variable get APP_STATUS >/dev/null 2>&1 || gh variable set APP_STATUS --body dev
ALLOW|git push -u origin task/t-1-2-3-slug
ALLOW|git push -u origin feat/main-menu
ALLOW|git pull --ff-only origin main
ALLOW|git checkout main && git pull origin main
ALLOW|gh pr checks 3 --watch --interval 30
ALLOW|lsof -nP -iTCP:3100 -sTCP:LISTEN -t | xargs -r kill
ALLOW|gh pr ready 12 && gh pr comment 12 --body ok
ALLOW|until gh pr view 3 --json mergeable --jq .mergeable | grep -qv UNKNOWN; do sleep 2; done
ALLOW|git commit -m "docs: explain why pkill/killall and gh pr merge are blocked"
ALLOW|gh pr comment 12 --body "never run git push origin main from an agent"
BLOCK|echo "harmless" && gh pr merge 7
ALLOW|POCKET_IT_USER_MERGE=1 gh pr merge 8 --merge --delete-branch
BLOCK|POCKET_IT_USER_MERGE=0 gh pr merge 8 --merge
BLOCK|git push origin HEAD:main
ALLOW|POCKET_IT_ORCHESTRATOR_PUSH=1 git push origin main
ALLOW|POCKET_IT_ORCHESTRATOR_PUSH=1 git push origin HEAD:main
ALLOW|POCKET_IT_ORCHESTRATOR_PUSH=1 git push -u origin task/pi-10-slug
BLOCK|POCKET_IT_ORCHESTRATOR_PUSH=1 git push --force origin main
BLOCK|POCKET_IT_ORCHESTRATOR_PUSH=1 git push -f origin main
CASES

# --- Fixtures: branch-resolution cases (PI-4). A bare `git push`/`git push origin HEAD` only
# resolves to a block when the branch it actually updates is main/master, so these need real
# git repos checked out on known branches rather than string matching alone.
TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

mk_repo() {
  local dir="$1" branch="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q -b "$branch"
  git -C "$dir" -c user.email=t@t.example -c user.name=test commit -q --allow-empty -m init
}
mk_repo "$TMPROOT/main-repo" main
mk_repo "$TMPROOT/feat-repo" feat/x
mkdir -p "$TMPROOT/not-a-repo" "$TMPROOT/neutral"
MISSING="$TMPROOT/does-not-exist"

expect_case() {
  local expect="$1" cwd="$2" cmd="$3"
  local payload got
  payload=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")
  if (cd "$cwd" && printf '%s' "$payload" | bash "$HOOKDIR/guard.sh") >/dev/null 2>&1; then got=ALLOW; else got=BLOCK; fi
  if [[ "$got" == "$expect" ]]; then echo "ok    $got  [cwd=$(basename "$cwd")] $cmd"; else echo "FAIL  want $expect got $got  [cwd=$(basename "$cwd")] $cmd"; fail=1; fi
}

# AC1 — on branch main, these all resolve to main and must block.
expect_case BLOCK "$TMPROOT/main-repo" "git push"
expect_case BLOCK "$TMPROOT/main-repo" "git push origin HEAD"
expect_case BLOCK "$TMPROOT/main-repo" "git push -u origin HEAD"
expect_case BLOCK "$TMPROOT/main-repo" "git push -q origin HEAD:main"
expect_case BLOCK "$TMPROOT/main-repo" "git push origin HEAD:refs/heads/main"

# AC2 — on branch feat/x, the same forms (plus pushing the branch by name) must pass.
expect_case ALLOW "$TMPROOT/feat-repo" "git push"
expect_case ALLOW "$TMPROOT/feat-repo" "git push origin HEAD"
expect_case ALLOW "$TMPROOT/feat-repo" "git push -u origin HEAD"
expect_case ALLOW "$TMPROOT/feat-repo" "git push -u origin feat/x"

# AC3 — compound commands resolve the branch of the cd target / -C path, not the hook's cwd;
# an unresolvable path falls back to the hook's cwd; a non-repo hook cwd passes.
expect_case BLOCK "$TMPROOT/neutral" "cd $TMPROOT/main-repo && git push origin HEAD"
expect_case ALLOW "$TMPROOT/neutral" "cd $TMPROOT/feat-repo && git push origin HEAD"
expect_case BLOCK "$TMPROOT/neutral" "git -C $TMPROOT/main-repo push origin HEAD"
expect_case ALLOW "$TMPROOT/neutral" "git -C $TMPROOT/feat-repo push origin HEAD"
expect_case BLOCK "$TMPROOT/main-repo" "cd $MISSING && git push origin HEAD"
expect_case ALLOW "$TMPROOT/feat-repo" "cd $MISSING && git push origin HEAD"
expect_case ALLOW "$TMPROOT/not-a-repo" "git push origin HEAD"

# AC4 — force push blocked by name or by current branch being main; allowed on a feature branch.
expect_case BLOCK "$TMPROOT/main-repo" "git push --force"
expect_case BLOCK "$TMPROOT/main-repo" "git push -f origin HEAD"
expect_case BLOCK "$TMPROOT/feat-repo" "git push --force origin main"
expect_case ALLOW "$TMPROOT/feat-repo" "git push -f"

# PI-10 AC1-AC4 — the POCKET_IT_ORCHESTRATOR_PUSH=1 prefix authorizes an implicit push to main
# (bare `git push` resolved from the current branch), but never a force-push, even prefixed.
expect_case BLOCK "$TMPROOT/main-repo" "git push"
expect_case ALLOW "$TMPROOT/main-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push"
expect_case BLOCK "$TMPROOT/main-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push --force"
expect_case BLOCK "$TMPROOT/main-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push -f origin HEAD"
expect_case ALLOW "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push"

# PI-10 review fix — three forms git accepts as a force-push, each still blocked to
# main/master even with the authorization prefix: a clustered short flag containing -f
# (not just a standalone -f token), a long --force(-with-lease) flag, and a leading '+' on
# the refspec (with or without an explicit src:dst). Each must go red if the corresponding
# guard is removed (mutation-provable against is_force()/strip_plus()).
expect_case BLOCK "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push -uf origin main"
expect_case BLOCK "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push -fu origin main"
expect_case BLOCK "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push -qf origin main"
expect_case BLOCK "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push origin +main"
expect_case BLOCK "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push origin +HEAD:main"
# Not force: a cluster without f, or a '+' on a refspec that does not target main/master.
expect_case ALLOW "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push -uq origin main"
expect_case ALLOW "$TMPROOT/feat-repo" "git push origin +task/x:task/y"

# PI-10 delta re-review — two more force/destructive spellings, both reachable only through
# the prefix (BLOCKED without it, ALLOWED with it before this fix): a short-flag cluster
# where the letter f sits next to a digit flag (-4/-6), and deleting main/master outright
# (by flag, by empty-source refspec, or via --mirror/--prune, which can remove it without
# ever naming it). Mutation-provable: reverting either guard turns its rows red.
expect_case BLOCK "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push -f4 origin main"
expect_case BLOCK "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push -4f origin main"
expect_case BLOCK "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push -f4 origin master"
expect_case BLOCK "$TMPROOT/main-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push -4f"

expect_case BLOCK "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push --delete origin main"
expect_case BLOCK "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push -d origin main"
expect_case BLOCK "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push -d origin master"
expect_case BLOCK "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push --delete origin refs/heads/main"
expect_case BLOCK "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push origin :main"
expect_case BLOCK "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push origin :refs/heads/main"
expect_case BLOCK "$TMPROOT/main-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push --mirror origin"
expect_case BLOCK "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push --prune origin +refs/heads/*:refs/heads/*"
# Same forms without the prefix must still block — the fix must not depend on it.
expect_case BLOCK "$TMPROOT/feat-repo" "git push --delete origin main"
expect_case BLOCK "$TMPROOT/feat-repo" "git push origin :main"

# Controls: deleting a *task* branch, in every one of the same shapes, must stay ALLOW —
# the fix must not over-tighten cleanup of ordinary branches.
expect_case ALLOW "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push -d origin task/x"
expect_case ALLOW "$TMPROOT/feat-repo" "git push -d origin task/x"
expect_case ALLOW "$TMPROOT/feat-repo" "git push --delete origin feat/old"
expect_case ALLOW "$TMPROOT/feat-repo" "git push origin :task/x"
expect_case ALLOW "$TMPROOT/feat-repo" "git push origin +task/x:task/y"

# ── PI-13: a form the classifier does not recognise must be DENIED, not ignored. The
# defect was that the push classifier anchored on `^git`, so anything in front of `git`
# (an env/variable assignment, a `-c key=value` one-off config, or the audit prefix with a
# non-authorized value) slipped past classification and reached the base branch unblocked.
# The other side matters as much: legitimate task-branch pushes, and the orchestrator's
# push with the exact authorized prefix, must still pass.

# AC1 — any variable (or `env`) assignment in front of `git` no longer hides the push.
# Mutation-provable: re-anchoring the classifier to the start of the command (dropping the
# leading-assignment strip) turns the two main-repo rows ALLOW → red.
expect_case BLOCK "$TMPROOT/main-repo" "FOO=bar git push"
expect_case BLOCK "$TMPROOT/main-repo" "env FOO=bar git push"
expect_case BLOCK "$TMPROOT/feat-repo" "FOO=bar git push origin main"

# AC2 — `git -c key=value push`, the standard one-off-config spelling, is classified. The
# config value must not be mistaken for the subcommand.
expect_case BLOCK "$TMPROOT/main-repo" "git -c k=v push"
expect_case BLOCK "$TMPROOT/feat-repo" "git -c k=v push origin main"
expect_case BLOCK "$TMPROOT/feat-repo" "git -c user.name=x push origin HEAD:main"
expect_case BLOCK "$TMPROOT/feat-repo" "git -c a=b -c c=d push origin main"

# AC3 — the audit prefix authorizes only by its EXACT value: any other value (=0, =2, =10)
# must be treated as no authorization and must not disarm the guard. Mutation-provable:
# re-anchoring to `^git` (so the prefix token is required to strip) makes these ALLOW → red.
expect_case BLOCK "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=0 git push origin main"
expect_case BLOCK "$TMPROOT/main-repo" "POCKET_IT_ORCHESTRATOR_PUSH=0 git push"
expect_case BLOCK "$TMPROOT/main-repo" "POCKET_IT_ORCHESTRATOR_PUSH=2 git push"
expect_case BLOCK "$TMPROOT/main-repo" "POCKET_IT_ORCHESTRATOR_PUSH=10 git push"

# AC4 — the exact authorized form still passes: this task must not re-close what PI-10 opened.
expect_case ALLOW "$TMPROOT/main-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push"
expect_case ALLOW "$TMPROOT/main-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push origin main"
expect_case BLOCK "$TMPROOT/main-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push --force"

# AC5 — the same AC1-AC3 spellings toward a non-base branch pass exactly as before.
expect_case ALLOW "$TMPROOT/feat-repo" "FOO=bar git push"
expect_case ALLOW "$TMPROOT/feat-repo" "git -c k=v push"
expect_case ALLOW "$TMPROOT/feat-repo" "FOO=bar git push origin feat/x"
expect_case ALLOW "$TMPROOT/feat-repo" "env X=1 git push origin HEAD"

# AC6 — a glob refspec reaches the base branch without naming it, quoted or unquoted; a
# quoted refspec is classified against the raw command, not the STR-stripped one.
# Mutation-provable: neutering targets_base()/is_glob() (or comparing dst by equality only)
# turns these red.
expect_case BLOCK "$TMPROOT/feat-repo" "git push origin refs/heads/*:refs/heads/*"
expect_case BLOCK "$TMPROOT/feat-repo" "git push origin +refs/heads/*:refs/heads/*"
expect_case BLOCK "$TMPROOT/feat-repo" "git push origin 'refs/heads/*:refs/heads/*'"
expect_case BLOCK "$TMPROOT/feat-repo" "git push origin refs/heads/*"

# AC7 — --all pushes every local branch, main included, without naming it; blocked on its
# own, and blocked as a force-push when combined with a force flag.
expect_case BLOCK "$TMPROOT/feat-repo" "git push --all --force origin"
expect_case BLOCK "$TMPROOT/feat-repo" "git push --all -f"
expect_case BLOCK "$TMPROOT/main-repo" "git push --all"

# AC8 — the ordinary cleanup of task branches, in every one of the same spellings, still
# passes: a glob that cannot expand to the base branch, a quoted task refspec, a `-c` push
# to a feature branch. The tightening must not catch these in the middle.
expect_case ALLOW "$TMPROOT/feat-repo" "git push origin refs/heads/task/*:refs/heads/task/*"
expect_case ALLOW "$TMPROOT/feat-repo" "git push origin 'refs/heads/task/*:refs/heads/task/*'"
expect_case ALLOW "$TMPROOT/feat-repo" "git push origin task/*"
expect_case ALLOW "$TMPROOT/feat-repo" "git -c k=v push origin feat/x"

# Controls: a git command that merely mentions `push` (a subcommand that is not push, or a
# push option name) must not be classified as a push to the base branch.
expect_case ALLOW "$TMPROOT/feat-repo" "git config push.default simple"
expect_case ALLOW "$TMPROOT/feat-repo" "git log --oneline"


# ── PI-13 round 2 (review of PR #47). The hook's job was reframed: it guards a COOPERATIVE
# agent from a base-branch push written in a NORMAL form; deliberate evasions are left to
# server-side branch protection (see the threat model at the top of guard.sh). These cases
# cover the regression the first round introduced and the everyday forms still reachable.

# F1 — REGRESSION FIX: a quoted string or a heredoc body that contains ; | && followed by
# push-shaped words must NOT turn a legitimate command into a fake push segment. All of these
# passed before PR #47, were blocked by it, and must pass again. Run from a feature branch so
# the real trailing push (to HEAD) is itself legitimate. Mutation-provable: replacing the
# quote-aware tokenizer with a regex split on the raw text turns these red.
expect_case ALLOW "$TMPROOT/feat-repo" 'git commit -m "fix; git push origin main is blocked now" && git push -u origin HEAD'
expect_case ALLOW "$TMPROOT/feat-repo" 'git commit -m "note | git push --all is denied" && git push -u origin HEAD'
expect_case ALLOW "$TMPROOT/feat-repo" 'git commit -m "a && git push origin main now fails" && git push -u origin HEAD'
expect_case ALLOW "$TMPROOT/feat-repo" 'gh pr comment 1 --body "blocked: git push; git push origin main here" && git push -u origin HEAD'
expect_case ALLOW "$TMPROOT/feat-repo" "git push -u origin HEAD && gh pr create --body \"\$(cat <<'EOF'
body ; git push origin main stays blocked
EOF
)\""
expect_case ALLOW "$TMPROOT/feat-repo" "git commit -F- <<'EOF'
line ; git push origin main here
EOF
git push -u origin HEAD"

# F8 — the audit prefix authorizes only on the push's OWN command word, not merely by being
# present somewhere in the command. Mutation-provable: tying auth to the whole command (the
# old behaviour) turns these ALLOW → red here.
expect_case BLOCK "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 true && git push origin main"
expect_case BLOCK "$TMPROOT/feat-repo" "echo POCKET_IT_ORCHESTRATOR_PUSH=1 ; git push origin main"

# F5 — every refspec after the remote is classified (not only the first), and options that
# take a value consume it so they do not shift the refspecs out of view. Each moves main on a
# real remote. Mutation-provable: reading only positional[1], or dropping PUSH_VALUE_OPTS,
# turns these red.
expect_case BLOCK "$TMPROOT/feat-repo" "git push origin task/x main"
expect_case BLOCK "$TMPROOT/feat-repo" "git push origin task/x HEAD:main"
expect_case BLOCK "$TMPROOT/feat-repo" "git push origin task/x task/x:main"
expect_case BLOCK "$TMPROOT/feat-repo" "git push origin task/x +main"
expect_case BLOCK "$TMPROOT/feat-repo" "git push -o ci.skip origin main"
expect_case BLOCK "$TMPROOT/feat-repo" "git push --push-option ci.skip origin main"
expect_case BLOCK "$TMPROOT/feat-repo" "git push --receive-pack git-receive-pack origin main"

# F6 — destinations that resolve to the base without being spelled `main`: the DWIM
# `heads/main`, the matching refspec `:`/`+:`, and `@` (HEAD). Mutation-provable: narrowing
# norm() back to `refs/heads/` only (F6a), or dropping the `:`/`@` handling, turns these red.
expect_case BLOCK "$TMPROOT/feat-repo" "git push origin task/x:heads/main"
expect_case BLOCK "$TMPROOT/feat-repo" "git push origin task/x:refs/heads/main"
expect_case BLOCK "$TMPROOT/feat-repo" "git push origin :"
expect_case BLOCK "$TMPROOT/feat-repo" "git push origin +:"
expect_case BLOCK "$TMPROOT/main-repo" "git push origin @"
expect_case BLOCK "$TMPROOT/main-repo" "git push -f origin @"

# Controls — the same shapes toward task branches, and @ from a feature branch, must pass:
# the multi-refspec reading and the : / @ handling must not over-tighten ordinary work.
expect_case ALLOW "$TMPROOT/feat-repo" "git push origin task/x main-menu"
expect_case ALLOW "$TMPROOT/feat-repo" "git push origin task/x task/y"
expect_case ALLOW "$TMPROOT/feat-repo" "git push origin :task/old"
expect_case ALLOW "$TMPROOT/feat-repo" "git push -o ci.skip origin task/x"
expect_case ALLOW "$TMPROOT/feat-repo" "git push origin @"
expect_case ALLOW "$TMPROOT/feat-repo" "git push origin task/x:refs/tags/v1"

# ── PI-13 round 3 (delta review of PR #47). Three everyday forms the tokenizer did not model,
# each blocked by the removed greps before round 2 and allowed after it.
NL=$'\n'

# F1 — a redirection is not a refspec. Operator, fd digit and target are dropped before the
# positionals are counted, or a bare push from the base branch stops looking implicit.
# Mutation-provable: making strip_redirections() return its input unchanged turns these red.
expect_case BLOCK "$TMPROOT/main-repo" "git push 2>&1"
expect_case BLOCK "$TMPROOT/main-repo" "git push 2>&1 | tail -5"
expect_case BLOCK "$TMPROOT/main-repo" "git push &>/dev/null"
expect_case BLOCK "$TMPROOT/main-repo" "git push >/tmp/push.log 2>&1"
expect_case BLOCK "$TMPROOT/main-repo" "git push -u origin 2>&1 | tail -3"
expect_case BLOCK "$TMPROOT/main-repo" "git push origin 2>/dev/null"
expect_case ALLOW "$TMPROOT/feat-repo" "git push 2>&1 | tail -5"
expect_case ALLOW "$TMPROOT/main-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push 2>&1 | tail -3"

# F2 — an unquoted newline separates commands; a newline inside quotes does not.
# Mutation-provable: putting the newline back into the lexer's whitespace turns these red.
expect_case BLOCK "$TMPROOT/feat-repo" "git add -A${NL}git commit -m x${NL}git push origin main"
expect_case BLOCK "$TMPROOT/feat-repo" "cd $TMPROOT/main-repo${NL}git push"
expect_case BLOCK "$TMPROOT/main-repo" "git add -A${NL}git commit -m x${NL}git push"
expect_case BLOCK "$TMPROOT/main-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 true${NL}git push"
expect_case ALLOW "$TMPROOT/feat-repo" "git add -A${NL}git commit -m x${NL}git push -u origin HEAD"
expect_case ALLOW "$TMPROOT/feat-repo" "git commit -m \"line1${NL}line2 ; git push origin main\" && git push -u origin HEAD"

# F3 — a command bash accepts but the lexer rejects is DENIED when it pushes to the base
# branch, never waved through. A heredoc delimiter outside \w (MSG-END) is removed too.
# Mutation-provable: printing an empty verdict on ValueError turns the BLOCK rows red.
expect_case BLOCK "$TMPROOT/feat-repo" "git commit -m \$'it\\'s' && git push origin main"
expect_case BLOCK "$TMPROOT/feat-repo" "git commit -F- <<'MSG-END'${NL}it's a note${NL}MSG-END${NL}git push origin main"
expect_case BLOCK "$TMPROOT/feat-repo" "printf \$'a\\'b' && git push -u origin HEAD"
expect_case ALLOW "$TMPROOT/feat-repo" "git commit -F- <<'MSG-END'${NL}it's a note${NL}MSG-END${NL}git push -u origin HEAD"

# F4 — a push under a shell keyword is still a push.
expect_case BLOCK "$TMPROOT/main-repo" "if git push origin main; then echo hi; fi"
expect_case BLOCK "$TMPROOT/feat-repo" "for r in a; do git push origin main; done"
expect_case ALLOW "$TMPROOT/feat-repo" "if git push -u origin HEAD; then echo ok; fi"

# ── PI-13 round 4. (F1) A command the lexer cannot parse has not been classified: every push in
# it is denied, whatever it targets, unless the exact prefix sits on that push. Mutation-provable:
# restoring the old explicit-main-only fallback turns the rows that do not spell main red.
UNP="git commit -m \$'it\\'s'"
expect_case BLOCK "$TMPROOT/main-repo" "$UNP && git push"
expect_case BLOCK "$TMPROOT/main-repo" "$UNP && git push -u origin HEAD"
expect_case BLOCK "$TMPROOT/main-repo" "$UNP${NL}git push 2>&1 | tail -3"
expect_case BLOCK "$TMPROOT/feat-repo" "$UNP && git push origin HEAD:main"
expect_case BLOCK "$TMPROOT/feat-repo" "$UNP && git push --all origin"
expect_case BLOCK "$TMPROOT/feat-repo" "$UNP && git push origin refs/heads/*:refs/heads/*"
expect_case BLOCK "$TMPROOT/feat-repo" "$UNP && git push origin :"
expect_case BLOCK "$TMPROOT/feat-repo" "$UNP && git push origin task/x:heads/main"
expect_case BLOCK "$TMPROOT/feat-repo" "$UNP && POCKET_IT_ORCHESTRATOR_PUSH=1 true && git push origin main"
expect_case BLOCK "$TMPROOT/main-repo" "$UNP && POCKET_IT_ORCHESTRATOR_PUSH=1 git push --force origin main"
expect_case ALLOW "$TMPROOT/main-repo" "$UNP && POCKET_IT_ORCHESTRATOR_PUSH=1 git push origin main"
expect_case ALLOW "$TMPROOT/feat-repo" "$UNP && git status"

# (F2) A backslash-newline continues the line; it is joined before the newline becomes a
# separator. Mutation-provable: dropping the join turns the BLOCK rows red.
expect_case BLOCK "$TMPROOT/feat-repo" "git push \\${NL} origin main"
expect_case BLOCK "$TMPROOT/feat-repo" "git push -u \\${NL} origin HEAD:main"
expect_case BLOCK "$TMPROOT/feat-repo" "git push \\${NL} --all origin"
expect_case BLOCK "$TMPROOT/feat-repo" "git push --force \\${NL} origin main"
expect_case BLOCK "$TMPROOT/feat-repo" "git push origin \\${NL} refs/heads/*:refs/heads/*"
expect_case ALLOW "$TMPROOT/feat-repo" "git push -u \\${NL} origin task/x"

# ── PI-32. The caller is read from the input, not from the command: Claude Code adds `agent_id`
# and `agent_type` when the hook runs inside a subagent and omits both in the main session. Every
# case below builds the input with and without those keys. Mutation-provable: treating every
# input as the main session (CALLER=main) turns every agent BLOCK row red.
agent_case() {
  local expect="$1" cwd="$2" fields="$3" cmd="$4" payload got
  payload=$(python3 -c 'import json,sys
d={"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}; d.update(json.loads(sys.argv[2])); print(json.dumps(d))' "$cmd" "$fields")
  if (cd "$cwd" && printf '%s' "$payload" | bash "$HOOKDIR/guard.sh") >/dev/null 2>&1; then got=ALLOW; else got=BLOCK; fi
  if [[ "$got" == "$expect" ]]; then echo "ok    $got  [cwd=$(basename "$cwd") $fields] $cmd"; else echo "FAIL  want $expect got $got  [cwd=$(basename "$cwd") $fields] $cmd"; fail=1; fi
}
DEV='{"agent_id":"a1b2c3d4","agent_type":"developer"}'
REV='{"agent_id":"r9","agent_type":"reviewer"}'
RETRO='{"agent_id":"t7","agent_type":"retro"}'
PP=POCKET_IT_ORCHESTRATOR_PUSH=1
PM=POCKET_IT_USER_MERGE=1
# A task branch whose upstream is origin/main with push.default=upstream: a bare `git push`
# from it lands on main although the command names no branch at all.
git clone -q "$TMPROOT/main-repo" "$TMPROOT/upstream-repo"
git -C "$TMPROOT/upstream-repo" checkout -q -b task/y --track origin/main
git -C "$TMPROOT/upstream-repo" config push.default upstream

# AC1 — a push to the base branch from an agent is denied even with the audit prefix.
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "$PP git push origin main"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "$PP git push origin HEAD:main"
agent_case BLOCK "$TMPROOT/main-repo" "$DEV" "$PP git push"
agent_case BLOCK "$TMPROOT/neutral"   "$DEV" "cd $TMPROOT/main-repo && $PP git push -u origin HEAD"
agent_case BLOCK "$TMPROOT/main-repo" "$REV" "git add docs/SESSION_HANDOFF.md && git commit -qm log && $PP git push"
agent_case BLOCK "$TMPROOT/feat-repo" "$RETRO" "$PP git push origin main"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git push origin main"
# AC1 — the message says the base branch is forbidden to agents and where diary lines go.
msg=$(cd "$TMPROOT/feat-repo" && python3 -c 'import json,sys
d={"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}; d.update(json.loads(sys.argv[2])); print(json.dumps(d))' "$PP git push origin main" "$DEV" | bash "$HOOKDIR/guard.sh" 2>&1 >/dev/null)
if grep -q "Agents never push the base branch" <<<"$msg" && grep -q "handoff.sh" <<<"$msg" && grep -q "task branch" <<<"$msg"; then
  echo "ok    MSG    agent push message names the ban and where diary lines go"
else echo "FAIL  agent push message: $msg"; fail=1; fi

# AC2 — the same pushes with the exact prefix and no agent keys pass as before.
expect_case ALLOW "$TMPROOT/feat-repo" "$PP git push origin main"
expect_case ALLOW "$TMPROOT/feat-repo" "$PP git push origin HEAD:main"
expect_case ALLOW "$TMPROOT/main-repo" "$PP git push"
expect_case ALLOW "$TMPROOT/neutral"   "cd $TMPROOT/main-repo && $PP git push -u origin HEAD"

# AC3 — an agent's gh pr merge is denied with the prefix, except agent_type retro.
agent_case BLOCK "$TMPROOT/neutral" "$DEV" "$PM gh pr merge 8 --squash"
agent_case BLOCK "$TMPROOT/neutral" "$REV" "$PM gh pr merge 8 --squash --delete-branch"
agent_case BLOCK "$TMPROOT/neutral" '{"agent_id":"x1"}' "$PM gh pr merge 8 --squash"
agent_case BLOCK "$TMPROOT/neutral" '{"agent_id":"x1","agent_type":"Retro"}' "$PM gh pr merge 8 --squash"
agent_case BLOCK "$TMPROOT/neutral" "$DEV" "$PM gh \"pr\" merge 8"
agent_case BLOCK "$TMPROOT/neutral" "$DEV" "gh api -X PUT repos/o/r/pulls/8/merge"
agent_case ALLOW "$TMPROOT/neutral" "$RETRO" "$PM gh pr merge 8 --squash"
agent_case BLOCK "$TMPROOT/neutral" "$RETRO" "gh pr merge 8 --squash"
expect_case ALLOW "$TMPROOT/neutral" "$PM gh pr merge 8 --squash"
agent_case ALLOW "$TMPROOT/neutral" "$REV" "gh pr ready 12 && gh pr comment 12 --body ok"
agent_case ALLOW "$TMPROOT/neutral" "$REV" "gh pr view 3 --json mergeable --jq .mergeable"

# AC4 — everything that was allowed to an agent stays allowed, except the base branch.
agent_case ALLOW "$TMPROOT/feat-repo" "$DEV" "git push -u origin task/pi-32-slug"
agent_case ALLOW "$TMPROOT/feat-repo" "$DEV" "git push -u origin HEAD"
agent_case ALLOW "$TMPROOT/feat-repo" "$DEV" "git push"
agent_case ALLOW "$TMPROOT/main-repo" "$DEV" "cd $TMPROOT/feat-repo && git push -u origin HEAD 2>&1 | tail -3"
agent_case ALLOW "$TMPROOT/neutral"   "$DEV" "git -C $TMPROOT/feat-repo push -u origin HEAD"
agent_case ALLOW "$TMPROOT/feat-repo" "$DEV" "git add -A && git commit -q -m 'fix: tidy the parser' && git push -u origin HEAD"
agent_case ALLOW "$TMPROOT/feat-repo" "$DEV" "git push -u origin HEAD && gh pr create --draft --base main --title x --body-file b.md"
agent_case ALLOW "$TMPROOT/feat-repo" "$DEV" "git fetch origin main && git rebase origin/main && git push --force-with-lease -u origin HEAD"
agent_case ALLOW "$TMPROOT/feat-repo" "$DEV" "git push origin +task/x:task/x"
agent_case ALLOW "$TMPROOT/feat-repo" "$DEV" "git push -u origin feat/main-menu"
agent_case ALLOW "$TMPROOT/main-repo" "$REV" "git log --oneline --grep push -5"
agent_case ALLOW "$TMPROOT/main-repo" "$REV" "git pull --ff-only origin main && git status"
agent_case ALLOW "$TMPROOT/feat-repo" "$DEV" "git commit -F msg.txt && git push -u origin HEAD"

# AC4 — for an agent, what can reach the base branch is denied in any spelling the main-session
# guard leaves to the server: quoting, wrappers, variables, aliases, config, globs, resolution.
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git push origin \"ma\"\"in\""
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "g\\it pu\\sh origin main"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "bash -c \"git push origin main\""
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "env -i git push origin HEAD:refs/heads/main"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "command /usr/bin/git push origin main"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git push origin \"\$B\""
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git push origin \$(printf ma; printf in)"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git -c alias.p=push p origin HEAD"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git -c push.default=upstream push"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "GIT_DIR=$TMPROOT/main-repo/.git git push -u origin HEAD"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git push --all origin"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git push --mirror origin"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git push origin :"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git push origin 'refs/heads/*:refs/heads/*'"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git push origin ''"
agent_case BLOCK "$TMPROOT/main-repo" "$DEV" "git push -u origin HEAD"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "cd $MISSING && git push origin HEAD"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "cd \"\$WT\" && git push -u origin HEAD"
agent_case BLOCK "$TMPROOT/upstream-repo" "$DEV" "git push"
# The price, on purpose: text outside a textual option (a positional argument, an echo) that
# spells a push to main next to a git word is denied for agents; the main session still allows it.
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git add -A && handoff.sh fact \"never git push origin main\" && git commit -qm log"
expect_case ALLOW "$TMPROOT/feat-repo" "git add -A && handoff.sh fact \"never git push origin main\" && git commit -qm log"

# AC5 — agent_id present but empty or of an unexpected type, or agent_type alone: an agent.
for f in '{"agent_id":""}' '{"agent_id":null}' '{"agent_id":42}' '{"agent_id":["x"]}' '{"agent_type":"developer"}' '{"agent_id":"","agent_type":null}'; do
  agent_case BLOCK "$TMPROOT/feat-repo" "$f" "$PP git push origin main"
done
agent_case ALLOW "$TMPROOT/feat-repo" '{"agent_id":null}' "git push -u origin HEAD"

# AC7 — quote removal that goes out of step cannot hide a push from an agent. Each row is a
# command bash runs as a push to main; the quote-aware reading alone lets the first three through
# (the lexer misreads where the quotes pair). Mutation-provable: skipping the quote-blind reading
# (agent_doubt returning '') turns them red.
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "printf \$'a\\'b' && git push origin main && echo 'c'"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "printf \$'a\\'b' && git push origin main && printf \$'c\\'d'"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "echo \"\$(echo \")\"; git push origin main; echo \"(\")\""
agent_case BLOCK "$TMPROOT/main-repo" "$DEV" "printf \$'a\\'b' && git push -u origin HEAD && echo 'c'"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git \$'\\x70ush' origin HEAD:\$'\\x6dain'"

# ── PI-32 round 2, finding 1. "The prefix authorizes nothing for an agent" (PREFIX_COUNTS) is
# covered by reading B, so no row above proves it alone. These rows run on a copy of the guard in
# which reading B is switched off by rewriting its one call; the copy is refused if the rewrite
# did not happen. Mutation-provable: PREFIX_COUNTS = True turns them red (reading A lets the prefix
# authorize). Not an environment switch: an agent could set it.
NOB="$TMPROOT/guard-no-reading-b.sh"
sed "s/reason = agent_doubt(dropped)/reason = ''/" "$HOOKDIR/guard.sh" > "$NOB"
if cmp -s "$HOOKDIR/guard.sh" "$NOB" || ! grep -q "reason = ''" "$NOB"; then
  echo "FAIL  reading B could not be switched off in the copy (the call to agent_doubt changed?)"; fail=1
fi
nob_case() {
  local expect="$1" cwd="$2" fields="$3" cmd="$4" payload got
  payload=$(python3 -c 'import json,sys
d={"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}; d.update(json.loads(sys.argv[2])); print(json.dumps(d))' "$cmd" "$fields")
  if (cd "$cwd" && printf '%s' "$payload" | bash "$NOB") >/dev/null 2>&1; then got=ALLOW; else got=BLOCK; fi
  if [[ "$got" == "$expect" ]]; then echo "ok    $got  [no-B cwd=$(basename "$cwd") $fields] $cmd"; else echo "FAIL  want $expect got $got  [no-B cwd=$(basename "$cwd") $fields] $cmd"; fail=1; fi
}
nob_case BLOCK "$TMPROOT/feat-repo" "$DEV" "$PP git push origin main"
nob_case BLOCK "$TMPROOT/feat-repo" "$DEV" "$PP git push origin HEAD:main"
nob_case BLOCK "$TMPROOT/main-repo" "$DEV" "$PP git push"
nob_case BLOCK "$TMPROOT/main-repo" "$DEV" "git commit -m \$'it\\'s' && $PP git push origin main"
# Controls on the same copy: the main session keeps its prefix, an agent keeps its task branch.
nob_case ALLOW "$TMPROOT/feat-repo" '{}' "$PP git push origin main"
nob_case ALLOW "$TMPROOT/feat-repo" "$DEV" "git push -u origin HEAD"

# ── PI-32 round 2, finding 2. A rule that looks for a word (merge, push, main, pkill, prod, sleep)
# must not find it in the free text passed as the value of a textual option (-m/--message,
# --body/--title/--notes, a heredoc read as text). Each rule is tested both ways: harmless text
# holding the word passes, the real command is still denied. Mutation-provable, each layer on rows
# the other layers do not cover: making the TEXT replacement return the raw command turns the rows
# marked (T) red; restoring the unanchored merge regex turns the rows marked (A) red (their value
# cannot be replaced: the command holds ANSI-C quoting, or the body a backtick); reading the
# APP_STATUS rule past its own segment turns (S) red, reading it on the quote-stripped text (Q).
HD() { printf '%s' "\"\$(cat <<'EOF'${NL}$1${NL}EOF${NL})\""; }

# Rule: agent merge ban (quote-blind text).
agent_case ALLOW "$TMPROOT/neutral" "$REV" "gh pr comment 54 --body \"Review passed — 9 criteria checked. merge: orchestrator\""
agent_case ALLOW "$TMPROOT/neutral" "$DEV" "gh pr create --draft --base main --title \"PI-99: fix merge order in doctor\" --body-file b.md"
agent_case ALLOW "$TMPROOT/neutral" "$REV" "gh pr comment 54 --body \"ready to merge\""
agent_case ALLOW "$TMPROOT/neutral" "$DEV" "gh pr create --draft --base main --title \"PI-99: fix merge order\" --body \$'line one\\nline two'"   # (A)
agent_case ALLOW "$TMPROOT/neutral" "$REV" "gh pr comment 54 --body \"Review passed, \`date\` checked. merge: orchestrator\""   # (A)
agent_case ALLOW "$TMPROOT/neutral" "$REV" "gh pr comment 54 --body $(HD 'NEEDS WORK: an agent ran gh pr merge 8 --squash')"   # (T)
agent_case ALLOW "$TMPROOT/neutral" "$REV" "gh pr comment 54 -F - <<'EOF'${NL}gh pr merge 8 must not run here${NL}EOF"   # (T)
agent_case ALLOW "$TMPROOT/neutral" "$DEV" "git commit -qm \"docs: gh pr merge is the orchestrator's\""   # (T)
agent_case ALLOW "$TMPROOT/neutral" "$REV" "gh pr comment 54 --body=\"see gh pr merge 8 and pulls/8/merge\""   # (T)
agent_case BLOCK "$TMPROOT/neutral" "$DEV" "gh pr merge 8"
agent_case BLOCK "$TMPROOT/neutral" "$DEV" "gh -R o/r pr merge 8"
agent_case BLOCK "$TMPROOT/neutral" "$DEV" "gh pr -R o/r merge 8 --squash"
agent_case BLOCK "$TMPROOT/neutral" "$DEV" "gh pr view 8 && gh pr merge 8"
agent_case BLOCK "$TMPROOT/neutral" "$DEV" "gh pr comment 8 --body ok && gh pr merge 8 --body \"merged\""
agent_case BLOCK "$TMPROOT/neutral" "$DEV" "gh pr comment 8 --body \"\$(gh pr merge 8)\""
agent_case BLOCK "$TMPROOT/neutral" "$DEV" "gh pr comment 8 --body \"run \`gh pr merge 8\`\""

# Rule: agent push to the base branch (reading B, quote-blind text).
agent_case ALLOW "$TMPROOT/feat-repo" "$DEV" "git commit -qm \"guard: deny a push to main from agents\" && git push -u origin HEAD"   # (T)
agent_case ALLOW "$TMPROOT/feat-repo" "$DEV" "git commit -F- <<'EOF'${NL}never git push origin main${NL}EOF${NL}git push -u origin HEAD"   # (T)
agent_case ALLOW "$TMPROOT/feat-repo" "$DEV" "git commit -m $(HD 'fix: git push origin main is denied') && git push -u origin HEAD"   # (T)
agent_case ALLOW "$TMPROOT/feat-repo" "$DEV" "git push -u origin HEAD && gh pr create --draft --base main --title \"push to main is denied\" --body $(HD 'git push origin main; git push --all')"   # (T)
agent_case ALLOW "$TMPROOT/feat-repo" "$REV" "git status && gh pr comment 54 --body-file - <<'EOF'${NL}1. git push origin HEAD:main passes${NL}EOF"   # (T)
agent_case ALLOW "$TMPROOT/feat-repo" "$DEV" "git stash push -m \"wip before merging main\""   # (T)
agent_case ALLOW "$TMPROOT/feat-repo" "$DEV" "git commit --message=\"push to main denied\" && git tag -a v1 -m \"main release\""   # (T)
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git commit -qm \"guard\" && git push origin main"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git commit -m \"\$(git push origin main)\""
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git commit -m \"\`git push origin main\`\""
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git commit -F- <<EOF${NL}\$(git push origin main)${NL}EOF"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "bash <<'EOF'${NL}git push origin main${NL}EOF"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "cat <<'EOF' | bash${NL}git push origin main${NL}EOF"
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git commit -m \"\$(cat <<'EOF'${NL}x${NL}EOF${NL}git push origin main${NL}EOF${NL})\""
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "gh pr create --title x --body \"\$(git push origin main)\""
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git commit -m \$'a\\'b' --message \"git push origin main\""
agent_case BLOCK "$TMPROOT/feat-repo" "$DEV" "git push -m x origin main"

# Rule: main-session merge (needs POCKET_IT_USER_MERGE=1).
expect_case ALLOW "$TMPROOT/neutral" "gh pr comment 3 --body \"run gh pr merge 3 after review\""
expect_case ALLOW "$TMPROOT/neutral" "gh pr create --title \"gh pr merge docs\" --body $(HD 'then gh pr merge 3 --squash')"
expect_case BLOCK "$TMPROOT/neutral" "gh pr comment 3 --body ok && gh pr merge 3"
expect_case BLOCK "$TMPROOT/neutral" "gh pr merge 3 --body \"merge it\""

# Rule: pkill/killall.
expect_case ALLOW "$TMPROOT/neutral" "gh pr comment 3 --body killall"   # (T)
agent_case ALLOW "$TMPROOT/neutral" "$DEV" "git commit -qm pkill-is-blocked"   # (T)
expect_case ALLOW "$TMPROOT/neutral" "git commit -m \"never pkill node\""
expect_case BLOCK "$TMPROOT/neutral" "gh pr comment 3 --body killall && pkill node"
agent_case BLOCK "$TMPROOT/neutral" "$DEV" "git commit -qm x; killall node"

# Rule: APP_STATUS → prod.
expect_case ALLOW "$TMPROOT/neutral" "gh variable set APP_STATUS --body dev && gh pr comment 3 --body prod"
expect_case ALLOW "$TMPROOT/neutral" "gh variable set APP_STATUS --body dev && echo prod-ready"   # (S)
expect_case ALLOW "$TMPROOT/neutral" "gh variable set APP_STATUS --body dev && gh pr comment 3 --body \"flip APP_STATUS to prod later\""
expect_case ALLOW "$TMPROOT/neutral" "git commit -m \"gh variable set APP_STATUS --body prod is the user's\""
expect_case BLOCK "$TMPROOT/neutral" "gh variable set APP_STATUS --body \"prod\""   # (Q)
expect_case BLOCK "$TMPROOT/neutral" "gh pr comment 3 --body ok && gh variable set APP_STATUS --body prod"
agent_case BLOCK "$TMPROOT/neutral" "$DEV" "gh variable set APP_STATUS --body 'prod'"   # (Q)

# Rule: sleep N && ….
expect_case ALLOW "$TMPROOT/neutral" "git commit -m \"sleep 30 && retry is blocked\""
agent_case ALLOW "$TMPROOT/neutral" "$REV" "gh pr comment 3 --body \"sleep 5; gh pr view 3\""
expect_case BLOCK "$TMPROOT/neutral" "sleep 30 && gh pr checks 3"

# Rule: legacy force-push-to-main grep.
expect_case ALLOW "$TMPROOT/feat-repo" "git push -f origin task/x && gh pr comment 3 --body main"   # (T)
expect_case ALLOW "$TMPROOT/feat-repo" "git push --force origin task/x && git commit -m \"main\""
expect_case BLOCK "$TMPROOT/feat-repo" "git push -f origin task/x && git push -f origin main"

exit $fail
