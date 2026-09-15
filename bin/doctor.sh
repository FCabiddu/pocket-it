#!/usr/bin/env bash
# pocket-it doctor — zero-token pre-flight for a target project.
# Usage (from the project root): bash ~/.claude/agents/pocket-it/bin/doctor.sh [--wave N]
#   bash <this-script's-own-path> --accept-base   — after reviewing an intentional base-branch
#     rewrite (see the ERROR's own instructions), tell doctor to stop flagging it. Every command
#     doctor prints (recovery, accept) is a self-contained shell one-liner with an absolute path to
#     this script and every ref name shell-quoted: it runs as-is from any directory in any project.
# Exit 0 = ready to launch agents; exit 1 = problems listed (fix before launching).
set -uo pipefail
DOCTOR_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)/$(basename "${BASH_SOURCE[0]}")"
ACCEPT_BASE=0; [[ "${1:-}" == "--accept-base" ]] && ACCEPT_BASE=1
WAVE="${2:-}"; [[ "${1:-}" == "--wave" ]] || WAVE=""
python3 - "$WAVE" "$ACCEPT_BASE" "$DOCTOR_ABS" <<'PY'
import json, os, re, sys, glob, subprocess, shlex, shutil
wave = sys.argv[1]
accept_base = sys.argv[2] == "1"
doctor_abs = sys.argv[3]
errs, warns = [], []
def err(m): errs.append(m)
def warn(m): warns.append(m)
def sh(cmd):
    try: return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()
    except Exception: return ""

# 1. git + config
if not os.path.isdir(".git") and not sh("git rev-parse --show-toplevel"):
    err("not a git repository — worktree isolation and PRs need one")
cfg = {}
if os.path.exists(".pocket-it.json"):
    try: cfg = json.load(open(".pocket-it.json"))
    except Exception as e: err(f".pocket-it.json is not valid JSON: {e}")
    if sh("git ls-files .pocket-it.json") == "": err(".pocket-it.json is not committed — agents in worktrees will not see it")
else:
    warn(".pocket-it.json missing — agents use defaults (medium / automerge on / no pipeline / main)")
for k, allowed in {"scope": ("simple","medium","full"), "branching": ("flat","epic"), "motion": ("none","sober","expressive")}.items():
    if k in cfg and cfg[k] not in allowed: err(f".pocket-it.json {k}={cfg[k]!r} not in {allowed}")
for k in ("automerge","pipeline"):
    if k in cfg and not isinstance(cfg[k], bool): err(f".pocket-it.json {k} must be true/false")
tests = cfg.get("tests", {})
for k in ("integration","e2e"):
    if k in tests and tests[k] not in ("off","on-demand","on"): err(f".pocket-it.json tests.{k}={tests[k]!r} not in off/on-demand/on")
base = cfg.get("baseBranch","main")
if sh(f"git rev-parse --verify --quiet {base}") == "" and sh(f"git rev-parse --verify --quiet origin/{base}") == "":
    err(f"baseBranch {base!r} does not exist locally or on origin")

# 1b. base branch rewritten (force-push) or deleted on origin since the last doctor run (PI-29).
# Server-side branch protection is not available on every plan; this is the fallback that at least
# makes it visible, while it is still recoverable (git keeps the old commit around until gc runs).
# The seen commit lives under the shared git-common-dir (never committed, shared by every worktree).
# Classification never reads a git error message: git's text is localised on a build with NLS
# support, so "does the ref exist" comes only from `ls-remote --exit-code`'s own exit status (2 = no
# matching ref, git's documented, language-independent signal), never from stdout/stderr wording.
# Every command printed below is a self-contained one-liner: an absolute, shell-quoted path to THIS
# script (doctor_abs, resolved by the bash wrapper before python even starts) and shlex.quote() on
# every ref name — it must run as-is from any cwd in any project, not just from inside pocket-it.
# Invariant (PI-29 round 5): no command this script prints ever writes to origin, under any ref name
# — not the base, not a rescue branch either. A rewrite a script sees as "accidental" may have been
# done on purpose to remove something (a secret, e.g.); publishing the dropped history again, even
# under a new name, would defeat that. Recovery saves the lost commit to a LOCAL branch only; whether
# to publish it anywhere, and whether/how to restore the base, are decisions for a person.
GIT_ENV = {**os.environ, "LC_ALL": "C", "LANGUAGE": "C"}  # belt and braces for any stderr text still shown to a human
def _load_seen(path):
    d = {}
    if os.path.exists(path):
        for line in open(path, errors="ignore"):
            parts = line.split()
            if len(parts) == 2: d[parts[0]] = parts[1]
    return d
