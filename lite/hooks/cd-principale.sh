#!/usr/bin/env bash
# PreToolUse(Bash): la sessione principale (agent_type assente) non entra con «cd» o «pushd» in un worktree
# (.claude/worktrees/): la cartella della shell resta lì per i comandi dopo, e uno script che toglie il worktree
# (merge-pr.sh) la fa sparire sotto la shell. Passano «git -C», i percorsi assoluti e «(cd <worktree> && …)»,
# perché un cd fra parentesi gira in una subshell.
# Gli agenti (agent_type presente) lavorano nel loro worktree: per loro il blocco è un altro. Niente git che cambia
# stato (merge, checkout, reset, commit…) nel checkout principale. La cartella si segue segmento per segmento; un cd
# verso una cartella che non esiste lascia la cartella com'era, come fa la shell (05/10: «cd <worktree tolto> && S=…;
# git merge origin/main» ha mergiato nel checkout principale).
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
MUTA = {"merge", "checkout", "switch", "reset", "commit", "pull", "rebase", "cherry-pick", "stash", "restore", "revert", "am"}
def principale(path):
    # checkout principale: la prima .git risalendo è una cartella (in un worktree è un file)
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
    # le variabili assegnate prima nello stesso comando (15/10: «W=<worktree>; cd $W» passava)
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
        if i < len(seg) and seg[i] in MUTA and principale(gd):
            print("git " + seg[i] + " nel checkout principale (" + gd + "): un agente lavora solo nel suo worktree; controlla che il cd sia riuscito e usa && fra cd e git")
            sys.exit(0)
        continue
    if not seg or seg[0] not in ("cd", "pushd"):
        continue
    args = [expand(a) for a in seg[1:] if not a.startswith("-")]
    if not agent and depth == 0 and args and ("$" in args[0] or "`" in args[0]):
        print("cd verso una cartella che non si legge dal comando (" + args[0] + "): dalla sessione principale usa un percorso esplicito, git -C o (cd <cartella> && …)")
        sys.exit(0)
    target = os.path.normpath(os.path.join(d, os.path.expanduser(args[0]))) if args else os.path.expanduser("~")
    if agent:
        if os.path.isdir(target):
            d = target
        continue
    if depth == 0:
        if "/.claude/worktrees/" in target + "/" and not target.endswith("/.claude/worktrees"):
            print("niente cd nei worktree dalla sessione principale (" + target + "): usa git -C, percorsi assoluti o (cd <worktree> && …)")
            sys.exit(0)
        d = target
')
[ -n "$msg" ] || exit 0
echo "cd-principale: $msg" >&2
exit 2
