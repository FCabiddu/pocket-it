#!/usr/bin/env bash
# Saves only the errors that matter, to be read back at the end of a wave with bin/errors.sh:
# - PermissionDenied: a denied permission;
# - PostToolUseFailure: every failed command, with note «first» or «failed again» ( an agent going round in circles).
# The agents' final reports are not saved: they already reach the main session, and in the log they were
# mostly «report delivered».
# One file per day in ~/.claude/logs/errors/; it disappears by itself after 7 days. It never blocks anything.
input=$(cat)
dir="${ERRORS_DIR:-$HOME/.claude/logs/errors}"; mkdir -p "$dir"   # ERRORS_DIR only for the tests
# Cleanup: the daily logs and the markers of the failed commands are thrown away after 7 days.
# Once a day, not at every event.
today="$dir/.cleaned-$(date +%F)"
if [ ! -e "$today" ]; then
  rm -f "$dir"/.cleaned-* 2>/dev/null
  : > "$today"
  find "$dir" -maxdepth 1 -name '*.jsonl' -mtime +7 -delete 2>/dev/null
  find "$dir/.seen" -type f -mtime +7 -delete 2>/dev/null
fi
printf '%s' "$input" | python3 -c '
import json, sys, os, hashlib, datetime
d = json.load(sys.stdin)
ev = d.get("hook_event_name", "")
log = os.path.join(sys.argv[1], datetime.date.today().isoformat() + ".jsonl")
base = {"time": datetime.datetime.now().isoformat(timespec="seconds"), "event": ev,
        "session": d.get("session_id"), "agent": d.get("agent_type") or "main", "cwd": d.get("cwd")}
cut = lambda s, n=600: (s or "")[:n]
if ev == "PostToolUseFailure":
    ti = json.dumps(d.get("tool_input", {}), sort_keys=True)
    key = hashlib.sha1((str(d.get("session_id")) + str(d.get("agent_id")) + d.get("tool_name", "") + ti).encode()).hexdigest()
    seen = os.path.join(sys.argv[1], ".seen")
    os.makedirs(seen, exist_ok=True)
    mark = os.path.join(seen, key)
    if not os.path.exists(mark):
        open(mark, "w").close()
        note = "first"
    else:
        note = "failed again"
    base.update(tool=d.get("tool_name"), input=cut(ti), error=cut(d.get("error")), note=note)
elif ev == "PermissionDenied":
    base.update(tool=d.get("tool_name"), input=cut(json.dumps(d.get("tool_input", {}))))
    # The reason for the denial: the field name is not documented, so everything not already above is saved.
    known = {"session_id", "transcript_path", "cwd", "hook_event_name", "tool_name", "tool_input",
            "tool_use_id", "agent_id", "agent_type", "permission_mode"}
    other = {k: v for k, v in d.items() if k not in known}
    if other:
        base["other"] = cut(json.dumps(other, ensure_ascii=False), 400)
else:
    sys.exit(0)
with open(log, "a") as f:
    f.write(json.dumps(base, ensure_ascii=False) + "\n")
' "$dir" 2>/dev/null
exit 0