def _save_seen(path, d):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        for k, v in sorted(d.items()): f.write(f"{k} {v}\n")
def _classify_base(base, env):
    # ('ok'|'deleted'|'unreachable', detail) — from ls-remote's exit code alone, never from text.
    ls = subprocess.run(["git", "ls-remote", "--exit-code", "origin", f"refs/heads/{base}"],
                         capture_output=True, text=True, env=env)
    if ls.returncode == 0: return "ok", None
    if ls.returncode == 2: return "deleted", None
    stderr = ls.stderr.strip()
    return "unreachable", (stderr.splitlines()[-1] if stderr else "no network")

common_dir = sh("git rev-parse --git-common-dir")
has_origin = sh("git remote get-url origin") != ""
seen_file = os.path.join(os.path.abspath(common_dir), "pocket-it", "base-seen") if common_dir else None
qbase = shlex.quote(base)
accept_cmd = f"bash {shlex.quote(doctor_abs)} --accept-base"

if accept_base:
    # a human reviewed an intentional rewrite (per the ERROR's own instructions) and tells doctor to
    # stop flagging it. This only ever updates doctor's own bookkeeping file — never a git ref, a
    # branch or a commit — so by construction it cannot discard any local work.
    if not (seen_file and has_origin):
        print("doctor --accept-base: no origin remote configured — nothing to accept"); sys.exit(1)
    seen = _load_seen(seen_file)
    prev = seen.get(base)
    status, detail = _classify_base(base, GIT_ENV)
    if status == "deleted":
        if prev:
            has_prev = subprocess.run(["git", "cat-file", "-e", prev + "^{commit}"],
                                       capture_output=True, env=GIT_ENV).returncode == 0
            if has_prev:
                rescue_branch = f"rescue-{prev[:12]}"
                print(f"doctor --accept-base: base branch {base!r} no longer exists on origin — nothing to accept: "
                      f"save the lost commit locally before it can be lost: git branch {rescue_branch} {prev} — "
                      f"whether to publish that branch anywhere, and how to restore {base!r}, is a decision for a "
                      f"person, not this script; this command never pushes")
            else:
                print(f"doctor --accept-base: base branch {base!r} no longer exists on origin — nothing to accept: "
                      f"commit {prev} is also gone from the local object database (pruned) — recovery is not "
                      f"possible from this clone, check other clones or worktrees for it")
        else:
            print(f"doctor --accept-base: base branch {base!r} does not exist on origin — nothing to accept")
        sys.exit(1)
    if status == "unreachable":
        print(f"doctor --accept-base: could not reach origin to verify base branch {base!r} ({detail}) — try again once reachable")
        sys.exit(1)
    fetch = subprocess.run(["git", "fetch", "--quiet", "origin", f"+refs/heads/{base}:refs/remotes/origin/{base}"],
                            capture_output=True, text=True, env=GIT_ENV)
    if fetch.returncode != 0:
        stderr = fetch.stderr.strip()
        print(f"doctor --accept-base: fetch of {base!r} failed right after ls-remote confirmed it exists — "
              f"transient, try again ({stderr.splitlines()[-1] if stderr else 'no output'})")
        sys.exit(1)
    remote_sha = sh(f"git rev-parse refs/remotes/origin/{base}")
    _save_seen(seen_file, {**seen, base: remote_sha})
    print(f"doctor --accept-base: {base!r} accepted at {remote_sha} — future runs compare from here")
    sys.exit(0)

