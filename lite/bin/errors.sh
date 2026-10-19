#!/usr/bin/env bash
# The errors and launches of the current project that reached ~/.claude/logs/ after the previous run.
# Every run marks the point: the next run shows only the new lines.
#   errors.sh                                   (from inside the repo, at the end of a wave)
#   errors.sh --wave <slug>-<n> [--rules v7]   (as above, and also writes the wave's row in docs/recap/metrics.md)
# Prints in full the denied permissions and the commands that failed again (an agent going round in circles),
# then the summary of the agent launches (hooks/log-launches.sh): how many per type, durations, turns, tokens, outcomes,
# who is near the turn limit, who compacted the context, who started without finishing.
# Commands that failed once are not printed: usually they are ordinary red tests, not friction.
# With --wave it appends (never rewrites) a row to the project's board, docs/recap/metrics.md, with the window's numbers:
# tasks (developer launches), PRs, review rounds (CHANGES reports), RERUN (tester stops beyond the first), launches, duration, tokens.
# The damage and friction columns stay `?`: the main session fills them in after reading. The rules version,
# when --rules is missing, is the one at the top of lite/CLAUDE.md next to this script.
set -euo pipefail

wave=""; rules=""
while [ $# -gt 0 ]; do
  case "$1" in
    --wave)   wave="${2:?errors: --wave needs <slug>-<n>}"; shift 2 ;;
    --rules) rules="${2:?errors: --rules needs a version, e.g. v7}"; shift 2 ;;
    *) echo "errors: unknown option: $1 (usage: errors.sh [--wave <slug>-<n>] [--rules v7])" >&2; exit 1 ;;
  esac
done
if [ -n "$wave" ] && [ -z "$rules" ]; then
  rules=$(head -1 "$(dirname "$0")/../CLAUDE.md" 2>/dev/null | grep -m1 -o 'v[0-9]\+' || true)
  rules="${rules:-?}"
fi

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "errors: not inside a git repo" >&2; exit 1; }
repo=$(dirname "$common")
dir="${ERRORS_DIR:-$HOME/.claude/logs/errors}"   # ERRORS_DIR only for the tests
launches="${LAUNCHES_DIR:-$HOME/.claude/logs/launches}"   # LAUNCHES_DIR only for the tests
agents="${AGENTS_DIR:-$HOME/.claude/agents}"     # AGENTS_DIR only for the tests: where the <agent>.md files with maxTurns live
mark="$dir/.read-$(printf '%s' "$repo" | shasum | cut -c1-12)"

python3 - "$dir" "$repo" "$mark" "$launches" "$agents" "$wave" "$rules" <<'EOF'
import json, sys, os, glob, datetime, re, collections
dir, repo, mark, launches, agents, wave, rules = sys.argv[1:]
since = open(mark).read().strip() if os.path.exists(mark) else ""
now = datetime.datetime.now().isoformat(timespec="seconds")
in_repo = lambda cwd: cwd == repo or cwd.startswith(repo + "/")
denied, again = [], []
for f in sorted(glob.glob(os.path.join(dir, "*.jsonl"))):
    if os.path.basename(f)[:10] < since[:10]:
        continue
    for line in open(f):
        d = json.loads(line)
        cwd = d.get("cwd") or ""
        if d["time"] <= since or not in_repo(cwd):
            continue
        if d["event"] == "PermissionDenied":
            denied.append(d)
        elif d.get("note") == "failed again":
            again.append(d)
one = lambda s, n: " ".join((s or "").split())[:n]
print(f"Errors of {repo} " + (f"from {since}" if since else "from the start of the logs") + f" to {now}")
print(f"\nDenied permissions: {len(denied)}")
for d in denied:
    print(f"- {d['time'][5:16].replace('T', ' ')} {d['agent']} {d['tool']}: {one(d['input'], 200)}")
    if d.get("other"):
        print(f"  → {one(d['other'], 300)}")
print(f"\nFailed again: {len(again)}")
for d in again:
    print(f"- {d['time'][5:16].replace('T', ' ')} {d['agent']} {d['tool']}: {one(d['input'], 160)}\n  → {one(d['error'], 200)}")

# Launches: every event in the register (30 days), paired by agent_id; a launch is new if its stop
# (or, without a stop, its start) is after the marker. The starts of a new launch may lie before the marker.
per_id = collections.OrderedDict()
new_stops = []   # every stop in the window: an agent resumed with SendMessage stops several times with the same agent_id
for f in sorted(glob.glob(os.path.join(launches, "*.jsonl"))):
    for line in open(f):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if not in_repo(d.get("cwd") or "") or not d.get("agent_id"):
            continue
        l = per_id.setdefault(d["agent_id"], {"agent": d.get("agent"), "compact": []})
        if d["event"] == "compact":
            l["compact"].append(d)
        else:
            l[d["event"]] = d
        if d["event"] == "stop" and d.get("time", "") > since:
            new_stops.append(d)
new_launches = [l for l in per_id.values() if (l.get("stop") or l.get("start") or {}).get("time", "") > since]
def max_turns(agent):
    # os.walk and not glob: the agent files also live in hidden folders (lite/.claude/agents/).
    for root, _, names in os.walk(agents, followlinks=True):
        if agent + ".md" in names:
            m = re.search(r"^maxTurns:\s*(\d+)", open(os.path.join(root, agent + ".md")).read(), re.M)
            if m:
                return int(m.group(1))
    return None
