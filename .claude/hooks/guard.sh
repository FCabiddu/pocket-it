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
# For the MAIN SESSION it DELIBERATELY DOES NOT chase forms reached only on purpose; these are
# left to server-side branch protection (for AGENTS most are denied — see WHO IS CALLING below):
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
#
# WHO IS CALLING — the main session or an agent (PI-32).
# The audit prefixes (POCKET_IT_ORCHESTRATOR_PUSH=1, POCKET_IT_USER_MERGE=1) were meant to tell
# the orchestrator, which has the mandate to push the base branch and merge PRs, from the agents,
# which never have it. A prefix alone cannot do that: it is plain text, written in the skills and
# in this very file, so any agent that reads the repository can type it — and one did, pushing a
# diary line to the base branch "with the orchestrator's prefix". A permission obtained by reading
# a shared file is not a permission.
# Claude Code itself tells the two apart. When a PreToolUse hook runs inside a subagent, its JSON
# input carries `agent_id` and `agent_type`; when it runs in the main session those keys are
# absent. This was checked in the field by recording the same Bash call from both contexts: the
# subagent's input held both keys with values, the main session's input held neither. The keys
# are written by Claude Code, not by the command and not by any file an agent can edit.
# So the caller is read first, and the two callers get two different guards:
#   - MAIN SESSION (no `agent_id`, no `agent_type`): everything below, unchanged — the prefixes
#     still authorize by exact value and remain the audit trail that the push or merge was meant.
#   - AGENT (either key present, whatever its value — empty, null, a number: in doubt it is an
#     agent): a prefix authorizes nothing. `gh pr merge` is denied except to `agent_type` "retro",
#     whose mandate is to merge its own text-only PRs (it still needs the merge prefix). Any push
#     that CAN reach main/master is denied, and the decision does not depend on reading the
#     command's quoting correctly: two independent readings run and either one denies —
#     (A) the quote-aware classifier below, and (B) a quote-blind reading that deletes every
#     quote and backslash instead of pairing them, so a misaligned `$'…\'…'`, a `"$(… ")"`
#     nesting or a hidden `'…'` cannot move a push out of view. Reading B denies a push that
#     names main/master, uses --all/--mirror/--prune, a `:` or glob refspec, a variable, an
#     unresolvable directory, an implicit push from main/master or whose @{push} is main/master,
#     config that changes what a push does (alias., push.default, remote.*.push, GIT_DIR…), an
#     unparseable command, or ANSI-C escapes that can encode a word. A push to a task branch
#     stays allowed. The price is paid in false positives, on purpose: a commit message or PR body
#     that spells a push to main next to a `git` word is denied for agents, who pass such text
#     through a file (`git commit -F`, `--body-file`) instead.
#   Residue for agents, left to server-side protection: `git`/`push` reached through a variable,
#   an eval of a variable, or an encoding outside ANSI-C quoting; a push both misread by the lexer
#   AND cut by a quoted separator after `push` in the same command.
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
# The caller: "main" only when the input is a JSON object with neither `agent_id` nor
# `agent_type`; anything else (either key present with any value, an unreadable input) is an
# agent — in doubt, deny. AGENT_TYPE is the agent_type string, empty when absent or not a string.
CALLER=$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    d=None
if isinstance(d, dict) and "agent_id" not in d and "agent_type" not in d:
    print("main")
else:
    t=d.get("agent_type") if isinstance(d, dict) else None
    print("agent:" + (t if isinstance(t, str) and "\n" not in t else ""))' 2>/dev/null)
