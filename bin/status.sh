#!/usr/bin/env bash
# pocket-it status — the project state computed from disk, in ~25 lines. What an orchestrator reads at the start of a turn.
# Usage (project root): bash ~/.claude/agents/pocket-it/bin/status.sh
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "status: not a git repository"; exit 1; }
cd "$ROOT"
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "== $(basename "$ROOT") · branch $(git branch --show-current 2>/dev/null) · $(git status --porcelain | wc -l | tr -d ' ') uncommitted"
if [[ -f .pocket-it.json ]]; then
  python3 - <<'PY'
import json; d = json.load(open(".pocket-it.json")); t = d.get("tests", {})
print("config: scope=%s automerge=%s pipeline=%s base=%s branching=%s motion=%s tests=%s/%s" % (d.get("scope","medium"), d.get("automerge",True), d.get("pipeline",False), d.get("baseBranch","main"), d.get("branching","flat"), d.get("motion","sober"), t.get("integration","on-demand"), t.get("e2e","on-demand")))
PY
else echo "config: .pocket-it.json missing (defaults) — run /intake"; fi
echo "docs: $(ls business-analysis/PROJECT_BUSINESS_ANALYSIS.md business-analysis/*_BUSINESS_ANALYSIS.md 2>/dev/null | sort -u | wc -l | tr -d ' ') BAD + $(ls business-analysis/*_BUSINESS_DELTA.md 2>/dev/null | wc -l | tr -d ' ') BAD delta · $(ls tech-analysis/PROJECT_TECH_ANALYSIS.md tech-analysis/*_TECH_ANALYSIS.md 2>/dev/null | sort -u | wc -l | tr -d ' ') TAD + $(ls tech-analysis/*_TECH_DELTA.md 2>/dev/null | wc -l | tr -d ' ') delta · $(ls design-specs/*.md 2>/dev/null | wc -l | tr -d ' ') design spec · best-practices: $([[ -d tech-analysis/best-practices || -d best-practices ]] && echo yes || echo no)"
if [[ -d tasks ]]; then
  python3 - <<'PY'
import glob,re,collections
c=collections.Counter(); hi=[]
for f in glob.glob("tasks/**/*.md", recursive=True):
    if f.endswith(("INDEX.md","README.md","/EPIC.md")) or re.search(r"/(EPIC|STORY)-[^/]*\.md$", f): continue
    t=open(f,errors="ignore").read()
    m=re.search(r"^\*\*Status(\*\*:|:\*\*)\s*([A-Za-z ]+)",t,re.M); st=(m.group(2).strip() if m else "Unknown")
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
# one name per linked worktree from the porcelain listing: its branch (or "detached"), then " (locked)" beside it when locked —
# the plain listing's last field is "locked"/"prunable" on such worktrees, not the branch
wtnames=$(git worktree list --porcelain | awk '
  function flush(){ if (n > 1) print (b != "" ? b : "detached") (l ? " (locked)" : ""); b=""; l=0 }
  /^worktree /{ flush(); n++ } /^branch refs\/heads\//{ b=substr($0, 19) } /^locked( |$)/{ l=1 }
  END{ flush() }')
wt=$(git worktree list --porcelain | grep -c '^worktree ')
[[ "$wt" -gt 1 ]] && echo "worktrees: $((wt-1)) ($(head -5 <<<"$wtnames" | paste -sd, -))"
# memory present = the frozen sources (pre-PI-16) or any fragment under docs/handoff/** (post-PI-16, PI-14
# composer); the composer itself (bin/handoff.sh facts|recent) never distinguishes "empty" from "absent",
# so status.sh checks presence on disk itself before asking it to compose.
HANDOFF_MAIN="docs/SESSION_HANDOFF.md"; HANDOFF_ARCHIVE="${HANDOFF_MAIN%.md}_ARCHIVE.md"
handoff_has_memory() {
  [[ -f "$HANDOFF_MAIN" ]] && return 0
  [[ -f "$HANDOFF_ARCHIVE" ]] && return 0
  [[ -d docs/handoff ]] && find docs/handoff -mindepth 2 -name '*.md' -print -quit 2>/dev/null | grep -q . && return 0
  return 1
}
if handoff_has_memory; then
  echo "handoff facts:"; bash "$BIN/handoff.sh" facts 2>/dev/null | head -8 | sed 's/^/  /'
  echo "handoff log (last 4):"; bash "$BIN/handoff.sh" recent 4 2>/dev/null | sed 's/^/  /'
else echo "handoff: nessuna memoria"; fi
