#!/usr/bin/env bash
# pocket-it doctor — zero-token pre-flight for a target project.
# Usage (from the project root): bash ~/.claude/agents/pocket-it/bin/doctor.sh [--wave N]
# Exit 0 = ready to launch agents; exit 1 = problems listed (fix before launching).
set -uo pipefail
WAVE="${2:-}"; [[ "${1:-}" == "--wave" ]] || WAVE=""
python3 - "$WAVE" <<'PY'
import json, os, re, sys, glob, subprocess
wave = sys.argv[1]
errs, warns = [], []
def err(m): errs.append(m)
def warn(m): warns.append(m)
def sh(cmd):
    try: return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()
    except Exception: return ""

# 1. git + config
if not os.path.isdir(".git") and not sh("git rev-parse --show-toplevel"):
    err("not a git repository — worktree isolation and PRs need one")
cfg = {}
if os.path.exists(".pocket-it.json"):
    try: cfg = json.load(open(".pocket-it.json"))
    except Exception as e: err(f".pocket-it.json is not valid JSON: {e}")
    if sh("git ls-files .pocket-it.json") == "": err(".pocket-it.json is not committed — agents in worktrees will not see it")
else:
    warn(".pocket-it.json missing — agents use defaults (medium / no automerge / no pipeline / main)")
for k, allowed in {"scope": ("simple","medium","full"), "branching": ("flat","epic")}.items():
    if k in cfg and cfg[k] not in allowed: err(f".pocket-it.json {k}={cfg[k]!r} not in {allowed}")
for k in ("automerge","pipeline"):
    if k in cfg and not isinstance(cfg[k], bool): err(f".pocket-it.json {k} must be true/false")
tests = cfg.get("tests", {})
for k in ("integration","e2e"):
    if k in tests and tests[k] not in ("off","on-demand","on"): err(f".pocket-it.json tests.{k}={tests[k]!r} not in off/on-demand/on")
base = cfg.get("baseBranch","main")
if sh(f"git rev-parse --verify --quiet {base}") == "" and sh(f"git rev-parse --verify --quiet origin/{base}") == "":
    err(f"baseBranch {base!r} does not exist locally or on origin")

# 2. board
tasks = {}
files = [f for f in glob.glob("tasks/*.md") if not f.endswith("INDEX.md")]
if not files: warn("tasks/ has no task files (run implementation-planner or quickfix first)")
hdr = re.compile(r"^\*\*([A-Za-z ]+?)(\*\*:|:\*\*)\s*(.*)$")
required = ["Status","Label","Files","TAD"]
for f in files:
    txt = open(f, errors="ignore").read()
    m = re.match(r"^#\s*(\S+)", txt)
    tid = m.group(1) if m else os.path.basename(f).split("-")[0]
    fields = {}
    for line in txt.splitlines()[:40]:
        h = hdr.match(line)
        if h: fields[h.group(1).strip()] = h.group(3).strip()
    tasks[tid] = {"file": f, "fields": fields}
    if fields.get("Status","").lower() in ("todo","to do","in coda","in progress","needs work"):
        for r in required:
            if r not in fields: warn(f"{f}: missing **{r}** line (developer needs it)")
        if "## Acceptance criteria" not in txt and "## Description" not in txt: warn(f"{f}: no acceptance criteria section")
    if sh(f"git ls-files '{f}'") == "": err(f"{f} is not committed — a developer in a worktree will not find it")
    for dep in re.split(r"[,\s]+", fields.get("Depends on", fields.get("Depends On",""))):
        dep = dep.strip()
        if dep and dep.lower() not in ("none","nessuna","-") and re.match(r"^[A-Z]+-", dep) and dep not in tasks and not glob.glob(f"tasks/{dep}-*.md"):
            err(f"{f}: depends on {dep} which has no task file")

# 3. DEPS.json
deps_files = glob.glob("implementation-plans/*_DEPS.json")
for df in deps_files:
    try: d = json.load(open(df))
    except Exception as e: err(f"{df}: invalid JSON: {e}"); continue
    dt = d.get("tasks", {})
    for tid, t in dt.items():
        if not glob.glob(f"tasks/{tid}-*.md"): err(f"{df}: task {tid} has no file in tasks/")
        for dep in t.get("dependsOn", []):
            if dep not in dt and not glob.glob(f"tasks/{dep}-*.md"): err(f"{df}: {tid} depends on unknown {dep}")
    for w, ids in (d.get("waves") or {}).items():
        seen = {}
        for tid in ids:
            for fpath in dt.get(tid, {}).get("files", []):
                if fpath in seen: err(f"{df}: wave {w}: {tid} and {seen[fpath]} both touch {fpath} — not parallel-safe")
                seen[fpath] = tid
            for dep in dt.get(tid, {}).get("dependsOn", []):
                if dep in ids: err(f"{df}: wave {w}: {tid} depends on {dep} in the same wave")
    if wave and wave in (d.get("waves") or {}):
        for tid in d["waves"][wave]:
            st = tasks.get(tid, {}).get("fields", {}).get("Status","?")
            if st.lower() == "done": warn(f"wave {wave}: {tid} already Done")

# 4. TAD numbering contract
for tad in glob.glob("tech-analysis/*_TECH_ANALYSIS.md"):
    txt = open(tad, errors="ignore").read()
    heads = re.findall(r"^## (\d+)\.", txt, re.M)
    nums = [int(h) for h in heads]
    if nums and nums != sorted(nums): err(f"{tad}: top-level sections out of order: {nums}")
    expected = {"5.2","6.2","7.6","8.1","9.3","11.1"}
    present = set(re.findall(r"^### (\d+\.\d+)", txt, re.M))
    missing = expected - present
    if missing and cfg.get("scope","medium") != "simple": warn(f"{tad}: subsections referenced by agents missing: {sorted(missing)}")

# 5. hygiene
if os.path.exists(".env") and sh("git ls-files .env"): err(".env is committed")
wt = sh("git worktree list | wc -l")
if wt and int(wt) > 12: warn(f"{wt} worktrees registered — prune the finished ones")
tmp = glob.glob("/tmp/*-automerge") + glob.glob("/tmp/*-pipeline")
if tmp: warn(f"legacy /tmp preference files present ({len(tmp)}) — ignored now, delete them")

for w in warns: print(f"warn  {w}")
for e in errs:  print(f"ERROR {e}")
print(f"doctor: {len(errs)} error(s), {len(warns)} warning(s), {len(files)} task file(s)")
sys.exit(1 if errs else 0)
PY