if common_dir and has_origin:
    seen = _load_seen(seen_file)
    prev = seen.get(base)
    status, detail = _classify_base(base, GIT_ENV)
    if status == "deleted":  # AC3
        if prev:
            has_prev = subprocess.run(["git", "cat-file", "-e", prev + "^{commit}"],
                                       capture_output=True, env=GIT_ENV).returncode == 0
            if has_prev:
                rescue_branch = f"rescue-{prev[:12]}"
                err(f"base branch {base!r} no longer exists on origin (last seen at {prev}) — "
                    f"save it locally before it can be lost: git branch {rescue_branch} {prev} — "
                    f"whether to publish that branch anywhere, and how to restore {base!r}, is a decision for a "
                    f"person, not this script; this command never pushes — then re-run doctor.sh")
            else:
                err(f"base branch {base!r} no longer exists on origin (last seen at {prev}) — "
                    f"commit {prev} is also gone from the local object database (pruned) — recovery is not "
                    f"possible from this clone, check other clones or worktrees for it")
        else:
            err(f"base branch {base!r} does not exist on origin")
    elif status == "unreachable":  # never a false ERROR
        warn(f"could not verify base branch {base!r} integrity — origin unreachable ({detail}), skipped")
    else:
        # ref exists on the remote: a real fetch (not ls-remote) is required from here — it forces the
        # remote-tracking ref to the live value even on a non-fast-forward (the leading '+') and pulls
        # down the objects the `merge-base --is-ancestor` below needs.
        fetch = subprocess.run(["git", "fetch", "--quiet", "origin", f"+refs/heads/{base}:refs/remotes/origin/{base}"],
                                capture_output=True, text=True, env=GIT_ENV)
        if fetch.returncode != 0:
            stderr = fetch.stderr.strip()
            warn(f"could not verify base branch {base!r} integrity — fetch failed ({stderr.splitlines()[-1] if stderr else 'no network'}), skipped")
        else:
            remote_sha = sh(f"git rev-parse refs/remotes/origin/{base}")
            if not prev:
                if remote_sha: _save_seen(seen_file, {**seen, base: remote_sha})  # AC4: first run, just record
            else:
                has_prev = subprocess.run(["git", "cat-file", "-e", prev + "^{commit}"], capture_output=True, env=GIT_ENV).returncode == 0
                if not has_prev:
                    warn(f"cannot verify base branch {base!r}: previously seen commit {prev} is missing from the local object database (shallow clone or pruned) — fetch full history to re-enable this check")
                else:
                    is_ancestor = subprocess.run(["git", "merge-base", "--is-ancestor", prev, remote_sha], capture_output=True, env=GIT_ENV).returncode == 0
                    if is_ancestor:
                        if remote_sha != prev: _save_seen(seen_file, {**seen, base: remote_sha})  # AC1: advanced normally
                    else:
                        # The recovery this script can perform on its own never writes to origin, under
                        # ANY name — not the base, not a side branch either. A script cannot tell an
                        # intentional rewrite from an accidental one, and an intentional rewrite can
                        # exist precisely to remove something (a secret, PI-29 round 5's own measured
                        # case) — publishing the old history under a new name on origin would defeat
                        # that on the spot, even though {base} itself is left untouched. So the printed
                        # command only ever creates a LOCAL branch; publishing it anywhere, and
                        # restoring {base}, are decisions for a person. has_prev (just checked above) is
                        # already true here, so {prev} is guaranteed present locally.
                        rescue_branch = f"rescue-{prev[:12]}"
                        save_cmd = f"git fetch origin && git branch {rescue_branch} {prev}"
                        err(
                            f"base branch {base!r} was rewritten on origin: commit {prev} is no longer in its history — "
                            f"see what changed: git log {prev}..refs/remotes/origin/{qbase} (added by the rewrite), "
                            f"git log refs/remotes/origin/{qbase}..{prev} (dropped by it) — "
                            f"the lost commit is still reachable locally: save it before it can be pruned away, "
                            f"locally only, this never pushes: {save_cmd} — "
                            f"restoring {base!r} to include it again, and whether to publish {rescue_branch} anywhere, "
                            f"are decisions for a person, not this script: doctor keeps reporting this as an error "
                            f"until {base!r} is restored, or, if the rewrite was intentional, then accept it with: {accept_cmd}"
                        )
                        # do not overwrite the seen commit here: keep reporting until it is fixed or explicitly accepted

