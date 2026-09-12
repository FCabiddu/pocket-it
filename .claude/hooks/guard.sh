#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Deterministically blocks the commands the pocket-it
# agents are told never to run, so the rule no longer has to live in every prompt.
# Register in ~/.claude/settings.json → hooks.PreToolUse. Exit 2 = block, message on stderr.
set -uo pipefail
INPUT=$(cat)
# Match against the command with heredoc bodies and quoted strings removed, so a commit
# message or an echo that *mentions* a blocked command is not a false positive.
CMD=$(printf '%s' "$INPUT" | python3 -c 'import json,sys,re
try:
    d=json.load(sys.stdin); c=d.get("tool_input",{}).get("command","")
except Exception:
    c=""
c=re.sub(r"<<-?\s*[\x27\"]?(\w+)[\x27\"]?[^\n]*\n.*?\n\s*\1\s*(?=\n|$)", " HEREDOC ", c, flags=re.S)
c=re.sub(r"\"(?:[^\"\\\\]|\\\\.)*\"", " STR ", c)
c=re.sub(r"\x27[^\x27]*\x27", " STR ", c)
print(c)' 2>/dev/null)
[[ -z "$CMD" ]] && exit 0
# The raw command, quotes and heredocs intact. The push classifier is fed this, not the
# stripped CMD, so a legitimately quoted refspec (`git push origin "refs/heads/*:..."`) is
# seen for what it is instead of collapsing to STR and slipping through. It is safe because
# the classifier fires only when the *stripped* CMD contains both `git` and `push` as bare
# words (a real push, never a mention buried in a commit message or an echo), and it acts
# only on a segment whose git subcommand is literally `push`.
RAW=$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception: pass' 2>/dev/null)

block() { echo "BLOCKED by pocket-it guard: $1. $2" >&2; exit 2; }

# gh pr merge requires the POCKET_IT_USER_MERGE=1 prefix: the audit trail that the merge is covered by the
# standing default (automerge: true) or by an explicit user instruction. The orchestrator uses it by default
# after an approved review; it is never used when the user asked for draft PRs, nor on the epic→main PR of
# a deployed project without an instruction (that merge is a deploy).
if ! grep -qE '(^|[;&|[:space:]])POCKET_IT_USER_MERGE=1[[:space:]]' <<<"$CMD"; then
  grep -qE '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+merge\b' <<<"$CMD" && block "gh pr merge" "Prefix the command with POCKET_IT_USER_MERGE=1 — the audit trail that this merge is covered by the automerge default or by an explicit instruction. Never merge when the user asked for draft PRs, nor the epic→main PR of a deployed project without an instruction: report the PR as ready instead."
fi
# git push to main/master is authorized only with the POCKET_IT_ORCHESTRATOR_PUSH=1 prefix: the
# audit trail that this push is the orchestrator updating the board, index or memory on the base
# branch after a wave (its standing mandate), not an agent pushing its own work — no agent knows
# this prefix and none is authorized to use it. A force-push to main/master, or any push that
# deletes it or rewrites the whole remote (--mirror/--prune), is blocked even with the prefix,
# below: rewriting or removing the base branch is never authorized, for anyone.
AUTHORIZED_PUSH=0
grep -qE '(^|[;&|[:space:]])POCKET_IT_ORCHESTRATOR_PUSH=1[[:space:]]' <<<"$CMD" && AUTHORIZED_PUSH=1
# No direct pushes to main/master (feature branches are fine).
if [[ "$AUTHORIZED_PUSH" -eq 0 ]]; then
  grep -qE 'git[[:space:]]+push([[:space:]]+-[-a-zA-Z]+)*[[:space:]]+\S+[[:space:]]+(main|master)([[:space:]]|$|:)' <<<"$CMD" && block "git push to main/master" "Push a task branch and open a draft PR."
  grep -qE 'git[[:space:]]+push([[:space:]]+-[-a-zA-Z]+)*[[:space:]]+(origin[[:space:]]+)?(HEAD:)?(main|master)([[:space:]]|$)' <<<"$CMD" && block "git push to main/master" "Push a task branch and open a draft PR."
fi
# A bare `git push`, `git push origin HEAD`/`-u origin HEAD` or a refspec whose destination is
# main/master (even under a refs/heads/ prefix) is only safe when the branch it resolves to isn't
# main/master. Resolve the repo (a `-C <path>` on the same `git` invocation, else the nearest
# preceding `cd <path>` in the command, else the hook's own cwd) and its current branch cheaply.
#
# The classifier below anchors on the `git` token *inside* each segment, after stripping any
# leading `env`/`NAME=VALUE` assignments and git's own global options: a push must be classified
# whatever sits in front of it — a variable assignment (`FOO=bar git push`), the audit prefix with
# any value, or a one-off config (`git -c k=v push`). A form that reaches the base branch but is
# not recognised is DENIED, never ignored. The gate therefore fires for any command that mentions
# both `git` and `push`; the classifier returns an empty verdict (ALLOW) for git commands that are
# not a push, so a broad gate is safe.
if grep -qE '(^|[^[:alnum:]_])git([^[:alnum:]_]|$)' <<<"$CMD" && grep -qE '(^|[^[:alnum:]_])push([^[:alnum:]_]|$)' <<<"$CMD"; then
  PUSH_VERDICT=$(python3 - "$RAW" "$PWD" <<'PYEOF'
import sys, re, os, subprocess, shlex
from fnmatch import fnmatch

cmd, hook_cwd = sys.argv[1], sys.argv[2]

def branch_of(path):
    try:
        r = subprocess.run(["git", "-C", path, "symbolic-ref", "--short", "-q", "HEAD"],
                            capture_output=True, text=True, timeout=3)
        return r.stdout.strip() if r.returncode == 0 else None
    except Exception:
        return None

def resolve_dir(path):
    if path is None:
        return hook_cwd
    p = path if path.startswith("/") else hook_cwd.rstrip("/") + "/" + path
    return p if os.path.isdir(p) else hook_cwd

def norm(ref):
    return re.sub(r'^refs/heads/', '', ref)

def is_glob(ref):
    # A refspec destination that is a glob (git's `*`, or shell globs `?`/`[`) can expand to
    # main/master without the token ever spelling it out — the fourth way a push reaches the
    # base branch without naming it (alongside --all, --mirror and --prune).
    return any(ch in ref for ch in '*?[')

def targets_base(ref):
    # True when a (normalised) destination ref is, or as a glob matches, main/master. Exact
    # match for a literal branch name; fnmatch so `refs/heads/*` (norm `*`) matches main while
    # `refs/heads/task/*` (norm `task/*`) does not — that is what keeps ordinary task-branch
    # cleanup passing while a base-reaching glob is blocked.
    r = norm(ref)
    return r in ('main', 'master') or fnmatch('main', r) or fnmatch('master', r)

def is_force(tokens):
    # git's parse-options accepts clustered short flags (-uf, -fu, -qf, ...), not just a
    # standalone -f token: any short-flag cluster containing the letter f is a force-push.
    # Clusters may also carry a digit flag (-4/-6 for IPv4/IPv6), so the cluster shape itself
    # must allow digits too, or -f4/-4f slip through unmatched.
    # No other `git push` short flag uses the letter f, so this cannot false-positive.
    for t in tokens:
        if not t.startswith('-'):
            continue
        if t == '-f' or t.startswith('--force'):
            return True
        if re.fullmatch(r'-[a-zA-Z0-9]+', t) and 'f' in t[1:]:
            return True
    return False

def strip_plus(ref):
    # A leading '+' on a refspec (or on the source side of a src:dst refspec) forces the
    # push regardless of any -f/--force flag; it must be recognised and stripped before the
    # destination is compared to main/master, or a forced +HEAD:main / +main slips through
    # as a plain (non-force) push to main and the authorization prefix wrongly allows it.
    return (ref[1:], True) if ref.startswith('+') else (ref, False)

def has_delete_flag(tokens):
    # -d/--delete (or a short cluster containing d, e.g. -ud) removes a remote ref outright.
    # No other `git push` short flag uses the letter d, so this cannot false-positive.
    for t in tokens:
        if not t.startswith('-'):
            continue
        if t == '-d' or t.startswith('--delete'):
            return True
        if re.fullmatch(r'-[a-zA-Z0-9]+', t) and 'd' in t[1:]:
            return True
    return False

def has_mirror_or_prune(tokens):
    # --mirror pushes and deletes to make the remote match every local ref exactly;
    # --prune deletes remote refs absent locally. Both can remove main/master without
    # ever naming it, so they are treated as always touching main — long-flag only,
    # no short form in git push, so no cluster case to worry about.
    return any(t.startswith('--mirror') or t.startswith('--prune') for t in tokens if t.startswith('-'))

verdict = ""
force = False
tracked_cd = None
for seg in re.split(r'(?:&&|\|\||;|\|)', cmd):
    seg = seg.strip()
    m = re.match(r'^cd\s+(\S+)', seg)
    if m:
        tracked_cd = m.group(1)
        continue
    try:
        seg_tokens = shlex.split(seg)
    except ValueError:
        seg_tokens = seg.split()
    if not seg_tokens:
        continue
    # Strip any leading `env` command and NAME=VALUE assignment prefixes so the push is
    # classified whatever sits in front of it: `FOO=bar git push`, `env X=1 git push`, and
    # the audit prefix with ANY value (POCKET_IT_ORCHESTRATOR_PUSH=0/2/…). Whether the exact
    # authorized value was given is decided in the shell (AUTHORIZED_PUSH, equality on `=1`);
    # here a prefix must never hide the push from classification — that was the fail-open.
    i = 0
    while i < len(seg_tokens):
        t = seg_tokens[i]
        if t == 'env' or re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*=.*', t):
            i += 1
            continue
        break
    if i >= len(seg_tokens) or seg_tokens[i] != 'git':
        continue
    i += 1
    # Consume git's own global options, which precede the subcommand. The value-taking ones
    # are enumerated so their argument is not mistaken for the subcommand — above all
    # `git -c key=value push` (the standard one-off config) and `git -C <path> push`.
    c_path = None
    value_opts = {'-C', '-c', '--namespace', '--git-dir', '--work-tree',
                  '--exec-path', '--super-prefix', '--config-env'}
    while i < len(seg_tokens) and seg_tokens[i].startswith('-'):
        opt = seg_tokens[i]
        if opt in value_opts:
            val = seg_tokens[i + 1] if i + 1 < len(seg_tokens) else None
            if opt == '-C' and val is not None:
                c_path = val
            i += 2
        else:
            i += 1
    if i >= len(seg_tokens) or seg_tokens[i] != 'push':
        continue
    tokens = seg_tokens[i + 1:]
    positional = [t for t in tokens if not t.startswith('-')]
    seg_force = is_force(tokens)
    seg_delete = has_delete_flag(tokens)

    implicit, explicit_main, destructive = False, False, False

    has_all = any(t == '--all' for t in tokens if t.startswith('-'))

    if has_mirror_or_prune(tokens):
        # Can wipe main from the remote without a single token naming it (a glob refspec,
        # or no refspec at all) — always in scope, regardless of the current branch or of
        # what the positional-ref matching below finds.
        explicit_main = True
        destructive = True

    if has_all:
        # --all pushes every local branch, main included, without naming it — reaches the base
        # branch like a glob refspec does. It is not destructive on its own (an ordinary
        # fast-forward multi-branch push), so a forced --all is caught by seg_force while a
        # plain one is a normal push to the base branch: blocked unless authorized.
        explicit_main = True

    if len(positional) == 0:
        implicit = True
    elif len(positional) == 1:
        ref0, plus_force = strip_plus(positional[0])
        seg_force = seg_force or plus_force
        if ':' in ref0:
            src, dst = ref0.split(':', 1)
            if dst and targets_base(dst):
                explicit_main = True
                if not src:
                    destructive = True  # empty source = delete, e.g. ":main"
        elif is_glob(ref0):
            if targets_base(ref0):  # e.g. `refs/heads/*` reaches main; `task/*` does not
                explicit_main = True
        else:
            implicit = True
    else:
        ref, plus_force = strip_plus(positional[1])
        seg_force = seg_force or plus_force
        if ':' in ref:
            src, dst = ref.split(':', 1)
            if dst and targets_base(dst):
                explicit_main = True
                if not src:
                    destructive = True  # empty source = delete, e.g. "origin :main"
        elif ref == 'HEAD':
            implicit = True
        elif is_glob(ref):
            if targets_base(ref):  # `origin refs/heads/*` reaches main; `origin task/*` does not
                explicit_main = True
        elif targets_base(ref):
            explicit_main = True
            if seg_delete:
                destructive = True  # "-d/--delete origin main"

    if explicit_main:
        verdict = "EXPLICIT"
        force = seg_force or destructive
        break
    if implicit:
        b = branch_of(resolve_dir(c_path or tracked_cd))
        if b in ('main', 'master'):
            verdict = "IMPLICIT"
            force = seg_force
            break

print(verdict + ("_FORCE" if force and verdict else ""))
PYEOF
)
  case "$PUSH_VERDICT" in
    IMPLICIT_FORCE|EXPLICIT_FORCE) block "git push to main/master" "Never rewrite main." ;;
    IMPLICIT) [[ "$AUTHORIZED_PUSH" -eq 0 ]] && block "git push to main/master" "Push a task branch and open a draft PR. Current branch is main — use a branch and a PR." ;;
    EXPLICIT) [[ "$AUTHORIZED_PUSH" -eq 0 ]] && block "git push to main/master" "Push a task branch and open a draft PR." ;;
  esac
fi
# Never kill by pattern on a shared machine.
grep -qE '(^|[;&|[:space:]])(pkill|killall)\b' <<<"$CMD" && block "pkill/killall" "Kill your own process by PID or by port: lsof -nP -iTCP:PORT -sTCP:LISTEN -t | xargs -r kill."
# CI budget switch is a human decision.
grep -qE 'gh[[:space:]]+variable[[:space:]]+set[[:space:]]+APP_STATUS.*prod' <<<"$CMD" && block "APP_STATUS → prod" "Turning hosted CI on is the user's call (initialising it to dev is fine)."
# Sleep-and-poll chains are blocked by the harness anyway; fail fast with a hint.
grep -qE '^[[:space:]]*(cd [^;&]+ (&&|;) *)?sleep[[:space:]]+[0-9]+[[:space:]]*(&&|;)' <<<"$CMD" && block "sleep N && …" "Use 'gh pr checks N --watch' or a bounded until-loop (sleep inside a loop body is fine)."
# Destructive git on shared history.
grep -qE 'git[[:space:]]+push[[:space:]]+.*(--force|-f)\b.*(main|master)' <<<"$CMD" && block "force-push to main" "Never rewrite main."
exit 0
