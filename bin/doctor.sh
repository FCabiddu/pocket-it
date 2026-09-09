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
    warn(".pocket-it.json missing — agents use defaults (medium / automerge on / no pipeline / main)")
for k, allowed in {"scope": ("simple","medium","full"), "branching": ("flat","epic"), "motion": ("none","sober","expressive")}.items():
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
files = [f for f in glob.glob("tasks/**/*.md", recursive=True) if not f.endswith(("INDEX.md","README.md","/EPIC.md")) and not re.search(r"/(EPIC|STORY)-[^/]*\.md$", f)]
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
    if "Status" not in fields: warn(f"{f}: no **Status** line — ignored by next-wave.sh (set Done or Todo)")
    if fields.get("Status","").lower() in ("todo","to do","in coda","in progress","needs work"):
        for r in required:
            if r not in fields: warn(f"{f}: missing **{r}** line (developer needs it)")
        if "## Acceptance criteria" not in txt and "## Description" not in txt: warn(f"{f}: no acceptance criteria section")
    if sh(f"git ls-files '{f}'") == "": err(f"{f} is not committed — a developer in a worktree will not find it")
    for dep in re.split(r"[,\s]+", fields.get("Depends on", fields.get("Depends On",""))):
        dep = dep.strip()
        if dep and dep.lower() not in ("none","nessuna","-") and re.match(r"^[A-Z]+-", dep) and dep not in tasks and not (glob.glob(f"tasks/**/{dep}-*.md", recursive=True) or glob.glob(f"tasks/**/{dep}.md", recursive=True)):
            (warn if fields.get("Status","").lower().startswith("done") else err)(f"{f}: depends on {dep} which has no task file")

# 2b. legacy nested board: EPIC.md / STORY-n.m.md status vs their T-*.md children (summaries nobody updates)
status_re = re.compile(r"^\*\*Status(\*\*:|:\*\*)\s*(.*)$", re.M)
def summary_status(path):
    m = status_re.search(open(path, errors="ignore").read())
    return m.group(2).strip() if m else ""
for epic_dir in sorted(d for d in glob.glob("tasks/EPIC-*") if os.path.isdir(d)):
    epic_children = sorted(glob.glob(os.path.join(epic_dir, "T-*.md")))
    epic_file = os.path.join(epic_dir, "EPIC.md")
    if epic_children and os.path.exists(epic_file):
        st = summary_status(epic_file)
        if not st.lower().startswith("done") and all(summary_status(c).lower().startswith("done") for c in epic_children):
            warn(f'{epic_file}: says "{st}" but all {len(epic_children)} children are Done — update the summary')
    for story_file in sorted(glob.glob(os.path.join(epic_dir, "STORY-*.md"))):
        sm = re.match(r"STORY-([\d.]+)\.md$", os.path.basename(story_file))
        if not sm: continue
        prefix = f"T-{sm.group(1)}."
        story_children = sorted(c for c in epic_children if os.path.basename(c).startswith(prefix))
        if not story_children: continue
        st = summary_status(story_file)
        if not st.lower().startswith("done") and all(summary_status(c).lower().startswith("done") for c in story_children):
            warn(f'{story_file}: says "{st}" but all {len(story_children)} children are Done — update the summary')

# 3. DEPS.json
deps_files = glob.glob("implementation-plans/*_DEPS.json")
for df in deps_files:
    try: d = json.load(open(df))
    except Exception as e: err(f"{df}: invalid JSON: {e}"); continue
    dt = d.get("tasks")
    if not isinstance(dt, dict) or not isinstance(d.get("waves", {}), dict):
        warn(f"{df}: legacy DEPS format (no tasks/waves maps) — skipped, not used by next-wave.sh"); continue
    for tid, t in dt.items():
        if not (glob.glob(f"tasks/**/{tid}-*.md", recursive=True) or glob.glob(f"tasks/**/{tid}.md", recursive=True)): err(f"{df}: task {tid} has no file in tasks/")
        for dep in t.get("dependsOn", []):
            if dep not in dt and not (glob.glob(f"tasks/**/{dep}-*.md", recursive=True) or glob.glob(f"tasks/**/{dep}.md", recursive=True)): err(f"{df}: {tid} depends on unknown {dep}")
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

# 4a. BAD: project document + deltas
bad_project = os.path.exists("business-analysis/PROJECT_BUSINESS_ANALYSIS.md")
bad_full = sorted(glob.glob("business-analysis/*_BUSINESS_ANALYSIS.md"))
bad_deltas = sorted(glob.glob("business-analysis/*_BUSINESS_DELTA.md"))
if not bad_project and len(bad_full) > 1:
    warn(f"business-analysis/: {len(bad_full)} per-feature BADs and no PROJECT_BUSINESS_ANALYSIS.md — consolidation pending (/business-analyst consolidate)")
for bd in bad_deltas:
    if not bad_project and not bad_full: warn(f"{bd}: delta without a project BAD (PROJECT_BUSINESS_ANALYSIS.md) or a legacy *_BUSINESS_ANALYSIS.md to apply it to")
    txt = open(bd, errors="ignore").read()
    if not re.search(r"^## .*Impatto sul documento di progetto", txt, re.M): warn(f"{bd}: missing «Impatto sul documento di progetto» section")
    if not re.search(r"Given .*, when .*, then ", txt, re.I): warn(f"{bd}: no Given/When/Then acceptance criteria")
    if "US-1:" in txt and (bad_project or bad_full) and not re.search(r"supersedes US-1\b", txt): warn(f"{bd}: US-1 — story numbering restarted instead of continuing the project sequence")

# 4b. TAD numbering contract
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
