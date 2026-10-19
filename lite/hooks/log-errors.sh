#!/usr/bin/env bash
# Saves only the errors that matter, to be read back at the end of a wave with bin/errori.sh:
# - PermissionDenied: a denied permission;
# - PostToolUseFailure: every failed command, with note «primo» (first) or «fallito di nuovo» (failed again: an agent going round in circles).
# The agents' final reports are not saved: they already reach the main session, and in the log they were
# mostly «report delivered».
# One file per day in ~/.claude/logs/errori/; it disappears by itself after 7 days. It never blocks anything.
input=$(cat)
dir="${ERRORI_DIR:-$HOME/.claude/logs/errori}"; mkdir -p "$dir"   # ERRORI_DIR only for the tests
# Cleanup: the daily logs and the markers of the failed commands are thrown away after 7 days.
# Once a day, not at every event.
oggi="$dir/.pulito-$(date +%F)"
if [ ! -e "$oggi" ]; then
  rm -f "$dir"/.pulito-* 2>/dev/null
  : > "$oggi"
  find "$dir" -maxdepth 1 -name '*.jsonl' -mtime +7 -delete 2>/dev/null
  find "$dir/.visti" -type f -mtime +7 -delete 2>/dev/null
fi
printf '%s' "$input" | python3 -c '
import json, sys, os, hashlib, datetime
d = json.load(sys.stdin)
ev = d.get("hook_event_name", "")
log = os.path.join(sys.argv[1], datetime.date.today().isoformat() + ".jsonl")
base = {"ora": datetime.datetime.now().isoformat(timespec="seconds"), "evento": ev,
        "sessione": d.get("session_id"), "agente": d.get("agent_type") or "principale", "cwd": d.get("cwd")}
cut = lambda s, n=600: (s or "")[:n]
if ev == "PostToolUseFailure":
    ti = json.dumps(d.get("tool_input", {}), sort_keys=True)
    key = hashlib.sha1((str(d.get("session_id")) + str(d.get("agent_id")) + d.get("tool_name", "") + ti).encode()).hexdigest()
    seen = os.path.join(sys.argv[1], ".visti")
    os.makedirs(seen, exist_ok=True)
    mark = os.path.join(seen, key)
    if not os.path.exists(mark):
        open(mark, "w").close()
        nota = "primo"
    else:
        nota = "fallito di nuovo"
    base.update(strumento=d.get("tool_name"), input=cut(ti), errore=cut(d.get("error")), nota=nota)
elif ev == "PermissionDenied":
    base.update(strumento=d.get("tool_name"), input=cut(json.dumps(d.get("tool_input", {}))))
    # The reason for the denial: the field name is not documented, so everything not already above is saved.
    noti = {"session_id", "transcript_path", "cwd", "hook_event_name", "tool_name", "tool_input",
            "tool_use_id", "agent_id", "agent_type", "permission_mode"}
    altro = {k: v for k, v in d.items() if k not in noti}
    if altro:
        base["altro"] = cut(json.dumps(altro, ensure_ascii=False), 400)
else:
    sys.exit(0)
with open(log, "a") as f:
    f.write(json.dumps(base, ensure_ascii=False) + "\n")
' "$dir" 2>/dev/null
exit 0
