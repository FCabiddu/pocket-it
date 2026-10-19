#!/usr/bin/env bash
# Test cases of log-launches.sh + the launch summary and the board (--wave) in errors.sh: `bash lite/hooks/log-launches-cases.sh`.
# Exits with 1 if a case fails.
H=$(cd "$(dirname "$0")" && pwd)/log-launches.sh; E=$(cd "$(dirname "$0")/../bin" && pwd)/errors.sh
tmp=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$tmp"' EXIT
export ERRORS_DIR=$tmp/err LAUNCHES_DIR=$tmp/lanci AGENTS_DIR=$tmp/agenti
R=$tmp/repo; git init -q "$R"; ALTRO=$tmp/altro; git init -q "$ALTRO"; fail=0
mkdir -p "$AGENTS_DIR/lite/.claude/agents"; printf -- '---\nname: developer\nmaxTurns: 200\n---\n' > "$AGENTS_DIR/lite/.claude/agents/developer.md"
# Fake transcript of a subagent: N assistant lines with different requestIds and usage.
transcript() { python3 -c '
import json,sys
n=int(sys.argv[2])
with open(sys.argv[1],"w") as f:
    f.write(json.dumps({"type":"user","message":{"role":"user","content":"x"}})+"\n")
    for i in range(n):
        f.write(json.dumps({"type":"assistant","requestId":"req_%d"%i,"requestedModel":"claude-sonnet-5-5","message":{"role":"assistant","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":100,"cache_creation_input_tokens":20}}})+"\n")
        f.write(json.dumps({"type":"assistant","requestId":"req_%d"%i,"message":{"role":"assistant","usage":{"input_tokens":10,"output_tokens":5}}})+"\n")
