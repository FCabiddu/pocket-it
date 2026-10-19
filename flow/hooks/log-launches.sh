#!/usr/bin/env bash
# Register of the agent launches, to be read back at the end of a wave with bin/errors.sh:
# - SubagentStart: who starts (type, id, cwd);
# - SubagentStop: how it ended (outcome read from the first lines of the report, with fixed rules and no LLM),
#   turns, tokens and model read from the subagent's transcript;
# - PreCompact: a context compaction (an agent that compacts more than 2 times has a task that is too big).
# The duration is not saved: errors.sh computes it from the start/stop pair with the same agent_id.
# One file per day in ~/.claude/logs/launches/; it disappears by itself after 30 days. It never blocks anything.
input=$(cat)
dir="${LAUNCHES_DIR:-$HOME/.claude/logs/launches}"; mkdir -p "$dir"   # LAUNCHES_DIR only for the tests
# Cleanup: the daily logs are thrown away after 30 days. Once a day, not at every event.
today="$dir/.cleaned-$(date +%F)"
if [ ! -e "$today" ]; then
  rm -f "$dir"/.cleaned-* 2>/dev/null
  : > "$today"
  find "$dir" -maxdepth 1 -name '*.jsonl' -mtime +30 -delete 2>/dev/null
fi
printf '%s' "$input" | python3 -c '
import json, sys, os, re, datetime
d = json.load(sys.stdin)
ev = d.get("hook_event_name", "")
events = {"SubagentStart": "start", "SubagentStop": "stop", "PreCompact": "compact"}
if ev not in events:
    sys.exit(0)
log = os.path.join(sys.argv[1], datetime.date.today().isoformat() + ".jsonl")
base = {"time": datetime.datetime.now().isoformat(timespec="seconds"), "event": events[ev],
        "session": d.get("session_id"), "agent_id": d.get("agent_id"),
        "agent": d.get("agent_type") or "main", "cwd": d.get("cwd")}
if ev == "SubagentStop":
    last = " ".join((d.get("last_assistant_message") or "").split())
    head = last[:300]
    # Outcome: the first marker that appears in the first lines of the report.
    rules = [(r"\bAPPROVED\b", "APPROVED"), (r"\bCHANGES\b", "CHANGES"),
              (r"\bE2E GREEN\b", "E2E GREEN"), (r"\bE2E RED\b", "E2E RED"), (r"\bE2E WRITTEN\b", "E2E WRITTEN"),
              (r"\bSECURITY OK\b", "SECURITY OK"), (r"\bSECURITY\s+[—-]", "SECURITY"),
              (r"github\.com/[^\s)]+/pull/(\d+)", "pr")]
    found = []
    for rx, name in rules:
        m = re.search(rx, head)
        if m:
            found.append((m.start(), name, m.group(1) if m.groups() else None))
    if found:
        found.sort()
        base["outcome"] = found[0][1]
        if found[0][2]:
            base["pr"] = int(found[0][2])
    else:
        base["outcome"] = "other"
    base["last"] = head
    # Turns, tokens and model from the transcript of the subagent (field agent_transcript_path; if missing it is derived
    # from the session transcript: <folder>/<session>/subagents/agent-<id>.jsonl).
    tp = d.get("agent_transcript_path")
    if not tp and d.get("transcript_path") and d.get("session_id") and d.get("agent_id"):
        tp = os.path.join(os.path.dirname(d["transcript_path"]), d["session_id"], "subagents", "agent-%s.jsonl" % d["agent_id"])
    if tp and os.path.isfile(tp):
        reqs, tin, tout, tcache, model = set(), 0, 0, 0, None
        with open(tp) as f:
            for line in f:
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if r.get("type") != "assistant":
                    continue
                u = (r.get("message") or {}).get("usage") if isinstance(r.get("message"), dict) else None
                rid = r.get("requestId") or r.get("uuid")
                if not u or rid in reqs:
                    continue
                reqs.add(rid)
                tin += (u.get("input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0)
                tout += u.get("output_tokens") or 0
                tcache += u.get("cache_read_input_tokens") or 0
                model = r.get("requestedModel") or (r.get("message") or {}).get("model") or model
        if reqs:
            base.update(turns=len(reqs), token_in=tin, token_out=tout, token_cache=tcache)
        if model:
            base["model"] = model
elif ev == "PreCompact":
    base["trigger"] = d.get("trigger")
with open(log, "a") as f:
    f.write(json.dumps(base, ensure_ascii=False) + "\n")
' "$dir" 2>/dev/null
exit 0
