#!/usr/bin/env bash
# PreToolUse(Bash): i comandi «solo con ok» del progetto non li lancia un agente.
# Il CLAUDE.md del progetto li elenca in una riga: `Comandi solo con ok: <regex>, <regex>, ...`
# (regex di Python, separate da virgola, quindi senza virgole dentro; `nessuno` = nessun comando).
# - Solo per i subagenti (agent_type presente): la sessione principale passa, è lei che chiede l'ok all'utente.
# - Il CLAUDE.md si cerca nel repo del cwd del comando e dei `cd <dir>` che il comando contiene
#   (radice = cartella di `git rev-parse --git-common-dir`, quindi vale anche nei worktree).
# - Comando che combacia con una regex: exit 2 e il messaggio di fermarsi e chiederlo nel report.
# - Nessuna riga, `nessuno`, fuori da un repo, errore proprio: passa (exit 0).
input=$(cat)
out=$(printf '%s' "$input" | python3 -c '
import json, os, re, subprocess, sys
d = json.load(sys.stdin)
if d.get("tool_name", "Bash") != "Bash" or not d.get("agent_type"):
    sys.exit(0)
cmd = (d.get("tool_input") or {}).get("command") or ""
if not cmd:
    sys.exit(0)
cwd = d.get("cwd") or os.getcwd()
dirs = [cwd]
for m in re.finditer(r"(?:^|[;&|(]\s*|\s)cd\s+([^\s;&|)]+)", cmd):
    p = os.path.expanduser(m.group(1).strip("\"\x27"))
    dirs.append(p if os.path.isabs(p) else os.path.join(cwd, p))
visti = set()
for dir in dirs:
    if not os.path.isdir(dir):
        continue
    try:
        common = subprocess.run(["git", "-C", dir, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                capture_output=True, text=True, timeout=5).stdout.strip()
    except Exception:
        continue
    if not common or common in visti:
        continue
    visti.add(common)
    claude = os.path.join(os.path.dirname(common), "CLAUDE.md")
    if not os.path.isfile(claude):
        continue
    lista = None
    for riga in open(claude, encoding="utf-8", errors="replace"):
        m = re.match(r"^Comandi solo con ok:\s*(.*?)\s*$", riga)
        if m:
            lista = m.group(1)
            break
    if lista is None or lista.lower() in ("", "nessuno", "-"):
        continue
    for rx in (x.strip() for x in lista.split(",")):
        if not rx:
            continue
        try:
            if re.search(rx, cmd):
                print(rx)
                sys.exit(0)
        except re.error:
            continue
' 2>/dev/null)
[ -z "$out" ] && exit 0
echo "comandi-costosi: «${out}» è un comando solo con ok dell'utente (riga «Comandi solo con ok» nel CLAUDE.md del progetto): fermati e chiedilo nel report, non lanciarlo" >&2
exit 2
