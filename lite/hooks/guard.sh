#!/usr/bin/env bash
# PreToolUse(Bash): blocks pushes to main/master, plain force pushes, and a «git checkout/restore» of a
# file with uncommitted changes (it would wipe them: use scripts/mutazione.sh fine, or commit first).
# Override for a deliberate push to main: prefix the command with ALLOW_MAIN_PUSH=1.
input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)
cwd=$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("cwd",""))' 2>/dev/null)
agent=$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("agent_type") or "")' 2>/dev/null)
# Agenti: niente prettier --write a mano. Il formato lo fa l'hook di pre-commit (lint-staged) sui soli file del
# commit; a mano un agente ha riformattato file fuori dal task (10/10, 13/10, 15/10: vedi
# docs/recap/2026-10-15-errori.md). Il testo fra virgolette e il corpo degli heredoc non sono comandi.
if [ -n "$agent" ]; then
  fmt=$(printf '%s' "$cmd" | python3 -c '
import os, re, shlex, sys
src = sys.stdin.read()
lines, out, i = src.split("\n"), [], 0
while i < len(lines):
    line = lines[i]; out.append(line); i += 1
    for m in re.finditer(r"(?<!<)<<-?(?!<)\s*([\"'"'"']?)(\w+)\1", line):
        while i < len(lines) and lines[i].strip() != m.group(2):
            i += 1
        i += 1
try:
    lex = shlex.shlex("\n".join(out), posix=True, punctuation_chars=";&|\n()")
    lex.whitespace = " \t\r"
    lex.wordchars += ":@%+,$`{}"
    toks = list(lex)
except ValueError:
    sys.exit(0)
segs, cur = [], []
for t in toks:
    if set(t) <= set(";&|\n()"):
        segs.append(cur); cur = []
    else:
        cur.append(t)
segs.append(cur)
for seg in segs:
    names = [os.path.basename(t) for t in seg]
    if "prettier" in names:
        args = seg[names.index("prettier") + 1:]
        if any(a in ("--write", "-w") or re.fullmatch(r"-[a-z]*w[a-z]*", a) for a in args):
            print(" ".join(seg)); break
    for runner in ("npm", "pnpm", "yarn"):
        if runner in names:
            rest = [a for a in seg[names.index(runner) + 1:] if not a.startswith("-")]
            if rest[:2] == ["run", "format"] or rest[:1] == ["format"]:
                print(" ".join(seg)); break
')
  if [ -n "$fmt" ]; then
    echo "guard: «${fmt}» bloccato per gli agenti: il formato lo applica da solo l'hook di pre-commit sui file del commit; per controllare usa prettier --check <file>" >&2
    exit 2
  fi
