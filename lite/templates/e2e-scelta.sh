#!/usr/bin/env bash
# Modello del flusso lite (lite/templates/e2e-scelta.sh): l'architect lo copia in
# scripts/e2e-scelta.sh insieme a e2e/spec-per-cartella.txt (modello: spec-per-cartella.txt).
# Un progetto può sostituirne la logica (per esempio seguendo gli import), ma tiene uso e uscita.
#
# Sceglie gli spec E2E da lanciare dai file cambiati, con la mappa:
#   bash scripts/e2e-scelta.sh [--base <ref>] [--head <ref>]   default origin/main e HEAD
#   bash scripts/e2e-scelta.sh --verifica                      controlla la mappa
# stdout: gli spec scelti, uno per riga, ordinati, senza doppioni (vuoto se nessuno).
# stderr: per ogni file cambiato, quali voci porta e perché; il tester lo incolla nella PR.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
MAP="${E2E_MAPPA:-e2e/spec-per-cartella.txt}"
[ -f "$MAP" ] || { echo "e2e-scelta: manca $MAP" >&2; exit 2; }

base=origin/main head=HEAD verifica=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base=$2; shift 2;;
    --head) head=$2; shift 2;;
    --verifica) verifica=1; shift;;
    *) echo "e2e-scelta: argomento sconosciuto $1" >&2; exit 2;;
  esac
done

if [ "$verifica" = 1 ]; then
  files=$(git ls-files)
else
  files=$(git diff --name-only --no-renames "$base...$head")
fi

E2E_FILES="$files" python3 - "$MAP" "$verifica" <<'EOF'
import fnmatch, glob, os, re, sys
mappa, verifica = sys.argv[1], sys.argv[2] == "1"
files = [l for l in os.environ["E2E_FILES"].splitlines() if l]
spec_globs, test_re, groups, rows = ["e2e/**/*.spec.ts"], r"(/__tests__/|\.test\.[jt]sx?$)", {}, []
for n, line in enumerate(open(mappa), 1):
    line = line.strip()
    if not line or line.startswith("#"): continue
    p = line.split()
    if p[0] == "@spec": spec_globs = p[1:]
    elif p[0] == "@test": test_re = line.split(None, 1)[1]
    elif p[0].startswith("="): groups[p[0][1:]] = p[1:]
    else: rows.append((n, p[0], p[1:]))
tutti = sorted({f for g in spec_globs for f in glob.glob(g, recursive=True)})
is_spec = lambda f: any(fnmatch.fnmatch(f, g.replace("**/", "*")) or fnmatch.fnmatch(f, g) for g in spec_globs)

def espandi(voci, seen=()):
    out = set()
    for v in voci:
        if v == "nessuno": continue
        if v == "tutti": out |= set(tutti)
        elif v in groups and v not in seen: out |= espandi(groups[v], seen + (v,))
        else: out.add(v)
    return out

if verifica:
    bad = []
    for name, voci in groups.items():
        for v in voci:
            if v not in ("tutti", "nessuno") and v not in groups and not glob.glob(v):
                bad.append(f"gruppo ={name}: {v} non esiste")
    for n, pre, voci in rows:
        if voci != ["nessuno"] and not any(f.startswith(pre) for f in files):
            bad.append(f"riga {n}: il prefisso {pre} non combacia con nessun file")
        for v in voci:
            if v not in ("tutti", "nessuno") and v not in groups and not glob.glob(v):
                bad.append(f"riga {n}: {v} non è un gruppo né uno spec esistente")
    for b in bad: print(b, file=sys.stderr)
    print(f"e2e-scelta: mappa {'con errori' if bad else 'giusta'}", file=sys.stderr)
    sys.exit(1 if bad else 0)

scelti = set()
for f in files:
    if re.search(test_re, f):
        print(f"{f}: nessuno (file di test)", file=sys.stderr); continue
    if is_spec(f):
        if glob.glob(f): scelti.add(f)
        print(f"{f}: sé stesso (spec cambiato)", file=sys.stderr); continue
    hit = [(n, voci) for n, pre, voci in rows if f.startswith(pre)]
    if not hit:
        scelti |= set(tutti)
        print(f"{f}: tutti (nessuna riga della mappa)", file=sys.stderr); continue
    for n, voci in hit:
        scelti |= espandi(voci)
    print(f"{f}: {' '.join(v for _, vs in hit for v in vs)} (righe {', '.join(str(n) for n, _ in hit)})", file=sys.stderr)
for s in sorted(scelti): print(s)
EOF