# 2. board
tasks = {}
files = [f for f in glob.glob("tasks/**/*.md", recursive=True) if not f.endswith(("INDEX.md","README.md","/EPIC.md")) and not re.search(r"/(EPIC|STORY)-[^/]*\.md$", f)]
if not files: warn("tasks/ has no task files (run implementation-planner or quickfix first)")
hdr = re.compile(r"^\*\*([A-Za-z ]+?)(\*\*:|:\*\*)\s*(.*)$")
required = ["Status","Label","Files","TAD"]
id_files = {}  # declared id -> [files] — same extraction as next-wave.sh, so both scripts agree on what "same id" means
for f in files:
    txt = open(f, errors="ignore").read()
    m = re.match(r"^#\s*(?=[A-Za-z][A-Za-z0-9]*-[^\s:]*\d)([A-Za-z][A-Za-z0-9]*(?:[-.][A-Za-z0-9]+)+)", txt)  # a real id: a letter-led prefix (alphanumeric segments allowed, e.g. E2E, I18N) then one or more -/.  segments, with a digit somewhere past the first hyphen; never a plain hyphenated word ("Follow-up": no digit, lookahead fails) and never trailing punctuation ("T-2.1.1." stops at "T-2.1.1")
    tid = m.group(1) if m else os.path.basename(f).split("-")[0]
    if m: id_files.setdefault(m.group(1), []).append(f)  # only a genuinely declared id counts as a duplicate candidate; a filename-guessed fallback never does
    fields = {}
    for line in txt.splitlines()[:40]:
        h = hdr.match(line)
        if h: fields[h.group(1).strip()] = h.group(3).strip()
    tasks[tid] = {"file": f, "fields": fields}
    if "Status" not in fields: warn(f"{f}: no **Status** line — ignored by next-wave.sh (set Done or Todo)")
    if fields.get("Status","").lower() in ("todo","to do","in coda","in progress","needs work"):
        for r in required:
            if r not in fields: warn(f"{f}: missing **{r}** line (developer needs it)")
        if "## Acceptance criteria" not in txt and "## Description" not in txt: warn(f"{f}: no acceptance criteria section")
    if sh(f"git ls-files '{f}'") == "": err(f"{f} is not committed — a developer in a worktree will not find it")
    for dep in re.split(r"[,\s]+", fields.get("Depends on", fields.get("Depends On",""))):
        dep = dep.strip()
        if dep and dep.lower() not in ("none","nessuna","-") and re.match(r"^[A-Z]+-", dep) and dep not in tasks and not (glob.glob(f"tasks/**/{dep}-*.md", recursive=True) or glob.glob(f"tasks/**/{dep}.md", recursive=True)):
            (warn if fields.get("Status","").lower().startswith("done") else err)(f"{f}: depends on {dep} which has no task file")

for tid, tfiles in sorted(id_files.items()):
    if len(tfiles) > 1:
        err(f"duplicate task id {tid}: {', '.join(sorted(tfiles))}")

# 2b. legacy nested board: EPIC.md / STORY-n.m.md status vs their T-*.md children (summaries nobody updates)
status_re = re.compile(r"^\*\*Status(\*\*:|:\*\*)\s*(.*)$", re.M)
def summary_status(path):
    m = status_re.search(open(path, errors="ignore").read())
    return m.group(2).strip() if m else ""
