#!/usr/bin/env bash
# pocket-it status — the project state computed from disk, in ~25 lines. What an orchestrator reads at the start of a turn.
# Usage (project root): bash ~/.claude/agents/pocket-it/bin/status.sh
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "status: not a git repository"; exit 1; }
cd "$ROOT"
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "== $(basename "$ROOT") · branch $(git branch --show-current 2>/dev/null) · $(git status --porcelain | wc -l | tr -d ' ') uncommitted"
if [[ -f .pocket-it.json ]]; then
  python3 -c 'import json;d=json.load(open(".pocket-it.json"));t=d.get("tests",{});print(f"config: scope={d.get(\"scope\",\"medium\")} automerge={d.get(\"automerge\",False)} pipeline={d.get(\"pipeline\",False)} base={d.get(\"baseBranch\",\"main\")} branching={d.get(\"branching\",\"flat\")} tests={t.get(\"integration\",\"on-demand\")}/{t.get(\"e2e\",\"on-demand\")}")'
else echo "config: .pocket-it.json missing (defaults) — run /intake"; fi
echo "docs: $(ls business-analysis/*.md 2>/dev/null | wc -l | tr -d ' ') BAD · $(ls tech-analysis/PROJECT_TECH_ANALYSIS.md tech-analysis/*_TECH_ANALYSIS.md 2>/dev/null | wc -l | tr -d ' ') TAD · $(ls tech-analysis/*_TECH_DELTA.md 2>/dev/null | wc -l | tr -d ' ') delta · $(ls design-specs/*.md 2>/dev/null | wc -l | tr -d ' ') design spec · best-practices: $([[ -d tech-analysis/best-practices || -d best-practices ]] && echo yes || echo no)"
if [[ -d tasks ]]; then
  python3 - <<'PY'
import glob,re,collections
c=collections.Counter(); hi=[]
for f in glob.glob("tasks/*.md"):
    if f.endswith("INDEX.md"): continue
    t=open(f,errors="ignore").read()
    m=re.search(r"^\*\*Status(\*\*:|:\*\*)\s*([A-Za-z ]+)",t,re.M); st=(m.group(2).strip() if m else "Todo")
    st={"to do":"Todo","in coda":"Todo"}.get(st.lower(),st.title() if st.lower() in("todo","done") else st)
    c[st]+=1
    if re.search(r"^\*\*Risk(\*\*:|:\*\*)\s*high",t,re.M|re.I) and st.lower()!="done": hi.append(re.match(r"^#\s*(\S+)",t).group(1))
print("board: "+" · ".join(f"{k} {v}" for k,v in sorted(c.items()))+(f" · high-risk open: {', '.join(hi[:6])}" if hi else ""))
PY
  bash "$BIN/next-wave.sh" 2>&1 >/dev/null | head -1 | sed 's/^/wave:  /'
  ready=$(bash "$BIN/next-wave.sh" 2>/dev/null | python3 -c 'import sys,json;print(", ".join(f"{json.loads(l)[\"issue\"]}({json.loads(l)[\"label\"][:1]}{\"!\" if json.loads(l)[\"risk\"]==\"high\" else \"\"})" for l in sys.stdin if l.strip()))' 2>/dev/null)
  [[ -n "$ready" ]] && echo "ready: $ready"
else echo "board: no tasks/ — nothing planned yet"; fi
if command -v gh >/dev/null && gh repo view >/dev/null 2>&1; then
  gh pr list --state open --limit 15 --json number,title,isDraft,labels,headRefName --jq '.[] | "pr:    #\(.number) \(if .isDraft then "draft" else "ready" end) [\(.labels|map(.name)|join(","))] \(.title|.[0:60])"' 2>/dev/null
fi
wt=$(git worktree list | wc -l | tr -d ' '); [[ "$wt" -gt 1 ]] && echo "worktrees: $((wt-1)) ($(git worktree list | tail -n +2 | awk '{print $NF}' | tr -d '[]' | head -5 | paste -sd, -))"
if [[ -f docs/SESSION_HANDOFF.md ]]; then
  echo "handoff facts:"; awk '/^## Fatti/{f=1;next} /^## /{f=0} f && /^- /{print "  "$0}' docs/SESSION_HANDOFF.md | head -8
  echo "handoff log (last 4):"; awk '/^## Log/{f=1;next} f && /^- /{print "  "$0}' docs/SESSION_HANDOFF.md | head -4
else echo "handoff: docs/SESSION_HANDOFF.md missing — agents create it on first PR (bin/handoff.sh)"; fi
