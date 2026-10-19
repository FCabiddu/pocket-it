#!/usr/bin/env bash
# The errors and launches of the current project that reached ~/.claude/logs/ after the previous run.
# Every run marks the point: the next run shows only the new lines.
#   errori.sh                                   (from inside the repo, at the end of a wave)
#   errori.sh --onda <slug>-<n> [--regole v7]   (as above, and also writes the wave's row in docs/recap/metriche.md)
# Prints in full the denied permissions and the commands that failed again (an agent going round in circles),
# then the summary of the agent launches (hooks/log-lanci.sh): how many per type, durations, turns, tokens, outcomes,
# who is near the turn limit, who compacted the context, who started without finishing.
# Commands that failed once are not printed: usually they are ordinary red tests, not friction.
# With --onda it appends (never rewrites) a row to the project's board, docs/recap/metriche.md, with the window's numbers:
# tasks (developer launches), PRs, review rounds (CHANGES reports), RIGIRA (tester stops beyond the first), launches, duration, tokens.
# The danni and attriti columns stay `?`: the main session fills them in after reading. The rules version,
# when --regole is missing, is the one at the top of lite/CLAUDE.md next to this script.
set -euo pipefail

onda=""; regole=""
while [ $# -gt 0 ]; do
  case "$1" in
    --onda)   onda="${2:?errori: --onda needs <slug>-<n>}"; shift 2 ;;
    --regole) regole="${2:?errori: --regole needs a version, e.g. v7}"; shift 2 ;;
    *) echo "errori: unknown option: $1 (usage: errori.sh [--onda <slug>-<n>] [--regole v7])" >&2; exit 1 ;;
  esac
done
if [ -n "$onda" ] && [ -z "$regole" ]; then
  regole=$(head -1 "$(dirname "$0")/../CLAUDE.md" 2>/dev/null | grep -m1 -o 'v[0-9]\+' || true)
  regole="${regole:-?}"
fi

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "errori: not inside a git repo" >&2; exit 1; }
repo=$(dirname "$common")
dir="${ERRORI_DIR:-$HOME/.claude/logs/errori}"   # ERRORI_DIR only for the tests
lanci="${LANCI_DIR:-$HOME/.claude/logs/lanci}"   # LANCI_DIR only for the tests
agenti="${AGENTI_DIR:-$HOME/.claude/agents}"     # AGENTI_DIR only for the tests: where the <agent>.md files with maxTurns live
mark="$dir/.letto-$(printf '%s' "$repo" | shasum | cut -c1-12)"

python3 - "$dir" "$repo" "$mark" "$lanci" "$agenti" "$onda" "$regole" <<'EOF'
import json, sys, os, glob, datetime, re, collections
dir, repo, mark, lanci, agenti, onda, regole = sys.argv[1:]
since = open(mark).read().strip() if os.path.exists(mark) else ""
now = datetime.datetime.now().isoformat(timespec="seconds")
nel_repo = lambda cwd: cwd == repo or cwd.startswith(repo + "/")
negati, di_nuovo = [], []
for f in sorted(glob.glob(os.path.join(dir, "*.jsonl"))):
    if os.path.basename(f)[:10] < since[:10]:
        continue
    for line in open(f):
        d = json.loads(line)
        cwd = d.get("cwd") or ""
        if d["ora"] <= since or not nel_repo(cwd):
            continue
        if d["evento"] == "PermissionDenied":
            negati.append(d)
        elif d.get("nota") == "fallito di nuovo":
            di_nuovo.append(d)
one = lambda s, n: " ".join((s or "").split())[:n]
print(f"Errors of {repo} " + (f"from {since}" if since else "from the start of the logs") + f" to {now}")
print(f"\nDenied permissions: {len(negati)}")
for d in negati:
    print(f"- {d['ora'][5:16].replace('T', ' ')} {d['agente']} {d['strumento']}: {one(d['input'], 200)}")
    if d.get("altro"):
        print(f"  → {one(d['altro'], 300)}")
print(f"\nFailed again: {len(di_nuovo)}")
for d in di_nuovo:
    print(f"- {d['ora'][5:16].replace('T', ' ')} {d['agente']} {d['strumento']}: {one(d['input'], 160)}\n  → {one(d['errore'], 200)}")

# Launches: every event in the register (30 days), paired by agent_id; a launch is new if its stop
# (or, without a stop, its start) is after the marker. The starts of a new launch may lie before the marker.
per_id = collections.OrderedDict()
stop_nuovi = []   # every stop in the window: an agent resumed with SendMessage stops several times with the same agent_id
for f in sorted(glob.glob(os.path.join(lanci, "*.jsonl"))):
    for line in open(f):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if not nel_repo(d.get("cwd") or "") or not d.get("agent_id"):
            continue
        l = per_id.setdefault(d["agent_id"], {"agente": d.get("agente"), "compact": []})
        if d["evento"] == "compact":
            l["compact"].append(d)
        else:
            l[d["evento"]] = d
        if d["evento"] == "stop" and d.get("ora", "") > since:
            stop_nuovi.append(d)
nuovi = [l for l in per_id.values() if (l.get("stop") or l.get("start") or {}).get("ora", "") > since]
def max_turns(agente):
    # os.walk and not glob: the agent files also live in hidden folders (lite/.claude/agents/).
    for radice, _, nomi in os.walk(agenti, followlinks=True):
        if agente + ".md" in nomi:
            m = re.search(r"^maxTurns:\s*(\d+)", open(os.path.join(radice, agente + ".md")).read(), re.M)
            if m:
                return int(m.group(1))
    return None