fi
printf '%s' "$cmd" | grep -q 'ALLOW_MAIN_PUSH=1' && exit 0
# Solo i segmenti con git push: «main» o «-f» altrove nella catena (checkout main, rm -f) non contano.
# Ogni riga: <cartella in cui gira il push>\t<segmento>. La cartella segue i «cd» che lo precedono nella
# catena (es. «cd worktree && git push»), poi l'eventuale -C; senza, è la cwd del tool.
# Il corpo degli heredoc e il testo fra virgolette (messaggi di commit, --body di una PR) non sono comandi:
# non si leggono. Se le virgolette non si chiudono, si torna a spezzare il testo grezzo, anche sugli a capo.
pushes=$(printf '%s' "$cmd" | CWD="$cwd" python3 -c '
import os, re, shlex, sys
src = sys.stdin.read()
d = os.environ.get("CWD") or os.getcwd()
def res(base, p):
    p = os.path.expanduser(p.strip("\"'"'"'"))
    return os.path.normpath(os.path.join(base, p))
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
def segments(s):
    try:
        lex = shlex.shlex(s, posix=True, punctuation_chars=";&|\n()")
        lex.whitespace = " \t\r"
        toks = list(lex)
    except ValueError:
        return [s.split() for s in re.split(r"&&|\|\||[;|&\n]", s)]
    # «(» e «)» restano nella lista: un cd fra parentesi gira in una subshell e non vale dopo.
    segs, cur = [], []
    for t in toks:
        if set(t) <= SEP:
            segs.append(cur); cur = []
            segs.extend(c for c in t if c in "()")
        else:
            cur.append(t)
    return segs + [cur]
stack = []
for seg in segments(strip_heredocs(src)):
    if seg == "(":
        stack.append(d); continue
    if seg == ")":
        d = stack.pop() if stack else d; continue
    if len(seg) == 2 and seg[0] == "cd":
        d = res(d, seg[1]); continue
    for i, t in enumerate(seg):
        if t != "git":
            continue
        j, where = i + 1, d
        if seg[j:j + 1] == ["-C"] and j + 1 < len(seg):
            where = res(d, seg[j + 1]); j += 2
        if seg[j:j + 1] == ["push"]:
            print("push\t" + where + "\t" + re.sub(r"\s+", " ", " ".join(seg[i:])))
            break
        # checkout/restore: i file che riscrive. Dopo «--» sono percorsi; senza «--», per checkout
        # conta un argomento solo se è un file esistente (un branch non lo è). restore --staged da
        # solo non tocca i file.
        if seg[j:j + 1] in (["checkout"], ["restore"]):
            args = seg[j + 1:]
            if seg[j] == "restore" and ("--staged" in args or "-S" in args) and not ("--worktree" in args or "-W" in args):
                break
            if "--" in args:
                paths = args[args.index("--") + 1:]
            else:
                skip, paths = False, []
                for a in args:
                    if skip:
                        skip = False; continue
                    if a in ("-b", "-B", "-s", "--source", "--orphan"):
                        skip = True; continue
                    if a.startswith("-"):
                        continue
                    if seg[j] == "restore" or os.path.isfile(res(where, a)):
                        paths.append(a)
            for a in args:
                # variabile, sostituzione o glob: il testo non dice quali file tocca, conta il repo intero
                if re.search(r"[$`*?\[]", a):
                    print("dinamico\t" + where + "\t" + a)
            for a in paths:
                print("tocca\t" + where + "\t" + a)
            break
')
[ -n "$pushes" ] || exit 0
block() { echo "guard: $1" >&2; exit 2; }
while IFS=$'\t' read -r kind dir seg; do
  if [ "$kind" = dinamico ]; then
    if [ -n "$(git -C "${dir:-.}" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
      block "l'argomento $seg non dice quali file tocca e il repo ha modifiche non committate che il checkout/restore può cancellare: per una mutazione usa scripts/mutazione.sh fine <file>, altrimenti fai prima un commit"
    fi
    continue
  fi
  if [ "$kind" = tocca ]; then
    if [ -n "$(git -C "${dir:-.}" status --porcelain -- "$seg" 2>/dev/null)" ]; then
      block "$seg ha modifiche non committate e il checkout/restore le cancella: per una mutazione usa scripts/mutazione.sh fine $seg, altrimenti fai prima un commit"
    fi
    continue
  fi
  if printf '%s' "$seg" | grep -Eq -- '(--force([^-]|$)|[[:space:]]-f([[:space:]]|$))'; then
    block "force push bloccato"
  fi
  if printf '%s' "$seg" | grep -Eq '(^|[[:space:]:+])(main|master)([[:space:]]|$)'; then
    block "push su main bloccato: usa un branch e una PR"
  fi
  # git push senza refspec (meno di due argomenti non-opzione, ovunque stiano: «origin --delete x»
  # ha il refspec x): vale il branch corrente della cartella in cui gira
  npos=$(printf '%s' "$seg" | awk '{ for (i = 1; i <= NF; i++) { if (p && $i !~ /^-/) n++; if ($i == "push") p = 1 } } END { print n + 0 }')
  if [ "$npos" -lt 2 ]; then
    b=$(git -C "${dir:-.}" branch --show-current 2>/dev/null)
    case "$b" in main|master) block "push su main bloccato (branch corrente $b in $dir): usa un branch e una PR" ;; esac
  fi
done <<< "$pushes"
exit 0
