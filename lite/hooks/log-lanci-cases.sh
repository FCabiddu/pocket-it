#!/usr/bin/env bash
# Casi di prova di log-lanci.sh + il riassunto dei lanci e il tabellone (--onda) in errori.sh: `bash lite/hooks/log-lanci-cases.sh`.
# Esce con 1 se un caso fallisce.
H=$(cd "$(dirname "$0")" && pwd)/log-lanci.sh; E=$(cd "$(dirname "$0")/../bin" && pwd)/errori.sh
tmp=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$tmp"' EXIT
export ERRORI_DIR=$tmp/err LANCI_DIR=$tmp/lanci AGENTI_DIR=$tmp/agenti
R=$tmp/repo; git init -q "$R"; ALTRO=$tmp/altro; git init -q "$ALTRO"; fail=0
mkdir -p "$AGENTI_DIR/lite/.claude/agents"; printf -- '---\nname: developer\nmaxTurns: 200\n---\n' > "$AGENTI_DIR/lite/.claude/agents/developer.md"
# Transcript finto di un subagente: N righe assistant con requestId diversi e usage.
transcript() { python3 -c '
import json,sys
n=int(sys.argv[2])
with open(sys.argv[1],"w") as f:
    f.write(json.dumps({"type":"user","message":{"role":"user","content":"x"}})+"\n")
    for i in range(n):
        f.write(json.dumps({"type":"assistant","requestId":"req_%d"%i,"requestedModel":"claude-sonnet-5-5","message":{"role":"assistant","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":100,"cache_creation_input_tokens":20}}})+"\n")
        f.write(json.dumps({"type":"assistant","requestId":"req_%d"%i,"message":{"role":"assistant","usage":{"input_tokens":10,"output_tokens":5}}})+"\n")
