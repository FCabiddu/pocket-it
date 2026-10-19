#!/usr/bin/env bash
# PreToolUse(Bash): the main session (agent_type absent) does not enter a worktree (.claude/worktrees/) with «cd»
# or «pushd»: the shell's directory stays there for the commands that follow, and a script that removes the worktree
# (merge-pr.sh) makes it vanish under the shell. «git -C», absolute paths and «(cd <worktree> && …)» pass,
# because a cd inside parentheses runs in a subshell.
# Agents (agent_type present) work in their own worktree: for them the block is a different one. No git that changes
# state (merge, checkout, reset, commit…) in the main checkout. The directory is followed segment by segment; a cd
# to a directory that does not exist leaves the directory as it was, as the shell does (05/10: «cd <removed worktree> && S=…;
# git merge origin/main» merged into the main checkout).
input=$(cat)
msg=$(printf '%s' "$input" | python3 -c '
import json, os, re, shlex, sys
d = json.load(sys.stdin)
agent = bool(d.get("agent_type"))
src = d.get("tool_input", {}).get("command", "")
cwd = d.get("cwd") or os.getcwd()
def strip_heredocs(s):
    lines, out, i = s.split("\n"), [], 0
    while i < len(lines):
        line = lines[i]; out.append(line); i += 1
        for m in re.finditer(r"(?<!<)<<-?(?!<)\s*([\"'"'"']?)(\w+)\1", line):
            while i < len(lines) and lines[i].strip() != m.group(2):
                i += 1
            i += 1
    return "\n".join(out)
SEP = set(";&|\n()")
try:
    lex = shlex.shlex(strip_heredocs(src), posix=True, punctuation_chars=";&|\n()")
    lex.whitespace = " \t\r"
    lex.wordchars += "$`{}"
    toks = list(lex)
except ValueError:
    sys.exit(0)
segs, cur = [], []
for t in toks:
    if set(t) <= SEP:
        segs.append(cur); cur = []
        segs.extend(c for c in t if c in "()")
    else:
        cur.append(t)
segs.append(cur)
MUTATING = {"merge", "checkout", "switch", "reset", "commit", "pull", "rebase", "cherry-pick", "stash", "restore", "revert", "am"}
def is_main_checkout(path):
    # main checkout: the first .git going up is a directory (in a worktree it is a file)
    p = path
    while True:
        g = os.path.join(p, ".git")
        if os.path.exists(g):
            return os.path.isdir(g)
        if os.path.dirname(p) == p:
            return False
        p = os.path.dirname(p)
ASSIGN = re.compile(r"^([A-Za-z_]\w*)=(.*)$", re.S)
VAR = re.compile(r"\$(?:\{([A-Za-z_]\w*)\}|([A-Za-z_]\w*))")
env = dict(os.environ)
def expand(s):
    # variables assigned earlier in the same command (15/10: «W=<worktree>; cd $W» passed)
    return VAR.sub(lambda m: env.get(m.group(1) or m.group(2), m.group(0)), s)
depth, d, stack = 0, cwd, []
for seg in segs:
    if seg and seg != "(" and seg != ")":
        k = 1 if seg[0] in ("export", "local", "readonly") else 0
        while k < len(seg) and ASSIGN.match(seg[k]):
            name, val = ASSIGN.match(seg[k]).groups()
            env[name] = expand(val); k += 1
        if k == len(seg) or seg[0] in ("export", "local", "readonly"):
            continue
        seg = seg[k:]
    if seg == "(":
        depth += 1; stack.append(d); continue
    if seg == ")":
        depth = max(0, depth - 1); d = stack.pop() if stack else d; continue
    if agent and seg and seg[0] == "git":
        i, gd = 1, d
        while i < len(seg) and seg[i].startswith("-"):
            if seg[i] == "-C" and i + 1 < len(seg):
                gd = os.path.normpath(os.path.join(gd, os.path.expanduser(seg[i + 1]))); i += 2
            elif seg[i] in ("-c", "--git-dir", "--work-tree"):
                i += 2
            else:
                i += 1
        if i < len(seg) and seg[i] in MUTATING and is_main_checkout(gd):
            print("git " + seg[i] + " in the main checkout (" + gd + "): an agent works only in its own worktree; check that the cd succeeded and use && between cd and git")
            sys.exit(0)
        continue
    if not seg or seg[0] not in ("cd", "pushd"):
        continue
    args = [expand(a) for a in seg[1:] if not a.startswith("-")]
    if not agent and depth == 0 and args and ("$" in args[0] or "`" in args[0]):
        print("cd to a directory that cannot be read from the command (" + args[0] + "): from the main session use an explicit path, git -C or (cd <dir> && …)")
        sys.exit(0)
    target = os.path.normpath(os.path.join(d, os.path.expanduser(args[0]))) if args else os.path.expanduser("~")
    if agent:
        if os.path.isdir(target):
            d = target
        continue
    if depth == 0:
        if "/.claude/worktrees/" in target + "/" and not target.endswith("/.claude/worktrees"):
            print("no cd into worktrees from the main session (" + target + "): use git -C, absolute paths or (cd <worktree> && …)")
            sys.exit(0)
        d = target
')
[ -n "$msg" ] || exit 0
echo "cd-main: $msg" >&2
exit 2
