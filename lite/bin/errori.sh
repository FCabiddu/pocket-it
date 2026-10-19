#!/usr/bin/env bash
# Gli errori e i lanci del progetto corrente arrivati in ~/.claude/logs/ dopo l'ultimo lancio.
# Ogni lancio segna il punto: il lancio dopo mostra solo le righe nuove.
#   errori.sh                                   (da dentro il repo, a fine onda)
#   errori.sh --onda <slug>-<n> [--regole v7]   (come sopra, e in più scrive la riga dell'onda in docs/recap/metriche.md)
# Stampa per intero i permessi negati e i comandi falliti di nuovo (un agente che gira in tondo),
# poi il riassunto dei lanci degli agenti (hooks/log-lanci.sh): quanti per tipo, durate, turni, token, esiti,
# chi è vicino al limite di turni, chi ha compattato il contesto, chi è partito senza finire.
# I comandi falliti una volta non si stampano: di solito sono test rossi normali, non attriti.
# Con --onda aggiunge (mai riscrive) una riga al tabellone del progetto, docs/recap/metriche.md, con i numeri della finestra:
# task (lanci di developer), PR, giri di review (report CHANGES), RIGIRA (stop del tester oltre il primo), lanci, durata, token.
# Le colonne danni e attriti restano `?`: le compila la sessione principale dopo la lettura. La versione delle regole,
# se --regole manca, è quella in testa a lite/CLAUDE.md accanto a questo script.
set -euo pipefail

onda=""; regole=""
while [ $# -gt 0 ]; do
  case "$1" in
    --onda)   onda="${2:?errori: --onda vuole <slug>-<n>}"; shift 2 ;;
    --regole) regole="${2:?errori: --regole vuole una versione, es. v7}"; shift 2 ;;
    *) echo "errori: opzione sconosciuta: $1 (uso: errori.sh [--onda <slug>-<n>] [--regole v7])" >&2; exit 1 ;;
  esac
done
if [ -n "$onda" ] && [ -z "$regole" ]; then
  regole=$(head -1 "$(dirname "$0")/../CLAUDE.md" 2>/dev/null | grep -m1 -o 'v[0-9]\+' || true)
  regole="${regole:-?}"
fi

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "errori: non sei in un repo git" >&2; exit 1; }
repo=$(dirname "$common")
dir="${ERRORI_DIR:-$HOME/.claude/logs/errori}"   # ERRORI_DIR solo per le prove
lanci="${LANCI_DIR:-$HOME/.claude/logs/lanci}"   # LANCI_DIR solo per le prove
agenti="${AGENTI_DIR:-$HOME/.claude/agents}"     # AGENTI_DIR solo per le prove: dove stanno i <agente>.md con maxTurns
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
print(f"Errori di {repo} " + (f"dal {since}" if since else "dall'inizio dei log") + f" al {now}")
print(f"\nPermessi negati: {len(negati)}")
for d in negati:
    print(f"- {d['ora'][5:16].replace('T', ' ')} {d['agente']} {d['strumento']}: {one(d['input'], 200)}")
    if d.get("altro"):
        print(f"  → {one(d['altro'], 300)}")
print(f"\nFalliti di nuovo: {len(di_nuovo)}")
for d in di_nuovo:
    print(f"- {d['ora'][5:16].replace('T', ' ')} {d['agente']} {d['strumento']}: {one(d['input'], 160)}\n  → {one(d['errore'], 200)}")

# Lanci: tutti gli eventi del registro (30 giorni), accoppiati per agent_id; un lancio è nuovo se il suo stop
# (o, senza stop, il suo start) è dopo il segnaposto. Gli start di un lancio nuovo possono stare prima del segnaposto.
per_id = collections.OrderedDict()
stop_nuovi = []   # tutti gli stop nella finestra: un agente ripreso con SendMessage si ferma più volte con lo stesso agent_id
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
    # os.walk e non glob: i file degli agenti stanno anche in cartelle nascoste (lite/.claude/agents/).
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
print(f"\nLanci: {len(nuovi)}" + (" (" + ", ".join(f"{a} {len(ls)}" for a, ls in per_tipo.items()) + ")" if nuovi else ""))
vicini, compattati, senza_stop = [], [], []
for agente, ls in per_tipo.items():
    durate = [m for m in (minuti(l) for l in ls) if m is not None]
    riga = f"- {agente:<12}{len(ls):>3}"
    if durate:
        riga += f"  durata media {sum(durate)//len(durate)}m, max {max(durate)}m" if len(durate) > 1 else f"  durata {durate[0]}m"
    turni = [l["stop"]["turni"] for l in ls if l.get("stop", {}).get("turni")]
    mt = max_turns(agente)
    if turni:
        riga += f"  turni max {max(turni)}" + (f"/{mt}" if mt else "")
    tin = sum(l["stop"].get("token_in", 0) + l["stop"].get("token_cache", 0) for l in ls if l.get("stop"))
    tout = sum(l["stop"].get("token_out", 0) for l in ls if l.get("stop"))
    if tin or tout:
        riga += f"  token {fmt_tok(tin)} in, {fmt_tok(tout)} out"
    esiti = collections.Counter(l["stop"].get("esito", "altro") for l in ls if l.get("stop"))
    if esiti:
        riga += "  esiti: " + ", ".join(f"{e} {n}" for e, n in esiti.most_common())
    print(riga)
    for l in ls:
        aid = (l.get("start") or l.get("stop"))["agent_id"][:4]
        t = l.get("stop", {}).get("turni")
        if t and mt and t >= 0.8 * mt:
            vicini.append(f"{agente} {aid} {t}/{mt}")
        for c in l["compact"]:
            compattati.append(f"{agente} {aid}, {c.get('trigger') or '?'}")
        if l.get("start") and not l.get("stop"):
            senza_stop.append(f"{agente} {aid} dalle {l['start']['ora'][11:16]}")
if vicini:
    print("Vicini al limite di turni (≥ 80% di maxTurns): " + "; ".join(vicini))
print(f"Compattazioni: {len(compattati)}" + (" (" + "; ".join(compattati) + ")" if compattati else ""))
if senza_stop:
    print("Senza stop (forse ancora in corso o interrotti): " + "; ".join(senza_stop))

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
    print(f"\nRiga dell'onda aggiunta a {os.path.relpath(tabellone, repo)} (danni e attriti da compilare): {riga.strip()}")
os.makedirs(dir, exist_ok=True)
open(mark, "w").write(now)
EOF
