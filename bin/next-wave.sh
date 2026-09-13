#!/usr/bin/env bash
# pocket-it next-wave — deterministic answer to "what can be launched right now?".
# Usage (project root): bash ~/.claude/agents/pocket-it/bin/next-wave.sh [DEPS.json]
# Reads task statuses from tasks/*.md and dependencies from the newest *_DEPS.json (or the given one).
# A task is READY when its status is Todo/Needs Work and every dependency is Done. Prints one JSON object
# per ready task plus a summary line, ready to be turned into Agent calls.
set -uo pipefail
DEPS="${1:-$(ls -t implementation-plans/*_DEPS.json 2>/dev/null | head -1)}"
python3 - "$DEPS" <<'PY'
import json, sys, glob, re, os
deps_path = sys.argv[1]
d = json.load(open(deps_path)) if deps_path and os.path.exists(deps_path) else {"tasks": {}}
dt = d.get("tasks", {})
hdr = re.compile(r"^\*\*([A-Za-z ]+?)(\*\*:|:\*\*)\s*(.*)$")
status, label, files_of, deps_of, risk, budget = {}, {}, {}, {}, {}, {}
for f in glob.glob("tasks/**/*.md", recursive=True):
    if f.endswith(("INDEX.md","README.md","/EPIC.md")) or re.search(r"/(EPIC|STORY)-[^/]*\.md$", f): continue
    txt = open(f, errors="ignore").read()
    m = re.match(r"^#\s*(?=[A-Za-z][A-Za-z0-9]*-[^\s:]*\d)([A-Za-z][A-Za-z0-9]*(?:[-.][A-Za-z0-9]+)+)", txt); tid = m.group(1) if m else None   # a real id: a letter-led prefix (alphanumeric segments allowed, e.g. E2E, I18N) then one or more -/. segments, with a digit somewhere past the first hyphen — same regex as doctor.sh, kept identical on purpose. Never a plain hyphenated word ("Follow-up": no digit, lookahead fails) and never trailing punctuation ("T-2.1.1." stops at "T-2.1.1")
    if not tid: continue
    fields = {}
    for line in txt.splitlines()[:40]:
        h = hdr.match(line)
        if h: fields[h.group(1).strip().lower()] = h.group(3).strip()
    status[tid] = re.split(r"\s+[\u2014\u2013-]\s+|\s*\(", fields.get("status", "Unknown"))[0].strip() or "Unknown"   # no Status line = not launchable (pre-board file), never Todo
    label[tid] = fields.get("label", "")
    risk[tid] = fields.get("risk", "low")
    budget[tid] = fields.get("budget", "")
    files_of[tid] = [x.strip("` ") for x in fields.get("files", "").split(",") if x.strip()]
    dep = fields.get("depends on", fields.get("depends On", ""))
    deps_of[tid] = [x for x in re.split(r"[,\s]+", dep) if re.match(r"^[A-Z]+-", x)]
    if tid in dt:
        deps_of[tid] = dt[tid].get("dependsOn", deps_of[tid]) or deps_of[tid]
        files_of[tid] = dt[tid].get("files", files_of[tid]) or files_of[tid]
def done(t): return status.get(t, "").lower() == "done"
def sort_key(tid):
    # Total order: every segment becomes a same-shaped (kind, num, word) tuple so numeric segments
    # never get compared against alphabetic ones directly (that raised TypeError on mixed ids like
    # T-BUG-1 next to T-28.5.5). Numeric segments (kind 0) sort by value and always before alphabetic
    # ones (kind 1) at the same position; alphabetic segments (kind 1) sort lexicographically.
    return [(0, int(x), "") if x.isdigit() else (1, 0, x) for x in re.split(r"[.\-]", tid)]
ready, blocked, taken = [], [], set()
for tid in sorted(status, key=sort_key):
    st = status[tid].lower()
    if st in ("done", "in progress"): continue
    if st not in ("todo", "to do", "in coda", "needs work"): continue
    missing = [x for x in deps_of.get(tid, []) if not done(x)]
    if missing: blocked.append((tid, missing)); continue
    overlap = [f for f in files_of.get(tid, []) if f in taken]
    if overlap: blocked.append((tid, [f"file busy: {overlap[0]}"])); continue
    taken.update(files_of.get(tid, []))
    ready.append(tid)
for tid in ready:
    print(json.dumps({"issue": tid, "label": label[tid], "risk": risk[tid], "status": status[tid],
                      "model": "opus" if risk[tid].lower() == "high" else "sonnet", "budget": budget.get(tid, ""),
                      "agent": "qa-engineer" if label[tid].upper() == "QA" else "developer",
                      "files": files_of.get(tid, [])}, ensure_ascii=False))
inprog = [t for t in status if status[t].lower() == "in progress"]
print(f"next-wave: {len(ready)} ready, {len(inprog)} in progress, {len(blocked)} blocked, {sum(1 for t in status if done(t))} done / {len(status)} total", file=sys.stderr)
for tid, why in blocked[:10]: print(f"  blocked {tid}: {', '.join(why)}", file=sys.stderr)
PY
