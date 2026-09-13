#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Deterministically blocks the commands the pocket-it
# agents are told never to run, so the rule no longer has to live in every prompt.
# Register in ~/.claude/settings.json → hooks.PreToolUse. Exit 2 = block, message on stderr.
#
# THREAT MODEL — read this before extending the push guard.
# This hook protects a COOPERATIVE agent from pushing to the base branch by mistake, written
# in a NORMAL shell form. It is NOT a security boundary and cannot be made into one: a client
# hook parses shell text, and shell has unbounded ways to reach a command that regexes and a
# tokeniser will never all cover. The real, un-bypassable protection is server-side branch
# protection on the base branch in GitHub; that is the owner's setting, not this file.
# Therefore the push guard COVERS, and has a red test for, the everyday spellings: a bare or
# explicit push, HEAD:/main and refs/heads/main and heads/main, `:`/`+:` and `@`, a variable/
# `env` assignment or a one-off `-c key=val` in front of `git`, the audit prefix (only its exact
# value, only on the push's own command word), force/delete/--mirror/--prune/--all, glob
# refspecs, every refspec in a multi-refspec push, redirections (`2>&1 | tail`, `&>/dev/null`),
# commands on separate lines, a push under a shell keyword (`if … ; then`, `while`, `for … do`),
# backslash-newline continuations, and — when the command cannot be parsed at all — a DENY of
# every push in it, whatever its target, unless the exact audit prefix sits on that push.
# It DELIBERATELY DOES NOT chase forms an agent would only reach on purpose; these are left to
# server-side branch protection, not worked around here:
#   - a string or stdin run as a shell: `bash -c "…"`, `sh -c`, `eval`, `source`, a heredoc
#     piped into a shell;
#   - wrappers and indirections: `env -i`/`env -u`, `command`, `exec`, `nohup`, `time`, `nice`,
#     `timeout`, `xargs`, `sudo`, `stdbuf`, `pushd`, a path such as `/usr/bin/git`;
#   - `git` or `push` hidden by quoting or escaping (`"git" push`, `g\it push`);
#   - an alias defined on the fly (`-c alias.x=push`, `--config-env`, `GIT_CONFIG_*`),
#     `git send-pack`, and an unknown global option;
#   - config or environment that changes what an implicit push does (`push.default`,
#     `remote.*.push`, `GIT_DIR`/`--git-dir` pointing at another repo).
# Adding a regex per new spelling does not converge; if these matter, they belong on the server.
# (PI-32 will let the hook read a Claude-Code input field an agent cannot forge and forbid the
# base branch to agents regardless of the command's shape; this guard then becomes the second
# line and the main session's guard, and still need not chase every spelling.)
set -uo pipefail
INPUT=$(cat)
# Match against the command with heredoc bodies and quoted strings removed, so a commit
# message or an echo that *mentions* a blocked command is not a false positive.
CMD=$(printf '%s' "$INPUT" | python3 -c 'import json,sys,re
try:
    d=json.load(sys.stdin); c=d.get("tool_input",{}).get("command","")
except Exception:
    c=""
c=re.sub(r"<<-?\s*[\x27\"]?([^\s\x27\"<>|;&()]+)[\x27\"]?[^\n]*\n.*?\n\s*\1\s*(?=\n|$)", " HEREDOC ", c, flags=re.S)
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
# deletes it or rewrites the whole remote (--mirror/--prune), is blocked even with the prefix:
# rewriting or removing the base branch is never authorized, for anyone. Authorization is decided
# by the classifier below, per push, and only when the exact prefix sits on that push's own
# command word — so a prefix on a neighbouring command does not authorize the push next to it.
# The classifier below finds a `git push` inside a normally-written command and decides whether
# it reaches the base branch. It reads the RAW command (quotes and refspecs intact) but is fed
# only when the *stripped* CMD holds both `git` and `push` as bare words, so a push named only
# inside a commit message or an echo never reaches it. It resolves an implicit push's branch
# from a `-C <path>` on the same invocation, else the nearest preceding `cd <path>`, else the
# hook's cwd. A parse failure (unbalanced quotes) yields ALLOW: this guards mistakes, and
# blocking a legitimate command on a lexer error would be the worse failure. See the threat
# model at the top for what is deliberately out of scope.
if grep -qE '(^|[^[:alnum:]_])git([^[:alnum:]_]|$)' <<<"$CMD" && grep -qE '(^|[^[:alnum:]_])push([^[:alnum:]_]|$)' <<<"$CMD"; then
  PUSH_VERDICT=$(python3 - "$RAW" "$PWD" <<'PYEOF'
import sys, re, os, subprocess, shlex
from fnmatch import fnmatch

cmd, hook_cwd = sys.argv[1], sys.argv[2]

HEREDOC_RE = r"<<-?\s*[\x27\"]?([^\s\x27\"<>|;&()]+)[\x27\"]?[^\n]*\n.*?\n\s*\1\s*(?=\n|$)"
# A command boundary is a run of separator punctuation (`; & && || | |& ( )` and an unquoted
# newline) or a shell keyword that begins a new command. Keywords are boundaries so a push
# under `if`/`while`/`for … do` is still classified; a newline is a boundary because a
# multi-line command is an everyday form for a cooperative agent, not an evasion.
BOUNDARY_KEYWORDS = {'if', 'then', 'elif', 'else', 'fi', 'while', 'until', 'for',
                     'do', 'done', 'case', 'esac', '{', '}', '!'}
# Redirection operators; each is dropped together with an optional leading fd digit (`2>&1`)
# and its target (`>/dev/null`), or the target lands in `positional` and a bare push stops
# looking implicit (`git push 2>&1 | tail` — the agents' standard output-capping form).
REDIR_OPS = {'>', '>>', '<', '<<<', '>&', '<&', '&>', '&>>'}
GIT_VALUE_OPTS = {'-C', '-c', '--namespace', '--git-dir', '--work-tree',
                  '--exec-path', '--super-prefix', '--config-env'}
# `git push` options that take a separate-token value; their value must be consumed or it is
# read as a refspec and shifts the real refspecs out of view (`git push -o ci.skip origin main`).
PUSH_VALUE_OPTS = {'-o', '--push-option', '--receive-pack', '--exec', '--repo'}

def is_boundary(t):
    return t in BOUNDARY_KEYWORDS or (t != '' and all(ch in ';&|()\n' for ch in t))

def strip_redirections(tokens):
    out = []
    k = 0
    while k < len(tokens):
        t = tokens[k]
        if t in REDIR_OPS:
            if out and re.fullmatch(r'\d+', out[-1]):
                out.pop()          # the fd digit written before the operator (2>&1)
            k += 2                 # skip the operator and its target token
            continue
        out.append(t); k += 1
    return out

def segments(raw):
    # Remove heredoc bodies, then tokenise with a quote-aware lexer and cut on the shell
    # separators. Splitting the raw text with a regex (an earlier approach) cut inside quotes
    # and heredoc bodies, so a commit message or PR body holding `;`/`|`/`&&` plus push-shaped
    # words was turned into a fake push segment and a legitimate command was blocked. Newline
    # is punctuation here (not whitespace) so a push on its own line is its own segment;
    # redirections are stripped per segment. A ValueError (a command bash accepts but shlex
    # rejects) propagates to the caller, which DENIES rather than allowing blindly.
    raw = re.sub(HEREDOC_RE, ' HEREDOC ', raw, flags=re.S)
    # A backslash-newline is a line continuation, not a separator: join it BEFORE the newline
    # becomes a boundary, or `git push \⏎ origin main` splits into a bare push and a stray line.
    raw = re.sub(r'\\\r?\n', ' ', raw)
    lex = shlex.shlex(raw, posix=True, punctuation_chars=';&|()<>\n')
    lex.whitespace = ' \t\r'
    lex.whitespace_split = True
    toks = list(lex)
    segs, cur = [], []
    for t in toks:
        if is_boundary(t):
            if cur:
                segs.append(strip_redirections(cur)); cur = []
        else:
            cur.append(t)
    if cur:
        segs.append(strip_redirections(cur))
    return segs

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
    # main is reachable spelled main, refs/heads/main, or heads/main (git DWIMs a push
    # destination through refs/<dst>). Strip those prefixes before comparing.
    return re.sub(r'^(refs/heads/|heads/)', '', ref)

def is_glob(ref):
    return any(ch in ref for ch in '*?[')

def targets_base(ref):
    # True when a destination ref is, or as a glob matches, main/master. fnmatch so a glob
    # `refs/heads/*` (norm `*`) matches main while `refs/heads/task/*` (norm `task/*`) does not.
    r = norm(ref)
    return r in ('main', 'master') or fnmatch('main', r) or fnmatch('master', r)

def strip_plus(ref):
    # A leading '+' forces the push regardless of any -f/--force flag; strip it before the
    # destination is compared, or a forced +HEAD:main / +main slips through as a plain push.
    return (ref[1:], True) if ref.startswith('+') else (ref, False)

def is_force(tokens):
    # Any short-flag cluster containing f (-uf, -fu, -f4, ...) forces; digits allowed for -4/-6.
    for t in tokens:
        if not t.startswith('-'):
            continue
        if t == '-f' or t.startswith('--force'):
            return True
        if re.fullmatch(r'-[a-zA-Z0-9]+', t) and 'f' in t[1:]:
            return True
    return False

def has_delete_flag(tokens):
    # -d/--delete (or a short cluster containing d) removes a remote ref outright.
    for t in tokens:
        if not t.startswith('-'):
            continue
        if t == '-d' or t.startswith('--delete'):
            return True
        if re.fullmatch(r'-[a-zA-Z0-9]+', t) and 'd' in t[1:]:
            return True
    return False

def has_mirror_or_prune(tokens):
    # --mirror/--prune can remove main from the remote without ever naming it.
    return any(t.startswith('--mirror') or t.startswith('--prune') for t in tokens if t.startswith('-'))

def push_positionals(tokens):
    # Positionals with the value of every value-taking push option consumed, so an option's
    # argument is not counted as a refspec and does not shift the real refspecs.
    pos, k = [], 0
    while k < len(tokens):
        t = tokens[k]
        if t.startswith('-'):
            if t in PUSH_VALUE_OPTS:
                k += 2
            else:
                k += 1
            continue
        pos.append(t); k += 1
    return pos

def classify_ref(ref):
    # (reaches_base, destructive, force) for one refspec.
    ref, force = strip_plus(ref)
    if ref in ('', ':'):
        return (True, False, force)          # matching refspec pushes every branch, main included
    if ref in ('HEAD', '@'):
        return (False, False, force)         # implicit — resolved from the current branch
    if ':' in ref:
        src, dst = ref.split(':', 1)
        if dst == '':
            return (False, False, force)     # deletes `src`, not the base (":main" has dst=main)
        if targets_base(dst):
            return (True, src == '', force)  # empty source side = delete of the base branch
        return (False, False, force)
    if is_glob(ref):
        return (targets_base(ref), False, force)
    return (targets_base(ref), False, force)

def analyze(tokens, authorized, c_path, tracked_cd):
    seg_force = is_force(tokens)
    reaches = implicit = destructive = False
    if has_mirror_or_prune(tokens):
        reaches = True; destructive = True
    if any(t == '--all' for t in tokens if t.startswith('-')):
        reaches = True
    positional = push_positionals(tokens)
    if len(positional) >= 2:
        refspecs = positional[1:]            # positional[0] is the remote
    elif len(positional) == 1:
        only, _ = strip_plus(positional[0])
        # a single positional is the remote (implicit push) unless it is refspec-shaped
        refspecs = [positional[0]] if (':' in only or is_glob(only) or only in ('', ':', '@')) else []
        if not refspecs:
            implicit = True
    else:
        refspecs = []; implicit = True
    for r in refspecs:
        eb, dstr, fo = classify_ref(r)
        reaches = reaches or eb
        destructive = destructive or dstr
        seg_force = seg_force or fo
        rr, _ = strip_plus(r)
        if not eb and rr in ('HEAD', '@'):
            implicit = True
    if reaches and has_delete_flag(tokens):
        destructive = True                    # "-d/--delete origin main"
    kind = 'EXPLICIT'
    if not reaches and implicit:
        if branch_of(resolve_dir(c_path or tracked_cd)) in ('main', 'master'):
            reaches = True; kind = 'IMPLICIT'
    if not reaches:
        return ''
    if seg_force or destructive:
        return 'BLOCK_FORCE'                  # rewriting/removing the base is never authorized
    if not authorized:
        return 'BLOCK_' + kind
    return ''

try:
    segs = segments(cmd)
except ValueError:
    # The command holds `git` and `push` (the gate fired) but the lexer cannot parse it —
    # anything bash accepts and shlex rejects (ANSI-C `$'…'`, unbalanced quotes). Such a command
    # has NOT been classified, so nothing about its target can be trusted: ANY `git push` in it is
    # denied — implicit, HEAD:main, --all, a glob or `:` alike, and a push to a task branch too —
    # unless the exact audit prefix sits on that push itself (and even then never a force/delete).
    # A coarse pass finds the pushes: heredocs and quoted strings removed, continuations joined,
    # cut on separators, then the same assignment/keyword/global-option walk as below.
    coarse = re.sub(HEREDOC_RE, ' ', cmd, flags=re.S)
    coarse = re.sub(r'\\\r?\n', ' ', coarse)
    coarse = re.sub(r'"(?:[^"\\]|\\.)*"', ' STR ', coarse)
    coarse = re.sub(r"'[^']*'", ' STR ', coarse)
    for piece in re.split(r'[;&|()\n]+', coarse):
        toks = piece.split()
        i, authorized = 0, False
        while i < len(toks) and (toks[i] == 'env' or toks[i] in BOUNDARY_KEYWORDS
                                 or re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*=.*', toks[i])):
            if toks[i] == 'POCKET_IT_ORCHESTRATOR_PUSH=1':
                authorized = True
            i += 1
        if i >= len(toks) or toks[i] != 'git':
            continue
        i += 1
        while i < len(toks) and toks[i].startswith('-'):
            i += 2 if toks[i] in GIT_VALUE_OPTS else 1
        if i >= len(toks) or toks[i] != 'push':
            continue
        rest = toks[i + 1:]
        if not authorized:
            print('BLOCK_UNPARSED'); sys.exit(0)
        if (is_force(rest) or has_delete_flag(rest) or has_mirror_or_prune(rest)
                or any(t.startswith('+') or t.startswith(':') for t in rest)):
            print('BLOCK_FORCE'); sys.exit(0)
    print(''); sys.exit(0)

result = ''
tracked_cd = None
for seg in segs:
    if len(seg) >= 2 and seg[0] == 'cd':
        tracked_cd = seg[1]
        continue
    # Strip a leading `env` and NAME=VALUE assignments; the audit prefix authorizes ONLY by its
    # exact value and ONLY on this push's own command word (not merely present in the command).
    i = 0
    authorized = False
    while i < len(seg):
        t = seg[i]
        if t == 'env':
            i += 1; continue
        if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*=.*', t):
            if t == 'POCKET_IT_ORCHESTRATOR_PUSH=1':
                authorized = True
            i += 1; continue
        break
    if i >= len(seg) or seg[i] != 'git':
        continue
    i += 1
    c_path = None
    while i < len(seg) and seg[i].startswith('-'):
        opt = seg[i]
        if opt in GIT_VALUE_OPTS:
            if opt == '-C' and i + 1 < len(seg):
                c_path = seg[i + 1]
            i += 2
        else:
            i += 1
    if i >= len(seg) or seg[i] != 'push':
        continue
    v = analyze(seg[i + 1:], authorized, c_path, tracked_cd)
    if v:
        result = v; break

print(result)
PYEOF
)
  case "$PUSH_VERDICT" in
    BLOCK_FORCE)    block "git push to main/master" "Never rewrite main." ;;
    BLOCK_IMPLICIT) block "git push to main/master" "Push a task branch and open a draft PR. Current branch is main — use a branch and a PR." ;;
    BLOCK_EXPLICIT) block "git push to main/master" "Push a task branch and open a draft PR." ;;
    BLOCK_UNPARSED) block "git push in a command the guard cannot parse" "Nothing about its target can be verified, so any push is refused — even one to a task branch. Rewrite the command without ANSI-C \$'…' quoting or unbalanced quotes, or run the push as its own command." ;;
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
