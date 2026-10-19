#!/usr/bin/env bash
# Register of the agent launches, to be read back at the end of a wave with bin/errori.sh:
# - SubagentStart: who starts (type, id, cwd);
# - SubagentStop: how it ended (outcome read from the first lines of the report, with fixed rules and no LLM),
#   turns, tokens and model read from the subagent's transcript;
# - PreCompact: a context compaction (an agent that compacts more than 2 times has a task that is too big).
# The duration is not saved: errori.sh computes it from the start/stop pair with the same agent_id.
# One file per day in ~/.claude/logs/lanci/; it disappears by itself after 30 days. It never blocks anything.
input=$(cat)
dir="${LANCI_DIR:-$HOME/.claude/logs/lanci}"; mkdir -p "$dir"   # LANCI_DIR only for the tests
# Cleanup: the daily logs are thrown away after 30 days. Once a day, not at every event.
oggi="$dir/.pulito-$(date +%F)"
if [ ! -e "$oggi" ]; then
  rm -f "$dir"/.pulito-* 2>/dev/null
  : > "$oggi"
  find "$dir" -maxdepth 1 -name '*.jsonl' -mtime +30 -delete 2>/dev/null
fi
printf '%s' "$input" | python3 -c '
import json, sys, os, re, datetime
d = json.load(sys.stdin)
ev = d.get("hook_event_name", "")
eventi = {"SubagentStart": "start", "SubagentStop": "stop", "PreCompact": "compact"}
if ev not in eventi:
    sys.exit(0)
log = os.path.join(sys.argv[1], datetime.date.today().isoformat() + ".jsonl")
base = {"ora": datetime.datetime.now().isoformat(timespec="seconds"), "evento": eventi[ev],
        "sessione": d.get("session_id"), "agent_id": d.get("agent_id"),
        "agente": d.get("agent_type") or "principale", "cwd": d.get("cwd")}
if ev == "SubagentStop":
    ultimo = " ".join((d.get("last_assistant_message") or "").split())
    testa = ultimo[:300]
    # Outcome: the first marker that appears in the first lines of the report.
    regole = [(r"\bAPPROVED\b", "APPROVED"), (r"\bCHANGES\b", "CHANGES"),
              (r"\bE2E VERDE\b", "E2E VERDE"), (r"\bE2E ROSS[OI]\b", "E2E ROSSO"), (r"\bE2E SCRITTI\b", "E2E SCRITTI"),
              (r"\bSICUREZZA OK\b", "SICUREZZA OK"), (r"\bSICUREZZA\s+[—-]", "SICUREZZA"),
              (r"github\.com/[^\s)]+/pull/(\d+)", "pr")]
    trovati = []
    for rx, nome in regole:
        m = re.search(rx, testa)
        if m:
            trovati.append((m.start(), nome, m.group(1) if m.groups() else None))
    if trovati:
        trovati.sort()
        base["esito"] = trovati[0][1]
        if trovati[0][2]:
            base["pr"] = int(trovati[0][2])
    else:
        base["esito"] = "altro"
    base["ultimo"] = testa
    # Turns, tokens and model from the transcript of the subagent (field agent_transcript_path; if missing it is derived
    # from the session transcript: <folder>/<session>/subagents/agent-<id>.jsonl).
    tp = d.get("agent_transcript_path")
    if not tp and d.get("transcript_path") and d.get("session_id") and d.get("agent_id"):
        tp = os.path.join(os.path.dirname(d["transcript_path"]), d["session_id"], "subagents", "agent-%s.jsonl" % d["agent_id"])
    if tp and os.path.isfile(tp):
        reqs, tin, tout, tcache, modello = set(), 0, 0, 0, None
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
                modello = r.get("requestedModel") or (r.get("message") or {}).get("model") or modello
        if reqs:
            base.update(turni=len(reqs), token_in=tin, token_out=tout, token_cache=tcache)
        if modello:
            base["modello"] = modello
elif ev == "PreCompact":
    base["trigger"] = d.get("trigger")
with open(log, "a") as f:
    f.write(json.dumps(base, ensure_ascii=False) + "\n")
' "$dir" 2>/dev/null
exit 0