' "$1" "$2"; }
# ev <evento> <agent_id> <agente> <cwd> <json in più>
ev() { python3 -c 'import json,sys; d={"hook_event_name":sys.argv[1],"session_id":"s","agent_id":sys.argv[2],"agent_type":sys.argv[3],"cwd":sys.argv[4],"transcript_path":"/x/s.jsonl"}; d.update(json.loads(sys.argv[5])); print(json.dumps(d))' "$@" | bash "$H"; }
# Ore: lo start va scritto prima dello stop; la durata la dà la differenza, quindi per avere minuti > 0
# si riscrive l'ora dello start nel file (gli eventi veri arrivano con l'ora di sistema).
sposta_start() { python3 -c '
import json,sys,glob,datetime
for f in glob.glob(sys.argv[1]+"/*.jsonl"):
    rows=[json.loads(l) for l in open(f)]
    for r in rows:
        if r["evento"]=="start" and r["agent_id"]==sys.argv[2]:
            r["ora"]=(datetime.datetime.fromisoformat(r["ora"])-datetime.timedelta(minutes=int(sys.argv[3]))).isoformat(timespec="seconds")
    open(f,"w").write("".join(json.dumps(r,ensure_ascii=False)+"\n" for r in rows))
' "$LANCI_DIR" "$2" "$3"; }

transcript "$tmp/t170.jsonl" 170
transcript "$tmp/t3.jsonl" 3
ev SubagentStart a1b2 developer "$R" '{}'
sposta_start x a1b2 14
ev SubagentStop  a1b2 developer "$R" "{\"last_assistant_message\":\"PR: https://github.com/x/y/pull/12 (verso onda/x-1).\\nFatto: tutto.\",\"agent_transcript_path\":\"$tmp/t170.jsonl\"}"
ev SubagentStart c3d4 reviewer "$R" '{}'
ev SubagentStop  c3d4 reviewer "$R" "{\"last_assistant_message\":\"CHANGES — 1) alta — manca il test\",\"agent_transcript_path\":\"$tmp/t3.jsonl\"}"
ev PreCompact    a1b2 developer "$R" '{"trigger":"auto"}'
ev SubagentStart e5f6 tester "$R" '{}'
ev SubagentStart z9z9 developer "$ALTRO" '{}'
ev SubagentStop  z9z9 developer "$ALTRO" '{"last_assistant_message":"APPROVED"}'
printf '{rotto' | bash "$H"; rotto=$?
ev SubagentStop  n0n0 reviewer "$R" '{"last_assistant_message":"Non ho trovato niente di strano."}'
ev SubagentStart s1s1 security "$R" '{}'
ev SubagentStop  s1s1 security "$R" '{"last_assistant_message":"SICUREZZA OK"}'

out=$(cd "$R" && bash "$E")
c() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (atteso $2, ottenuto $3)"; fail=1; fi; }
has() { printf '%s' "$out" | grep -c -- "$1"; }
c "start + stop → durata in minuti"                 1 "$(has 'developer     1  durata 14m')"
c "CHANGES in testa al report → esito CHANGES"      1 "$(has 'esiti: CHANGES 1')"
c "link alla PR → esito pr"                         1 "$(has 'esiti: pr 1')"
c "SICUREZZA OK → esito SICUREZZA OK"               1 "$(has 'esiti: SICUREZZA OK 1')"
c "report senza marcatori → esito altro"            1 "$(has ', altro 1')"
c "start senza stop → riga Senza stop"              1 "$(has 'Senza stop (forse ancora in corso o interrotti): tester e5f6')"
c "170 turni su maxTurns 200 → Vicini al limite"    1 "$(has 'Vicini al limite di turni (≥ 80% di maxTurns): developer a1b2 170/200')"
c "turni e token letti dal transcript"              1 "$(has 'turni max 170/200  token 22k in, 850 out')"
c "PreCompact auto → Compattazioni: 1"              1 "$(has 'Compattazioni: 1 (developer a1b2, auto)')"
c "eventi di un altro repo non compaiono"           0 "$(has 'z9z9')"
c "conteggio per tipo"                              1 "$(has 'Lanci: 5 (developer 1, reviewer 2, tester 1, security 1)')"
c "JSON rotto → exit 0"                             0 "$rotto"
c "JSON rotto → nessuna riga scritta"               0 "$(grep -c 'rotto' "$LANCI_DIR"/*.jsonl)"
out=$(cd "$R" && bash "$E")
c "secondo lancio senza eventi nuovi → Lanci: 0"    1 "$(has 'Lanci: 0')"

# Il segnaposto ha la precisione del secondo: gli eventi della finestra nuova devono stare nel secondo dopo.
sleep 1
# Tabellone: una finestra nuova con 2 developer (PR 20 e 21), un reviewer ripreso (CHANGES poi APPROVED, stesso id),
# un altro reviewer (CHANGES), un tester fermato due volte (ROSSO, poi VERDE dopo RIGIRA).
M=$R/docs/recap/metriche.md
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
ev SubagentStop  t1t1 tester "$R" '{"last_assistant_message":"E2E ROSSO — 1 bug app"}'
ev SubagentStop  t1t1 tester "$R" '{"last_assistant_message":"E2E VERDE"}'
out=$(cd "$R" && bash "$E" --onda prova-1 --regole v9)
oggi=$(date +%Y-%m-%d)
c "--onda crea il file con l'intestazione"          1 "$(grep -c '^# Metriche per onda' "$M")"
c "intestazione della tabella"                      1 "$(grep -c '^| data | onda | regole | task | PR | giri di review (CHANGES) | RIGIRA | lanci | durata totale | token | danni | attriti |$' "$M")"
c "riga dell'onda: task, PR, CHANGES, RIGIRA, lanci, durata, token, ?" 1 "$(grep -c "^| $oggi | prova-1 | v9 | 2 | 20, 21 | 2 | 1 | 5 | 10m | 390 in, 15 out | ? | ? |$" "$M")"
c "la riga si stampa anche a video"                 1 "$(has 'Riga dell.onda aggiunta a docs/recap/metriche.md')"
versione=$(grep -m1 -o 'v[0-9]\+' "$(dirname "$E")/../CLAUDE.md")
out=$(cd "$R" && bash "$E" --onda prova-2)
c "seconda onda → aggiunge una riga, non riscrive"  1 "$(grep -c '^# Metriche per onda' "$M")"
c "seconda onda senza lanci → riga con 0 e ?"       1 "$(grep -c "^| $oggi | prova-2 | $versione | 0 | - | 0 | 0 | 0 | ? | ? | ? | ? |$" "$M")"
c "due righe di dati in tutto"                      2 "$(grep -c '^| 20' "$M")"
c "opzione sconosciuta → exit 1"                    1 "$( (cd "$R" && bash "$E" --boh >/dev/null 2>&1); echo $?)"
c "senza --onda il file non cambia"                 2 "$( (cd "$R" && bash "$E" >/dev/null); grep -c '^| 20' "$M")"
exit $fail
