#!/usr/bin/env python3
"""pocket-it usage-report — where the tokens went, from Claude Code transcripts.

Usage:  python3 ~/.claude/agents/pocket-it/bin/usage-report.py [--days N] [project-dir ...]
Without arguments it reports on the current working directory's project. Reads ~/.claude/projects/
transcripts (main sessions + subagents), deduplicates resumed records, and prints: per-session
cost/context, subagent runs by type, runaway agents, tool-result volume, failure signatures.
"""
import json, glob, os, sys, re, collections, datetime

ROOT = os.path.expanduser("~/.claude/projects")
days, args, skip = 30, [], False
for i, a in enumerate(sys.argv[1:], 1):
    if skip: skip = False; continue
    if a == "--days" and i + 1 < len(sys.argv): days = int(sys.argv[i + 1]); skip = True; continue
    if not a.startswith("--"): args.append(a)
since = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=days)
targets = args or [os.getcwd()]

def proj_dir(path):
    return os.path.join(ROOT, "-" + os.path.abspath(path).strip("/").replace("/", "-"))
def load(p):
    out = []
    with open(p, errors="ignore") as f:
        for line in f:
            try: out.append(json.loads(line))
            except Exception: pass
    return out
def ts(r):
    t = r.get("timestamp")
    try: return datetime.datetime.fromisoformat(t.replace("Z", "+00:00")) if t else None
    except Exception: return None
def usage(r):
    u = ((r.get("message") or {}).get("usage") or {})
    return u.get("input_tokens", 0), u.get("cache_creation_input_tokens", 0), u.get("cache_read_input_tokens", 0), u.get("output_tokens", 0)
def rtext(cc):
    x = cc.get("content"); return x if isinstance(x, str) else " ".join(y.get("text", "") for y in (x or []) if isinstance(y, dict))

