#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit|Bash): nella memoria globale (quella delle sessioni aperte dalla home,
# ~/.claude/projects/<home>/memory/) non entra niente di un progetto. Le memorie di un progetto vanno nella
# memoria del progetto, che si carica solo aprendo Claude dalla sua cartella.
# - Blocca una memoria `type: project` o che nomina un progetto (nel nome del file o nel testo).
# - Ogni altra scrittura lì, e ogni comando Bash che la tocca, chiede conferma all'utente: una memoria
#   di progetto che non lo nomina si riconosce solo leggendola.
# Progetti: i repo git sotto ~/Desktop e le cartelle che hanno una memoria in ~/.claude/projects/.
# Per le prove: MEMORIA_HOME, MEMORIA_CLAUDE_DIR, MEMORIA_PROGETTI_DIR.
input=$(cat)
out=$(printf '%s' "$input" | python3 -c '
import json, os, re, subprocess, sys
home = os.environ.get("MEMORIA_HOME") or os.path.expanduser("~")
claude = os.environ.get("MEMORIA_CLAUDE_DIR") or os.path.join(home, ".claude")
desk = os.environ.get("MEMORIA_PROGETTI_DIR") or os.path.join(home, "Desktop")
enc = lambda p: re.sub(r"[^A-Za-z0-9]", "-", p)
mem = os.path.join(os.path.realpath(claude), "projects", enc(home), "memory") + "/"
d = json.load(sys.stdin)
ti = d.get("tool_input", {})
def chiedi(perche):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask",
        "permissionDecisionReason": "memoria-globale: " + perche}}))
    sys.exit(0)
if d.get("tool_name") == "Bash":
    cmd = ti.get("command") or ""
    if enc(home) + "/memory" in cmd:
        chiedi("il comando tocca la memoria globale: deve restarci solo cio che vale per tutti i progetti")
    sys.exit(0)
p = ti.get("file_path") or ti.get("notebook_path") or ""
p = os.path.realpath(os.path.join(d.get("cwd") or "", os.path.expanduser(p)))
if not p.startswith(mem):
    sys.exit(0)
testo = "\n".join(str(ti.get(k) or "") for k in ("content", "new_string", "new_source"))
if re.search(r"^\s*type:\s*project\s*$", testo, re.M):
    print("una memoria type: project va nella memoria del progetto, non in quella globale")
    sys.exit(0)
# Nomi dei progetti: repo git fino a 3 livelli sotto ~/Desktop, piu le cartelle con una memoria propria.
cartelle = set()
for radice, dirs, files in os.walk(desk):
    livello = radice[len(desk):].count(os.sep)
    dirs[:] = [x for x in dirs if x not in ("node_modules", ".git", ".claude")] if livello < 3 else []
    if livello >= 1:
        cartelle.add(radice)
codificate = set(os.listdir(os.path.join(claude, "projects"))) if os.path.isdir(os.path.join(claude, "projects")) else set()
nomi = set()
for c in cartelle:
    if os.path.exists(os.path.join(c, ".git")) or enc(c) in codificate:
        nomi.add(os.path.basename(c))
for n in sorted(nomi, key=len, reverse=True):
    parti = [re.escape(x) for x in re.split(r"[^A-Za-z0-9]+", n) if x]
    if not parti:
        continue
    rx = r"(?<![A-Za-z0-9])" + r"[-_ ]?".join(parti) + r"(?![A-Za-z0-9])"
    if re.search(rx, os.path.basename(p) + "\n" + testo, re.I):
        print("cita il progetto " + n + ": va nella memoria del progetto (~/.claude/projects/<cartella del progetto>/memory/), non in quella globale")
        sys.exit(0)
chiedi("scrittura nella memoria globale: e una preferenza valida per tutti i progetti?")
' 2>/dev/null)
[ -z "$out" ] && exit 0
case $out in '{'*) printf '%s\n' "$out"; exit 0;; esac
echo "memoria-globale: $out" >&2
exit 2
