#!/usr/bin/env bash
# Template of the flow (flow/templates/e2e-select.sh): the architect copies it to
# scripts/e2e-select.sh together with e2e/spec-per-folder.txt (template: spec-per-folder.txt).
# A project may replace its logic (for example following the imports), but keeps usage and output.
#
# Picks the E2E specs to run from the changed files, with the map:
#   bash scripts/e2e-select.sh [--base <ref>] [--head <ref>]   default origin/main and HEAD
#   bash scripts/e2e-select.sh --check                      checks the map
# stdout: the chosen specs, one per line, sorted, without duplicates (empty if none).
# stderr: for every changed file, which entries it brings and why; the tester pastes it in the PR.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
MAP="${E2E_MAP:-e2e/spec-per-folder.txt}"
[ -f "$MAP" ] || { echo "e2e-select: $MAP is missing" >&2; exit 2; }

base=origin/main head=HEAD check=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base=$2; shift 2;;
    --head) head=$2; shift 2;;
    --check) check=1; shift;;
    *) echo "e2e-select: unknown argument $1" >&2; exit 2;;
  esac
done

if [ "$check" = 1 ]; then
  files=$(git ls-files)
else
  files=$(git diff --name-only --no-renames "$base...$head")
fi

E2E_FILES="$files" python3 - "$MAP" "$check" <<'EOF'
import fnmatch, glob, os, re, sys
spec_map, check = sys.argv[1], sys.argv[2] == "1"
files = [l for l in os.environ["E2E_FILES"].splitlines() if l]
spec_globs, test_re, groups, rows = ["e2e/**/*.spec.ts"], r"(/__tests__/|\.test\.[jt]sx?$)", {}, []
for n, line in enumerate(open(spec_map), 1):
    line = line.strip()
    if not line or line.startswith("#"): continue
    p = line.split()
    if p[0] == "@spec": spec_globs = p[1:]
    elif p[0] == "@test": test_re = line.split(None, 1)[1]
    elif p[0].startswith("="): groups[p[0][1:]] = p[1:]
    else: rows.append((n, p[0], p[1:]))
all_specs = sorted({f for g in spec_globs for f in glob.glob(g, recursive=True)})
is_spec = lambda f: any(fnmatch.fnmatch(f, g.replace("**/", "*")) or fnmatch.fnmatch(f, g) for g in spec_globs)

def expand(entries, seen=()):
    out = set()
    for v in entries:
        if v == "none": continue
        if v == "all": out |= set(all_specs)
        elif v in groups and v not in seen: out |= expand(groups[v], seen + (v,))
        else: out.add(v)
    return out

if check:
    bad = []
    for name, entries in groups.items():
        for v in entries:
            if v not in ("all", "none") and v not in groups and not glob.glob(v):
                bad.append(f"group ={name}: {v} does not exist")
    for n, pre, entries in rows:
        if entries != ["none"] and not any(f.startswith(pre) for f in files):
            bad.append(f"line {n}: the prefix {pre} matches no file")
        for v in entries:
            if v not in ("all", "none") and v not in groups and not glob.glob(v):
                bad.append(f"line {n}: {v} is neither a group nor an existing spec")
    for b in bad: print(b, file=sys.stderr)
    print(f"e2e-select: map {'with errors' if bad else 'ok'}", file=sys.stderr)
    sys.exit(1 if bad else 0)

chosen = set()
for f in files:
    if re.search(test_re, f):
        print(f"{f}: none (test file)", file=sys.stderr); continue
    if is_spec(f):
        if glob.glob(f): chosen.add(f)
        print(f"{f}: itself (changed spec)", file=sys.stderr); continue
    hit = [(n, entries) for n, pre, entries in rows if f.startswith(pre)]
    if not hit:
        chosen |= set(all_specs)
        print(f"{f}: all (no line in the map)", file=sys.stderr); continue
    for n, entries in hit:
        chosen |= expand(entries)
    print(f"{f}: {' '.join(v for _, vs in hit for v in vs)} (lines {', '.join(str(n) for n, _ in hit)})", file=sys.stderr)
for s in sorted(chosen): print(s)
EOF