' "$1" "$2"; }
# ev <event> <agent_id> <agent> <cwd> <extra json>
ev() { python3 -c 'import json,sys; d={"hook_event_name":sys.argv[1],"session_id":"s","agent_id":sys.argv[2],"agent_type":sys.argv[3],"cwd":sys.argv[4],"transcript_path":"/x/s.jsonl"}; d.update(json.loads(sys.argv[5])); print(json.dumps(d))' "$@" | bash "$H"; }
# Times: the start must be written before the stop; the duration is the difference, so to get minutes > 0
# the start time is rewritten in the file (real events arrive with the system time).
sposta_start() { python3 -c '
import json,sys,glob,datetime
for f in glob.glob(sys.argv[1]+"/*.jsonl"):
    rows=[json.loads(l) for l in open(f)]
    for r in rows:
        if r["event"]=="start" and r["agent_id"]==sys.argv[2]:
            r["time"]=(datetime.datetime.fromisoformat(r["time"])-datetime.timedelta(minutes=int(sys.argv[3]))).isoformat(timespec="seconds")
    open(f,"w").write("".join(json.dumps(r,ensure_ascii=False)+"\n" for r in rows))
' "$LAUNCHES_DIR" "$2" "$3"; }

transcript "$tmp/t170.jsonl" 170
transcript "$tmp/t3.jsonl" 3
ev SubagentStart a1b2 developer "$R" '{}'
sposta_start x a1b2 14
ev SubagentStop  a1b2 developer "$R" "{\"last_assistant_message\":\"PR: https://github.com/x/y/pull/12 (verso wave/x-1).\\nFatto: tutto.\",\"agent_transcript_path\":\"$tmp/t170.jsonl\"}"
ev SubagentStart c3d4 reviewer "$R" '{}'
ev SubagentStop  c3d4 reviewer "$R" "{\"last_assistant_message\":\"CHANGES — 1) alta — manca il test\",\"agent_transcript_path\":\"$tmp/t3.jsonl\"}"
ev PreCompact    a1b2 developer "$R" '{"trigger":"auto"}'
ev SubagentStart e5f6 tester "$R" '{}'
ev SubagentStart z9z9 developer "$ALTRO" '{}'
ev SubagentStop  z9z9 developer "$ALTRO" '{"last_assistant_message":"APPROVED"}'
printf '{rotto' | bash "$H"; rotto=$?
ev SubagentStop  n0n0 reviewer "$R" '{"last_assistant_message":"Non ho trovato niente di strano."}'
ev SubagentStart s1s1 security "$R" '{}'
ev SubagentStop  s1s1 security "$R" '{"last_assistant_message":"SECURITY OK"}'

out=$(cd "$R" && bash "$E")
c() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (expected $2, got $3)"; fail=1; fi; }
has() { printf '%s' "$out" | grep -c -- "$1"; }
c "start + stop → duration in minutes"              1 "$(has 'developer     1  duration 14m')"
c "CHANGES at the top of the report → outcome CHANGES" 1 "$(has 'outcomes: CHANGES 1')"
c "link to the PR → outcome pr"                     1 "$(has 'outcomes: pr 1')"
c "SECURITY OK → outcome SECURITY OK"             1 "$(has 'outcomes: SECURITY OK 1')"
c "report without markers → outcome other"          1 "$(has ', other 1')"
c "start without stop → Without stop line"          1 "$(has 'Without stop (maybe still running or interrupted): tester e5f6')"
c "170 turns on maxTurns 200 → Near the limit"      1 "$(has 'Near the turn limit (≥ 80% of maxTurns): developer a1b2 170/200')"
c "turns and tokens read from the transcript"       1 "$(has 'turns max 170/200  tokens 22k in, 850 out')"
c "PreCompact auto → Compactions: 1"                1 "$(has 'Compactions: 1 (developer a1b2, auto)')"
c "events of another repo do not appear"            0 "$(has 'z9z9')"
c "count per type"                                  1 "$(has 'Launches: 5 (developer 1, reviewer 2, tester 1, security 1)')"
c "broken JSON → exit 0"                            0 "$rotto"
c "broken JSON → no line written"                   0 "$(grep -c 'rotto' "$LAUNCHES_DIR"/*.jsonl)"
out=$(cd "$R" && bash "$E")
c "second run without new events → Launches: 0"     1 "$(has 'Launches: 0')"

# The marker has one-second precision: the events of the new window must fall in the following second.
sleep 1
# Board: a new window with 2 developers (PR 20 and 21), a resumed reviewer (CHANGES then APPROVED, same id),
# another reviewer (CHANGES), a tester stopped twice (ROSSO, then VERDE after RERUN).
M=$R/docs/recap/metrics.md
ev SubagentStart d1d1 developer "$R" '{}'
sposta_start x d1d1 10
ev SubagentStop  d1d1 developer "$R" "{\"last_assistant_message\":\"PR: https://github.com/x/y/pull/20\",\"agent_transcript_path\":\"$tmp/t3.jsonl\"}"
ev SubagentStart d2d2 developer "$R" '{}'
ev SubagentStop  d2d2 developer "$R" '{"last_assistant_message":"PR aperta: https://github.com/x/y/pull/21"}'
ev SubagentStart r1r1 reviewer "$R" '{}'
ev SubagentStop  r1r1 reviewer "$R" '{"last_assistant_message":"CHANGES — 1) media — nome sbagliato"}'
ev SubagentStop  r1r1 reviewer "$R" '{"last_assistant_message":"APPROVED"}'
ev SubagentStart r2r2 reviewer "$R" '{}'
ev SubagentStop  r2r2 reviewer "$R" '{"last_assistant_message":"CHANGES — 1) bassa — commento"}'
ev SubagentStart t1t1 tester "$R" '{}'
ev SubagentStop  t1t1 tester "$R" '{"last_assistant_message":"E2E RED — 1 bug app"}'
ev SubagentStop  t1t1 tester "$R" '{"last_assistant_message":"E2E GREEN"}'
out=$(cd "$R" && bash "$E" --wave prova-1 --rules v9)
oggi=$(date +%Y-%m-%d)
c "--wave creates the file with the heading"        1 "$(grep -c '^# Metrics per wave' "$M")"
c "table header"                                    1 "$(grep -c '^| date | wave | rules | tasks | PRs | review rounds (CHANGES) | RERUN | launches | total duration | tokens | damage | friction |$' "$M")"
c "wave row: tasks, PR, CHANGES, RERUN, launches, duration, tokens, ?" 1 "$(grep -c "^| $oggi | prova-1 | v9 | 2 | 20, 21 | 2 | 1 | 5 | 10m | 390 in, 15 out | ? | ? |$" "$M")"
c "the row is also printed on screen"               1 "$(has 'Wave row appended to docs/recap/metrics.md')"
versione=$(grep -m1 -o 'v[0-9]\+' "$(dirname "$E")/../CLAUDE.md")
out=$(cd "$R" && bash "$E" --wave prova-2)
c "second wave → appends a row, does not rewrite"   1 "$(grep -c '^# Metrics per wave' "$M")"
c "second wave without launches → row with 0 and ?" 1 "$(grep -c "^| $oggi | prova-2 | $versione | 0 | - | 0 | 0 | 0 | ? | ? | ? | ? |$" "$M")"
c "two data rows in total"                          2 "$(grep -c '^| 20' "$M")"
c "unknown option → exit 1"                         1 "$( (cd "$R" && bash "$E" --boh >/dev/null 2>&1); echo $?)"
c "without --wave the file does not change"         2 "$( (cd "$R" && bash "$E" >/dev/null); grep -c '^| 20' "$M")"
exit $fail