def minuti(l):
    if not (l.get("start") and l.get("stop")):
        return None
    a, b = (datetime.datetime.fromisoformat(l[k]["ora"]) for k in ("start", "stop"))
    return max(0, int((b - a).total_seconds() // 60))
fmt_m = lambda m: f"{m}m" if m is not None else "?"
def fmt_tok(n):
    return f"{n/1e6:.1f}M" if n >= 1e6 else (f"{n//1000}k" if n >= 1000 else str(n))
per_tipo = collections.OrderedDict()
for l in nuovi:
    per_tipo.setdefault(l["agente"], []).append(l)
print(f"\nLaunches: {len(nuovi)}" + (" (" + ", ".join(f"{a} {len(ls)}" for a, ls in per_tipo.items()) + ")" if nuovi else ""))
vicini, compattati, senza_stop = [], [], []
for agente, ls in per_tipo.items():
    durate = [m for m in (minuti(l) for l in ls) if m is not None]
    riga = f"- {agente:<12}{len(ls):>3}"
    if durate:
        riga += f"  average duration {sum(durate)//len(durate)}m, max {max(durate)}m" if len(durate) > 1 else f"  duration {durate[0]}m"
    turni = [l["stop"]["turni"] for l in ls if l.get("stop", {}).get("turni")]
    mt = max_turns(agente)
    if turni:
        riga += f"  turns max {max(turni)}" + (f"/{mt}" if mt else "")
    tin = sum(l["stop"].get("token_in", 0) + l["stop"].get("token_cache", 0) for l in ls if l.get("stop"))
    tout = sum(l["stop"].get("token_out", 0) for l in ls if l.get("stop"))
    if tin or tout:
        riga += f"  tokens {fmt_tok(tin)} in, {fmt_tok(tout)} out"
    esiti = collections.Counter(l["stop"].get("esito", "altro") for l in ls if l.get("stop"))
    if esiti:
        riga += "  outcomes: " + ", ".join(f"{e} {n}" for e, n in esiti.most_common())
    print(riga)
    for l in ls:
        aid = (l.get("start") or l.get("stop"))["agent_id"][:4]
        t = l.get("stop", {}).get("turni")
        if t and mt and t >= 0.8 * mt:
            vicini.append(f"{agente} {aid} {t}/{mt}")
        for c in l["compact"]:
            compattati.append(f"{agente} {aid}, {c.get('trigger') or '?'}")
        if l.get("start") and not l.get("stop"):
            senza_stop.append(f"{agente} {aid} since {l['start']['ora'][11:16]}")
if vicini:
    print("Near the turn limit (≥ 80% of maxTurns): " + "; ".join(vicini))
print(f"Compactions: {len(compattati)}" + (" (" + "; ".join(compattati) + ")" if compattati else ""))
if senza_stop:
    print("Without stop (maybe still running or interrupted): " + "; ".join(senza_stop))

if onda:
    tabellone = os.path.join(repo, "docs", "recap", "metriche.md")
    durate = [m for m in (minuti(l) for l in nuovi) if m is not None]
    tin = sum(l["stop"].get("token_in", 0) + l["stop"].get("token_cache", 0) for l in nuovi if l.get("stop"))
    tout = sum(l["stop"].get("token_out", 0) for l in nuovi if l.get("stop"))
    prs = sorted({d["pr"] for d in stop_nuovi if d.get("pr")})
    colonne = [now[:10], onda, regole,
               str(sum(1 for l in nuovi if l["agente"] == "developer")),
               ", ".join(str(p) for p in prs) if prs else "-",
               str(sum(1 for d in stop_nuovi if d.get("esito") == "CHANGES")),
               str(max(0, sum(1 for d in stop_nuovi if d.get("agente") == "tester") - 1)),
               str(len(nuovi)),
               f"{sum(durate)}m" if durate else "?",
               f"{fmt_tok(tin)} in, {fmt_tok(tout)} out" if (tin or tout) else "?",
               "?", "?"]
    riga = "| " + " | ".join(colonne) + " |\n"
    os.makedirs(os.path.dirname(tabellone), exist_ok=True)
    if not os.path.exists(tabellone):
        with open(tabellone, "w") as f:
            f.write("# Metriche per onda\n\n"
                    "Una riga per onda, scritta da `errori.sh --onda <slug>-<n>` a fine onda con i numeri del registro dei lanci. "
                    "`danni` e `attriti` li compila la sessione principale dopo la lettura degli errori (il numero di righe scritte in `attriti.md` e nel recap). "
                    "Serve a vedere, onda dopo onda e versione dopo versione delle regole, se il flusso migliora.\n\n"
                    "| data | onda | regole | task | PR | giri di review (CHANGES) | RIGIRA | lanci | durata totale | token | danni | attriti |\n"
                    "|---|---|---|---|---|---|---|---|---|---|---|---|\n")
    with open(tabellone, "a") as f:
        f.write(riga)
    print(f"\nWave row appended to {os.path.relpath(tabellone, repo)} (danni and attriti to fill in): {riga.strip()}")
os.makedirs(dir, exist_ok=True)
open(mark, "w").write(now)
EOF