def minutes(l):
    if not (l.get("start") and l.get("stop")):
        return None
    a, b = (datetime.datetime.fromisoformat(l[k]["time"]) for k in ("start", "stop"))
    return max(0, int((b - a).total_seconds() // 60))
fmt_m = lambda m: f"{m}m" if m is not None else "?"
def fmt_tok(n):
    return f"{n/1e6:.1f}M" if n >= 1e6 else (f"{n//1000}k" if n >= 1000 else str(n))
per_type = collections.OrderedDict()
for l in new_launches:
    per_type.setdefault(l["agent"], []).append(l)
print(f"\nLaunches: {len(new_launches)}" + (" (" + ", ".join(f"{a} {len(ls)}" for a, ls in per_type.items()) + ")" if new_launches else ""))
near_limit, compacted, no_stop = [], [], []
for agent, ls in per_type.items():
    durations = [m for m in (minutes(l) for l in ls) if m is not None]
    row = f"- {agent:<12}{len(ls):>3}"
    if durations:
        row += f"  average duration {sum(durations)//len(durations)}m, max {max(durations)}m" if len(durations) > 1 else f"  duration {durations[0]}m"
    turns = [l["stop"]["turns"] for l in ls if l.get("stop", {}).get("turns")]
    mt = max_turns(agent)
    if turns:
        row += f"  turns max {max(turns)}" + (f"/{mt}" if mt else "")
    tin = sum(l["stop"].get("token_in", 0) + l["stop"].get("token_cache", 0) for l in ls if l.get("stop"))
    tout = sum(l["stop"].get("token_out", 0) for l in ls if l.get("stop"))
    if tin or tout:
        row += f"  tokens {fmt_tok(tin)} in, {fmt_tok(tout)} out"
    outcomes = collections.Counter(l["stop"].get("outcome", "other") for l in ls if l.get("stop"))
    if outcomes:
        row += "  outcomes: " + ", ".join(f"{e} {n}" for e, n in outcomes.most_common())
    print(row)
    for l in ls:
        aid = (l.get("start") or l.get("stop"))["agent_id"][:4]
        t = l.get("stop", {}).get("turns")
        if t and mt and t >= 0.8 * mt:
            near_limit.append(f"{agent} {aid} {t}/{mt}")
        for c in l["compact"]:
            compacted.append(f"{agent} {aid}, {c.get('trigger') or '?'}")
        if l.get("start") and not l.get("stop"):
            no_stop.append(f"{agent} {aid} since {l['start']['time'][11:16]}")
if near_limit:
    print("Near the turn limit (≥ 80% of maxTurns): " + "; ".join(near_limit))
print(f"Compactions: {len(compacted)}" + (" (" + "; ".join(compacted) + ")" if compacted else ""))
if no_stop:
    print("Without stop (maybe still running or interrupted): " + "; ".join(no_stop))

if wave:
    board = os.path.join(repo, "docs", "recap", "metrics.md")
    durations = [m for m in (minutes(l) for l in new_launches) if m is not None]
    tin = sum(l["stop"].get("token_in", 0) + l["stop"].get("token_cache", 0) for l in new_launches if l.get("stop"))
    tout = sum(l["stop"].get("token_out", 0) for l in new_launches if l.get("stop"))
    prs = sorted({d["pr"] for d in new_stops if d.get("pr")})
    columns = [now[:10], wave, rules,
               str(sum(1 for l in new_launches if l["agent"] == "developer")),
               ", ".join(str(p) for p in prs) if prs else "-",
               str(sum(1 for d in new_stops if d.get("outcome") == "CHANGES")),
               str(max(0, sum(1 for d in new_stops if d.get("agent") == "tester") - 1)),
               str(len(new_launches)),
               f"{sum(durations)}m" if durations else "?",
               f"{fmt_tok(tin)} in, {fmt_tok(tout)} out" if (tin or tout) else "?",
               "?", "?"]
    row = "| " + " | ".join(columns) + " |\n"
    os.makedirs(os.path.dirname(board), exist_ok=True)
    if not os.path.exists(board):
        with open(board, "w") as f:
            f.write("# Metrics per wave\n\n"
                    "One row per wave, written by `errors.sh --wave <slug>-<n>` at the end of the wave with the numbers of the launch register. "
                    "`damage` and `friction` are filled in by the main session after reading the errors (the number of rows written in `friction.md` and in the recap). "
                    "It shows, wave after wave and rules version after rules version, whether the flow improves.\n\n"
                    "| date | wave | rules | tasks | PRs | review rounds (CHANGES) | RERUN | launches | total duration | tokens | damage | friction |\n"
                    "|---|---|---|---|---|---|---|---|---|---|---|---|\n")
    with open(board, "a") as f:
        f.write(row)
    print(f"\nWave row appended to {os.path.relpath(board, repo)} (damage and friction to fill in): {row.strip()}")
os.makedirs(dir, exist_ok=True)
open(mark, "w").write(now)
EOF
