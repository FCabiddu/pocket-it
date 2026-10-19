#!/usr/bin/env bash
# PreToolUse(Bash): blocks pushes to main/master, plain force pushes, and a «git checkout/restore» of a
# file with uncommitted changes (it would wipe them: commit first).
# Override for a deliberate push to main: prefix the command with ALLOW_MAIN_PUSH=1.
input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)
cwd=$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("cwd",""))' 2>/dev/null)
agent=$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("agent_type") or "")' 2>/dev/null)
# Agents: no prettier --write by hand. Formatting is done by the pre-commit hook (lint-staged) on the files of the
# commit only; by hand an agent reformatted files outside its task. Quoted text and heredoc bodies are not commands.
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
    echo "guard: «${fmt}» blocked for agents: formatting is applied by the pre-commit hook itself on the files of the commit; to check, use prettier --check <file>" >&2
    exit 2
  fi
fi
printf '%s' "$cmd" | grep -q 'ALLOW_MAIN_PUSH=1' && exit 0
# Only the segments with git push: «main» or «-f» elsewhere in the chain (checkout main, rm -f) do not count.
# Each line: <directory the push runs in>\t<segment>. The directory follows the «cd» that precede it in the
# chain (e.g. «cd worktree && git push»), then -C if present; without, it is the tool's cwd.
# Heredoc bodies and quoted text (commit messages, the --body of a PR) are not commands:
# they are not read. If the quotes are not closed, fall back to splitting the raw text, on newlines too.
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
    # «(» and «)» stay in the list: a cd inside parentheses runs in a subshell and does not apply afterwards.
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
        # checkout/restore: the files it rewrites. After «--» they are paths; without «--», for checkout
        # an argument counts only if it is an existing file (a branch is not). restore --staged on
        # its own does not touch the files.
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
                # variable, substitution or glob: the text does not say which files it touches, the whole repo counts
                if re.search(r"[$`*?\[]", a):
                    print("dynamic\t" + where + "\t" + a)
            for a in paths:
                print("touches\t" + where + "\t" + a)
            break
')
[ -n "$pushes" ] || exit 0
block() { echo "guard: $1" >&2; exit 2; }
while IFS=$'\t' read -r kind dir seg; do
  if [ "$kind" = dynamic ]; then
    if [ -n "$(git -C "${dir:-.}" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
      block "the argument $seg does not say which files it touches and the repo has uncommitted changes that checkout/restore can wipe: commit first"
    fi
    continue
  fi
  if [ "$kind" = touches ]; then
    if [ -n "$(git -C "${dir:-.}" status --porcelain -- "$seg" 2>/dev/null)" ]; then
      block "$seg has uncommitted changes and checkout/restore wipes them: commit first"
    fi
    continue
  fi
  if printf '%s' "$seg" | grep -Eq -- '(--force([^-]|$)|[[:space:]]-f([[:space:]]|$))'; then
    block "force push blocked"
  fi
  if printf '%s' "$seg" | grep -Eq '(^|[[:space:]:+])(main|master)([[:space:]]|$)'; then
    block "push to main blocked: use a branch and a PR"
  fi
  # git push without refspec (fewer than two non-option arguments, wherever they are: «origin --delete x»
  # has the refspec x): the current branch of the directory it runs in applies
  npos=$(printf '%s' "$seg" | awk '{ for (i = 1; i <= NF; i++) { if (p && $i !~ /^-/) n++; if ($i == "push") p = 1 } } END { print n + 0 }')
  if [ "$npos" -lt 2 ]; then
    b=$(git -C "${dir:-.}" branch --show-current 2>/dev/null)
    case "$b" in main|master) block "push to main blocked (current branch $b in $dir): use a branch and a PR" ;; esac
  fi
done <<< "$pushes"
exit 0