for target in targets:
    d = proj_dir(target)
    if not os.path.isdir(d):
        print(f"no transcripts for {target} (looked in {d})"); continue
    print(f"\n{'#'*90}\n# {target}   (last {days} days)\n{'#'*90}")
    seen = set()
    # map subagent transcript id -> subagent_type, from the parents' Agent tool calls/results
    agent_type = {}
    for mp in glob.glob(os.path.join(d, "*.jsonl")):
        idx = {}
        for r in load(mp):
            if r.get("type") == "assistant":
                for cc in (r.get("message") or {}).get("content") or []:
                    if isinstance(cc, dict) and cc.get("type") == "tool_use" and cc.get("name") == "Agent":
                        idx[cc.get("id")] = (cc.get("input") or {}).get("subagent_type") or "general-purpose"
            elif r.get("type") == "user":
                cont = (r.get("message") or {}).get("content")
                if isinstance(cont, list):
                    for cc in cont:
                        if isinstance(cc, dict) and cc.get("type") == "tool_result" and cc.get("tool_use_id") in idx:
                            m = re.search(r"agentId:\s*([0-9a-f]{8,})", rtext(cc))
                            if m: agent_type[m.group(1)] = idx[cc["tool_use_id"]]
    print("\n== main sessions")
    print(f"{'date':10} {'sid':8} {'model':18} {'calls':>5} {'ctx_avg':>8} {'ctx_max':>8} {'agents':>6} {'bash':>5} {'hours':>5} {'cost$':>7}")
    tot_cost = 0.0
    for mp in sorted(glob.glob(os.path.join(d, "*.jsonl"))):
        recs = load(mp)
        times = [t for t in (ts(r) for r in recs) if t]
        if not times or max(times) < since: continue
        ctxs, models, n_agent, n_bash = [], collections.Counter(), 0, 0
        for r in recs:
            if r.get("type") != "assistant": continue
            key = ((r.get("message") or {}).get("id"), r.get("uuid"))
            if key in seen: continue
            seen.add(key)
            i, cw, cr, o = usage(r)
            if i + cw + cr: ctxs.append(i + cw + cr)
            models[(r.get("message") or {}).get("model") or "?"] += 1
            for cc in (r.get("message") or {}).get("content") or []:
                if isinstance(cc, dict) and cc.get("type") == "tool_use":
                    if cc.get("name") == "Agent": n_agent += 1
                    if cc.get("name") == "Bash": n_bash += 1
        cost = next((r for r in recs if r.get("type") == "cost-state"), None)
        c = cost.get("totalCostUSD") if cost else None
        if c: tot_cost += c
        hours = (max(times) - min(times)).total_seconds() / 3600
        mdl = models.most_common(1)[0][0].replace("claude-", "") if models else "?"
        print(f"{min(times).strftime('%Y-%m-%d'):10} {os.path.basename(mp)[:8]:8} {mdl[:18]:18} {len(ctxs):5} {int(sum(ctxs)/len(ctxs)) if ctxs else 0:8} {max(ctxs) if ctxs else 0:8} {n_agent:6} {n_bash:5} {hours:5.1f} {str(round(c)) if c else '-':>7}")
        if ctxs and sum(ctxs) / len(ctxs) > 250000: print("      ^ contesto medio > 250k: sessione troppo lunga o modello 1M — una sessione per epica, /compact")
        if n_bash > 200 and n_agent < 5: print("      ^ molti Bash e pochi agenti: la sessione principale sta implementando da sola")
    if tot_cost: print(f"costo registrato (dove presente): ${tot_cost:.0f}")

    print("\n== subagents by type")
    rows = []
    for sp in glob.glob(os.path.join(d, "*/subagents/*.jsonl")):
        recs = load(sp)
        times = [t for t in (ts(r) for r in recs) if t]
        if not times or max(times) < since: continue
        first = next((r for r in recs if r.get("type") == "user"), None)
        cont = (first.get("message") or {}).get("content") if first else ""
        prompt = cont if isinstance(cont, str) else json.dumps(cont)[:3000]
        aid = re.sub(r"^agent-", "", os.path.basename(sp).replace(".jsonl", ""))
        atype = agent_type.get(aid)
        m = re.search(r"agents/(?:pocket-it/\.claude/agents/)?([a-z-]+)\.md", prompt or "")
        if not atype and m: atype = m.group(1)
        if not atype:
            m2 = re.search(r"Issue:\s*([A-Z]+-[\d.]+)", prompt or "")
            atype = "developer?" if m2 else "inline"
        calls, ctxs, out, errs, tools = 0, [], 0, 0, collections.Counter()
        idx = {}
        for r in recs:
            if r.get("type") == "assistant":
                key = ((r.get("message") or {}).get("id"), r.get("uuid"))
                if key in seen: continue
                seen.add(key); calls += 1
                i, cw, cr, o = usage(r); out += o
                if i + cw + cr: ctxs.append(i + cw + cr)
                for cc in (r.get("message") or {}).get("content") or []:
                    if isinstance(cc, dict) and cc.get("type") == "tool_use": tools[cc.get("name")] += 1; idx[cc.get("id")] = cc.get("name")
            elif r.get("type") == "user":
                cont = (r.get("message") or {}).get("content")
                if isinstance(cont, list):
                    for cc in cont:
                        if isinstance(cc, dict) and cc.get("type") == "tool_result" and cc.get("is_error"): errs += 1
        if calls: rows.append((atype, calls, int(sum(ctxs)/len(ctxs)) if ctxs else 0, max(ctxs) if ctxs else 0, out, sum(ctxs), errs, os.path.basename(sp)[:12], tools))
    by = collections.defaultdict(list)
    for r in rows: by[r[0]].append(r)
    print(f"{'type':22} {'n':>4} {'calls':>6} {'ctx_avg':>8} {'ctx_max':>8} {'out_k':>6} {'readM':>7} {'errs':>5}")
    for t, rs in sorted(by.items(), key=lambda kv: -sum(r[5] for r in kv[1])):
        n = len(rs)
        print(f"{t[:22]:22} {n:4} {sum(r[1] for r in rs)/n:6.0f} {sum(r[2] for r in rs)/n:8.0f} {max(r[3] for r in rs):8} {sum(r[4] for r in rs)/n/1000:6.1f} {sum(r[5] for r in rs)/1e6:7.0f} {sum(r[6] for r in rs):5}")
    run = [r for r in rows if r[1] > 150 or r[3] > 250000]
    if run:
        print(f"\n== runaway agents ({len(run)}): >150 turns or >250k context")
        for r in sorted(run, key=lambda r: -r[5])[:10]:
            print(f"  {r[0][:18]:18} calls={r[1]:4} ctx_max={r[3]:7} read={r[5]/1e6:5.0f}M errs={r[6]:3} id={r[7]} tools={dict(r[8].most_common(3))}")

    print("\n== failure signatures (tool results)")
    sig = collections.Counter()
    pats = {"own-PR review refused": "your own pull request", "PR not found": "Could not resolve to a PullRequest",
            "usage limit": "You've hit", "API error killed agent": "terminated early due to an API error",
            "classifier denied": "auto mode classifier", "worktree isolation block": "This agent is isolated in the worktree",
            "sleep blocked": "Blocked: sleep", "guard blocked": "BLOCKED by pocket-it guard", "AskUserQuestion in subagent": "AskUserQuestion"}
    for p in glob.glob(os.path.join(d, "**/*.jsonl"), recursive=True):
        for r in load(p):
            if r.get("type") != "user": continue
            t = ts(r)
            if t and t < since: continue
            cont = (r.get("message") or {}).get("content")
            txts = [rtext(cc) for cc in cont if isinstance(cc, dict) and cc.get("type") == "tool_result" and cc.get("is_error")] if isinstance(cont, list) else ([cont] if isinstance(cont, str) and "<task-notification>" in cont else [])
            for x in txts:
                for k, needle in pats.items():
                    if needle in x: sig[k] += 1
    for k, v in sig.most_common(): print(f"  {v:5}  {k}")
    if not sig: print("  none")