for epic_dir in sorted(d for d in glob.glob("tasks/EPIC-*") if os.path.isdir(d)):
    epic_children = sorted(glob.glob(os.path.join(epic_dir, "T-*.md")))
    epic_file = os.path.join(epic_dir, "EPIC.md")
    if epic_children and os.path.exists(epic_file):
        st = summary_status(epic_file)
        if not st.lower().startswith("done") and all(summary_status(c).lower().startswith("done") for c in epic_children):
            warn(f'{epic_file}: says "{st}" but all {len(epic_children)} children are Done — update the summary')
    for story_file in sorted(glob.glob(os.path.join(epic_dir, "STORY-*.md"))):
        sm = re.match(r"STORY-([\d.]+)\.md$", os.path.basename(story_file))
        if not sm: continue
        prefix = f"T-{sm.group(1)}."
        story_children = sorted(c for c in epic_children if os.path.basename(c).startswith(prefix))
        if not story_children: continue
        st = summary_status(story_file)
        if not st.lower().startswith("done") and all(summary_status(c).lower().startswith("done") for c in story_children):
            warn(f'{story_file}: says "{st}" but all {len(story_children)} children are Done — update the summary')

# PI-37 CHECK BEGIN
# 2c. merged PR left on a non-Done task. A gap between two lanes: quickfix/SKILL.md already
# corrects Status to Done right after its own merge, run-wave/SKILL.md Step 5 now does too (same PR),
# this is the net for whoever else merges, or forgets. `gh` reachability is the ONLY thing this check
# is allowed to depend on; a slow or absent network must never slow doctor.sh down, so every `gh` call
# below carries Python's own subprocess timeout (no shell `timeout`/`gtimeout`: absent on macOS) and
# any failure — missing binary, no auth, no network, no permission on this repo — skips the whole
# check in silence: no warning, no error, nothing written. Read-only: never touches a task file.
if shutil.which("gh"):
    try:
        _auth = subprocess.run(["gh","auth","status"], capture_output=True, text=True, timeout=3)
        _gh_ready = _auth.returncode == 0
    except Exception:
        _gh_ready = False
    merged_prs = None
    if _gh_ready:
        try:
            _prs = subprocess.run(["gh","pr","list","--state","merged","--json","number","--limit","1000"],
                                   capture_output=True, text=True, timeout=5)
            if _prs.returncode == 0: merged_prs = {p["number"] for p in json.loads(_prs.stdout)}
        except Exception:
            merged_prs = None
    if merged_prs is not None:
        for tid, t in tasks.items():
            status = t["fields"].get("Status","").strip()
            if status.lower().startswith("done"): continue  # AC2: Done (+ any trailing note) with a merged PR is not the case this warns about — same "startswith" convention as the rest of this file (e.g. the Depends-on and legacy-summary checks above)
            m_pr = re.search(r"(?:pull/|#)\s*(\d+)", t["fields"].get("PR",""))  # AC2: no PR / open / closed-without-merge never matches a merged number below
            if not m_pr: continue
            num = int(m_pr.group(1))
            if num in merged_prs:
                warn(f"{t['file']}: PR #{num} is merged but **Status** is {status!r} — set it to Done (or reopen the PR if it should not have merged)")
# PI-37 CHECK END