IS_AGENT=1; AGENT_TYPE=""
if [[ "$CALLER" == main ]]; then IS_AGENT=0; else AGENT_TYPE=${CALLER#agent:}; fi
# The quote-blind text (reading B for agents): continuations joined, every quote and backslash
# deleted rather than paired, so no quoting trick can hide a word from a search on it.
NORM=$(printf '%s' "$RAW" | python3 -c 'import sys,re
s=sys.stdin.read(); s=re.sub(r"\x5c\r?\n", " ", s); print(re.sub(r"[\x27\x22\x5c]", "", s))' 2>/dev/null)

block() { echo "BLOCKED by pocket-it guard: $1. $2" >&2; exit 2; }

# An agent never merges a PR, prefix or not — except `retro`, whose mandate is to merge its own
# text-only PRs (and which still needs the prefix below). Read on the quote-blind text: a merge
# spelled `gh "pr" merge` or through the REST endpoint is still a merge.
if [[ $IS_AGENT == 1 && "$AGENT_TYPE" != retro ]]; then
  if grep -qE '(^|[^[:alnum:]_-])gh[[:space:]]+([^;&|()[:space:]]+[[:space:]]+)*pr[[:space:]]+([^;&|()[:space:]]+[[:space:]]+)*merge([^[:alnum:]_-]|$)|pulls/[^/[:space:]]+/merge' <<<"$NORM"; then
    block "gh pr merge from an agent" "Agents never merge PRs, with or without POCKET_IT_USER_MERGE=1: the prefix is the orchestrator's audit trail, not a permission (only the retro agent merges its own PRs). Report the PR as ready; the orchestrator merges it. If this was only text (a comment or PR body), pass it through --body-file."
  fi
fi
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
# For an agent the gate is the quote-blind text holding a `git` word (which no quoting can hide),
# and the classifier runs in agent mode: the prefix never authorizes and reading B is added.
PUSH_MODE=""
if [[ $IS_AGENT == 1 ]]; then
  grep -qE '(^|[^[:alnum:]_])git([^[:alnum:]_]|$)' <<<"$NORM" && PUSH_MODE=agent
elif grep -qE '(^|[^[:alnum:]_])git([^[:alnum:]_]|$)' <<<"$CMD" && grep -qE '(^|[^[:alnum:]_])push([^[:alnum:]_]|$)' <<<"$CMD"; then
  PUSH_MODE=main
fi
if [[ -n "$PUSH_MODE" ]]; then
  PUSH_VERDICT=$(python3 - "$RAW" "$PWD" "$PUSH_MODE" <<'PYEOF'
import sys, re, os, subprocess, shlex
from fnmatch import fnmatch

cmd, hook_cwd, mode = sys.argv[1], sys.argv[2], sys.argv[3]
# The audit prefix authorizes only the main session; for an agent it is inert text.
PREFIX_COUNTS = (mode == 'main')

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

def classify_quote_aware(cmd):
    # Reading A. Returns '' or a BLOCK_* verdict. The prefix counts only when PREFIX_COUNTS.
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
                if PREFIX_COUNTS and toks[i] == 'POCKET_IT_ORCHESTRATOR_PUSH=1':
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
                return 'BLOCK_UNPARSED'
            if (is_force(rest) or has_delete_flag(rest) or has_mirror_or_prune(rest)
                    or any(t.startswith('+') or t.startswith(':') for t in rest)):
                return 'BLOCK_FORCE'
        return ''

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
                if PREFIX_COUNTS and t == 'POCKET_IT_ORCHESTRATOR_PUSH=1':
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
            return v
    return ''

# ── Reading B, agents only: quote-blind. Quotes and backslashes are DELETED, never paired, so a
# misaligned quote (an ANSI-C string with an escaped quote, a double quote nested in a command
# substitution) cannot carry a push out of view: every word the shell
# could execute is still a word here. Separators and shell keywords cut segments. It over-reads on
# purpose — text inside a commit message is read as if it were a command — and denies in doubt.
B_TOKEN_RE = re.compile(r'[;&|()\n\x60]+|[^\s;&|()\x60]+')
BASE_WORD_RE = re.compile(r'(?<![A-Za-z0-9_.-])(main|master)(?![A-Za-z0-9_.-])')
PUSH_WORD_RE = re.compile(r'(?<![A-Za-z0-9_])push(?![A-Za-z0-9_])')
# Config or environment that changes what a push does or where it goes, and the plumbing push.
CONFIG_DOUBT_RE = re.compile(r'alias\.|push\.default|remote\.[^\s=]*\.push|GIT_CONFIG|--config-env'
                             r'|GIT_DIR|--git-dir|GIT_WORK_TREE|--work-tree|send-pack')
# ANSI-C quoting with an escape that can encode any character (a hex, unicode or octal escape).
ANSI_ESCAPE_RE = re.compile(r"\x24\x27[^\x27]*\\(x[0-9A-Fa-f]|u[0-9A-Fa-f]|U[0-9A-Fa-f]|[0-7]|c.)")

def b_is_sep(t):
    return t in BOUNDARY_KEYWORDS or all(ch in ';&|()\n\x60' for ch in t)

def b_strip_redirections(tokens):
    out, k = [], 0
    while k < len(tokens):
        t = tokens[k]
        if '>' in t or '<' in t:
            # `2>`, `>`, `&>` alone take the next token as target; `>/dev/null` carries its own.
            k += 2 if re.fullmatch(r'\d*[<>]+&?', t) else 1
            continue
        out.append(t); k += 1
    return out

def b_resolve(path, base):
    # None when the directory cannot be known: a variable, a `~user`, `-`, or a missing path.
    if path is None:
        return base
    if '\x24' in path or path == '-' or re.match(r'~[^/]', path):
        return None
    p = os.path.expanduser(path)
    p = p if p.startswith('/') else base.rstrip('/') + '/' + p
    return p if os.path.isdir(p) else None

def b_push_destination(path):
    try:
        r = subprocess.run(["git", "-C", path, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{push}"],
                           capture_output=True, text=True, timeout=3)
        return r.stdout.strip() if r.returncode == 0 else ''
    except Exception:
        return ''

def agent_doubt(raw):
    n = re.sub(r'\\\r?\n', ' ', raw)
    n = re.sub(r'[\x27\x22\x5c]', '', n)
    toks = B_TOKEN_RE.findall(n)
    git_seen, pushes = False, []
    for k, t in enumerate(toks):
        if b_is_sep(t):
            continue
        if git_seen and PUSH_WORD_RE.search(t):
            pushes.append(k)
        if t == 'git' or t.endswith('/git'):
            git_seen = True
    if git_seen and ANSI_ESCAPE_RE.search(raw):
        return 'ANSI-C quoting with a hex, unicode or octal escape can spell any word, so the command cannot be read'
    if not pushes:
        return ''
    try:
        segments(raw)
    except ValueError:
        return 'the command cannot be parsed, so the target of its push cannot be verified'
    m = CONFIG_DOUBT_RE.search(n)
    if m:
        return '"%s" can change what a push does or where it goes' % m.group(0)
    if re.search(r'(^|\s)(\x27\x27|\x22\x22)(\s|$)', raw):
        return 'an empty quoted argument can be an empty refspec'
    for k in pushes:
        s = k
        while s > 0 and not b_is_sep(toks[s - 1]):
            s -= 1
        e = k + 1
        while e < len(toks) and not b_is_sep(toks[e]):
            e += 1
        tail = b_strip_redirections(toks[k + 1:e])
        # A strict push is `git [global options] push` in one segment: the only kind whose
        # arguments are read as refspecs and whose implicit target is resolved.
        strict, c_path = False, None
        g = max((j for j in range(s, k) if toks[j] == 'git' or toks[j].endswith('/git')), default=None)
        if g is not None and toks[k] == 'push':
            j = g + 1
            while j < k and toks[j].startswith('-'):
                if toks[j] in GIT_VALUE_OPTS:
                    if toks[j] == '-C' and j + 1 < k:
                        c_path = toks[j + 1]
                    j += 2
                else:
                    j += 1
            strict = (j == k)
        for t in [toks[k]] + tail:
            if BASE_WORD_RE.search(t):
                return 'the push names main/master'
            if t in ('--all', ':', '+:') or t.startswith('--mirror') or t.startswith('--prune'):
                return '%s pushes or prunes every branch, main included' % t
            if '*' in t and (strict or ':' in t or '/' in t):
                return 'a glob refspec can match main/master'
            if strict and ('\x24' in t or '\x60' in t):
                return 'a variable or substitution hides the target of the push'
        if not strict:
            continue
        refs = push_positionals(tail)[1:]
        if refs and not any(strip_plus(r)[0] in ('HEAD', '@') for r in refs):
            continue                                   # explicit destinations, none of them the base
        cd_path = None
        for j in range(k - 1, -1, -1):
            if toks[j] in ('cd', 'pushd') and (j == 0 or b_is_sep(toks[j - 1])):
                nxt = toks[j + 1] if j + 1 < len(toks) and not b_is_sep(toks[j + 1]) else '~'
                cd_path = nxt
                break
        base = hook_cwd
        if cd_path is not None:
            base = b_resolve(cd_path, hook_cwd)
            if base is None:
                return 'the directory of an implicit push (%s) cannot be resolved' % cd_path
        d = b_resolve(c_path, base)
        if d is None:
            return 'the directory of an implicit push (-C %s) cannot be resolved' % c_path
        if branch_of(d) in ('main', 'master'):
            return 'an implicit push from a checkout on main/master'
        if not refs:
            dest = b_push_destination(d)
            if dest and norm(dest.split('/', 1)[-1]) in ('main', 'master'):
                return 'the current branch pushes to %s by its upstream configuration' % dest
    return ''

if mode == 'agent':
    verdict = classify_quote_aware(cmd)
    if verdict:
        reason = {'BLOCK_FORCE': 'it rewrites or removes the base branch',
                  'BLOCK_UNPARSED': 'the command cannot be parsed, so the target of its push cannot be verified'
                  }.get(verdict, 'the push reaches main/master')
        print('BLOCK_AGENT ' + reason)
    else:
        reason = agent_doubt(cmd)
        print('BLOCK_AGENT ' + reason if reason else '')
else:
    print(classify_quote_aware(cmd))
PYEOF
)
  case "$PUSH_VERDICT" in
    BLOCK_AGENT*)   block "git push that can reach main/master, from an agent (${PUSH_VERDICT#BLOCK_AGENT })" "Agents never push the base branch — not with POCKET_IT_ORCHESTRATOR_PUSH=1, which authorizes only the main session, and not in any spelling: in doubt the guard denies. Push your task branch in a command of its own, e.g. git push -u origin HEAD from your worktree or git push -u origin <task-branch> spelled literally, with no main/master and no variable in that command; pass commit messages or PR bodies that mention such a push through a file (git commit -F, --body-file). Diary lines (handoff.sh log/fact) are committed on your own task branch and travel with your PR; with no branch of your own, leave them uncommitted in the working tree — the orchestrator commits them on the base branch when it closes the wave." ;;
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