# 3. DEPS.json
deps_files = glob.glob("implementation-plans/*_DEPS.json")
for df in deps_files:
    try: d = json.load(open(df))
    except Exception as e: err(f"{df}: invalid JSON: {e}"); continue
    dt = d.get("tasks")
    if not isinstance(dt, dict) or not isinstance(d.get("waves", {}), dict):
        warn(f"{df}: legacy DEPS format (no tasks/waves maps) — skipped, not used by next-wave.sh"); continue
    for tid, t in dt.items():
        if not (glob.glob(f"tasks/**/{tid}-*.md", recursive=True) or glob.glob(f"tasks/**/{tid}.md", recursive=True)): err(f"{df}: task {tid} has no file in tasks/")
        for dep in t.get("dependsOn", []):
            if dep not in dt and not (glob.glob(f"tasks/**/{dep}-*.md", recursive=True) or glob.glob(f"tasks/**/{dep}.md", recursive=True)): err(f"{df}: {tid} depends on unknown {dep}")
    for w, ids in (d.get("waves") or {}).items():
        seen = {}
        for tid in ids:
            for fpath in dt.get(tid, {}).get("files", []):
                if fpath in seen: err(f"{df}: wave {w}: {tid} and {seen[fpath]} both touch {fpath} — not parallel-safe")
                seen[fpath] = tid
            for dep in dt.get(tid, {}).get("dependsOn", []):
                if dep in ids: err(f"{df}: wave {w}: {tid} depends on {dep} in the same wave")
    if wave and wave in (d.get("waves") or {}):
        for tid in d["waves"][wave]:
            st = tasks.get(tid, {}).get("fields", {}).get("Status","?")
            if st.lower() == "done": warn(f"wave {wave}: {tid} already Done")

# 4a. BAD: project document + deltas
bad_project = os.path.exists("business-analysis/PROJECT_BUSINESS_ANALYSIS.md")
bad_full = sorted(glob.glob("business-analysis/*_BUSINESS_ANALYSIS.md"))
bad_deltas = sorted(glob.glob("business-analysis/*_BUSINESS_DELTA.md"))
if not bad_project and len(bad_full) > 1:
    warn(f"business-analysis/: {len(bad_full)} per-feature BADs and no PROJECT_BUSINESS_ANALYSIS.md — consolidation pending (/business-analyst consolidate)")
for bd in bad_deltas:
    if not bad_project and not bad_full: warn(f"{bd}: delta without a project BAD (PROJECT_BUSINESS_ANALYSIS.md) or a legacy *_BUSINESS_ANALYSIS.md to apply it to")
    txt = open(bd, errors="ignore").read()
    if not re.search(r"^## .*Impatto sul documento di progetto", txt, re.M): warn(f"{bd}: missing «Impatto sul documento di progetto» section")
    if not re.search(r"Given .*, when .*, then ", txt, re.I): warn(f"{bd}: no Given/When/Then acceptance criteria")
    if "US-1:" in txt and (bad_project or bad_full) and not re.search(r"supersedes US-1\b", txt): warn(f"{bd}: US-1 — story numbering restarted instead of continuing the project sequence")

# 4b. TAD numbering contract
for tad in glob.glob("tech-analysis/*_TECH_ANALYSIS.md"):
    txt = open(tad, errors="ignore").read()
    heads = re.findall(r"^## (\d+)\.", txt, re.M)
    nums = [int(h) for h in heads]
    if nums and nums != sorted(nums): err(f"{tad}: top-level sections out of order: {nums}")
    expected = {"5.2","6.2","7.6","8.1","9.3","11.1"}
    present = set(re.findall(r"^### (\d+\.\d+)", txt, re.M))
    missing = expected - present
    if missing and cfg.get("scope","medium") != "simple": warn(f"{tad}: subsections referenced by agents missing: {sorted(missing)}")

# 5. hygiene
if os.path.exists(".env") and sh("git ls-files .env"): err(".env is committed")
wt = sh("git worktree list | wc -l")
if wt and int(wt) > 12: warn(f"{wt} worktrees registered — prune the finished ones")
tmp = glob.glob("/tmp/*-automerge") + glob.glob("/tmp/*-pipeline")
if tmp: warn(f"legacy /tmp preference files present ({len(tmp)}) — ignored now, delete them")

for w in warns: print(f"warn  {w}")
for e in errs:  print(f"ERROR {e}")
print(f"doctor: {len(errs)} error(s), {len(warns)} warning(s), {len(files)} task file(s)")
sys.exit(1 if errs else 0)
PY
