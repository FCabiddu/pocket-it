#!/usr/bin/env bash
# pocket-it install-drift — the installed dependency tree against the lockfile, and the reinstall that closes
# the gap. Two subcommands, one shared declaration of what a lockfile is and which install command owns it.
#
# Usage (from anywhere; <dir> defaults to the current directory):
#   bash install-drift.sh check     [<dir>]
#   bash install-drift.sh reinstall [<dir>] [--since <ref>] [--except <branch>] [--running <what>] [--dry-run]
#   bash install-drift.sh lockfiles          # the lockfile names this script knows, one per line
#
# THREAT MODEL — stated here because a guard whose failure mode is silence is worth nothing without one.
# What it protects against: a verification passing while the installed tree is NOT the tree the lockfile
# declares. A merged dependency bump leaves every checkout that is not reinstalled running the previous
# versions; every later test run and every verify.sh is then green about code nobody is shipping, and no
# red ever appears to reveal it. So a package whose installed version disagrees with the lockfile, and a
# lockfile shape this script cannot read, both produce OUTPUT AND A NON-ZERO EXIT — never a silent pass.
# What it deliberately leaves to another layer:
#  * it compares versions, never file contents: a package edited in place at the version the lockfile names
#    (a patch applied by hand, a partially written install) is indistinguishable from a clean one here.
#  * only npm-format lockfiles are read (package-lock.json, npm-shrinkwrap.json). pnpm, yarn and bun keep
#    their own formats, which no standard-library parser on this machine can read; they are reported
#    "NOT SUPPORTED", by name, on their own line, and the exit code says so. They are never called clean.
#  * an entry the lockfile carries without a version (a workspace link) is counted and reported, not compared.
#  * `reinstall` decides "is something running against this checkout" from LIVE PROCESSES (see live_runs),
#    never from the mere existence of a worktree: worktree.sh registers and locks one at creation and only
#    cleanup-merged.sh releases it, so a registered worktree routinely outlives the agent that owned it by
#    days, and treating registration as liveness defers every reinstall forever (measured on this repo's own
#    checkout: 9 worktrees registered, 7 locked, most of them of branches merged long before). What it can
#    read is this user's own processes, and only their current directory: an agent that has chdir'd out of
#    the checkout while still using its node_modules is invisible to it — which is why --running exists, for
#    a caller that knows it launched one, and why an unreadable process list defers instead of installing.
#
# Exit codes, both subcommands:
#   0  nothing to do — the install matches the lockfile, or there is nothing to compare (no lockfile, no
#      node_modules, non-JS project). This is the ONLY code that means "no disagreement was found".
#   1  check: the installed tree disagrees with the lockfile · reinstall: the install command failed.
#   2  usage error.
#   3  no verdict could be reached: the lockfile's format is not supported, or it cannot be parsed. Never
#      reported as clean, never as drift.
#   4  reinstall only: DEFERRED — not run, because something is running against this checkout.
set -uo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# ONE declaration of the lockfiles this script knows and the package manager each belongs to. Both halves of
# the script read it (the drift check and the reinstall command table) and so does the test suite, which
# iterates it rather than a list of its own: a lockfile added here is covered by every case the suite builds.
LOCKFILES="package-lock.json:npm npm-shrinkwrap.json:npm pnpm-lock.yaml:pnpm yarn.lock:yarn bun.lockb:bun bun.lock:bun"
# The package managers whose lockfile this script can actually read. Everything else is NOT SUPPORTED, loudly.
SUPPORTED_PM="npm"

usage() {
  cat >&2 <<'U'
usage: install-drift.sh check     [<dir>]
       install-drift.sh reinstall [<dir>] [--since <ref>] [--except <branch>] [--running <what>] [--dry-run]
       install-drift.sh lockfiles
  check      compares the installed tree in <dir> with its lockfile (exit 0 match / 1 drift / 3 no verdict)
  reinstall  runs the lockfile's own frozen install in <dir> when it is needed and nothing is running there
  lockfiles  prints the lockfile names this script knows, one per line, for callers that need the same list
U
  exit 2
}

# install_cmd <pm> — the frozen install that makes an installed tree match that package manager's lockfile.
# Frozen in every case on purpose: a plain install may CHANGE the lockfile, which is the opposite of the job.
install_cmd() {
  case "$1" in
    npm)  echo "npm ci";;
    pnpm) echo "pnpm install --frozen-lockfile";;
    # yarn berry refuses --frozen-lockfile; classic refuses --immutable. The lockfile's own header (berry
    # writes __metadata:) and .yarnrc.yml tell them apart without running yarn at all.
    yarn) if [[ -f "$DIR/.yarnrc.yml" ]] || grep -q '^__metadata:' "$DIR/yarn.lock" 2>/dev/null
          then echo "yarn install --immutable"; else echo "yarn install --frozen-lockfile"; fi;;
    bun)  echo "bun install --frozen-lockfile";;
    *)    return 1;;
  esac
}

SUB="${1:-}"; [[ $# -gt 0 ]] && shift
case "$SUB" in
  check|reinstall) ;;
  # N1: one declaration, readable from outside. verify.sh asks for it instead of keeping a second list that
  # goes stale the day a lockfile is added here — which is how a branch that changes bun.lock or
  # npm-shrinkwrap.json reads as "lockfile unchanged" and borrows another checkout's node_modules.
  lockfiles) for item in $LOCKFILES; do printf '%s\n' "${item%%:*}"; done; exit 0;;
  *) usage;;
esac

DIR="."; SINCE=""; EXCEPT=""; RUNNING=""; DRYRUN=0; DOLOG=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)   SINCE="${2:-}"; [[ -n "$SINCE" ]] || usage; shift 2;;
    --except)  [[ -n "${2:-}" ]] || usage; EXCEPT="$EXCEPT ${2}"; shift 2;;
    --running) RUNNING="${2:-}"; [[ -n "$RUNNING" ]] || usage; shift 2;;
    --dry-run) DRYRUN=1; shift;;
    --no-log)  DOLOG=0; shift;;
    -*)        usage;;
    *)         DIR="$1"; shift;;
  esac
done
[[ -d "$DIR" ]] || { echo "install-drift: usage error — no such directory: $DIR" >&2; exit 2; }
DIR=$(cd "$DIR" && pwd -P)

# present_locks — one "<lockfile>:<pm>" per lockfile actually present in $DIR, in the order declared above.
present_locks() {
  local item f
  for item in $LOCKFILES; do
    f="${item%%:*}"
    [[ -e "$DIR/$f" ]] && printf '%s\n' "$item"
  done
}

# check_tree — compares every entry of every readable lockfile with what is installed, and says so.
check_tree() {
  local cmds="" item pm c
  for item in $LOCKFILES; do
    pm="${item#*:}"
    c=$(install_cmd "$pm") && cmds="$cmds$pm=$c
"
  done
  python3 - "$DIR" "$LOCKFILES" "$SUPPORTED_PM" "$cmds" <<'PY'
import json, os, sys

d, decl, supported, cmds = sys.argv[1], sys.argv[2], sys.argv[3].split(), sys.argv[4]
CMD = dict(l.split("=", 1) for l in cmds.splitlines() if "=" in l)
MAXLINES = 10

locks = []
for item in decl.split():
    f, _, pm = item.partition(":")
    if os.path.exists(os.path.join(d, f)):
        locks.append((f, pm))
if not locks:
    print("install-drift: SKIP — no lockfile in %s, nothing to compare" % d)
    sys.exit(0)
# isdir follows symlinks on purpose: a worktree that borrows another checkout's node_modules through a
# symlink is exactly the tree this check has to be able to read.
if not os.path.isdir(os.path.join(d, "node_modules")):
    print("install-drift: SKIP — no node_modules in %s, nothing is installed to compare" % d)
    sys.exit(0)


def npm_entries(path):
    """({path under the checkout: lock entry}, error) for an npm lockfile of any version."""
    try:
        data = json.load(open(path))
    except Exception as exc:
        return None, "cannot be parsed (%s)" % type(exc).__name__
    if not isinstance(data, dict):
        return None, "is not a JSON object"
    out = {}
    packages = data.get("packages")
    if isinstance(packages, dict) and packages:          # lockfileVersion 2 and 3
        for k, v in packages.items():
            if isinstance(v, dict) and k.startswith("node_modules/"):
                out[k] = v
        return out, None
    deps = data.get("dependencies")
    if isinstance(deps, dict) and deps:                  # lockfileVersion 1 (and v2's compatibility block)
        def walk(prefix, tree):
            for name, v in tree.items():
                if not isinstance(v, dict):
                    continue
                rel = prefix + "/" + name
                out[rel] = v
                sub = v.get("dependencies")
                if isinstance(sub, dict):
                    walk(rel + "/node_modules", sub)
        walk("node_modules", deps)
        return out, None
    return None, ("declares neither \"packages\" nor \"dependencies\" (lockfileVersion %s)"
                  % json.dumps(data.get("lockfileVersion")))


def installed(rel):
    """(version, reason) — the version in the installed package.json, or why there is none."""
    p = os.path.join(d, rel, "package.json")
    if not os.path.exists(p):
        return None, "absent"
    try:
        v = json.load(open(p)).get("version")
    except Exception:
        return None, "unreadable"
    if not isinstance(v, str):
        return None, "unreadable"
    return v, None


drift_total = 0
no_verdict = 0
lines = []
summary = []

for lockname, pm in locks:
    base = lockname
    if pm not in supported:
        no_verdict += 1
        summary.append("install-drift: NOT SUPPORTED — drift check not supported for %s (%s): the installed "
                       "tree in %s was NOT compared with it" % (pm, base, d))
        continue
    ents, err = npm_entries(os.path.join(d, lockname))
    if err:
        no_verdict += 1
        summary.append("install-drift: NOT SUPPORTED — %s %s: the installed tree in %s was NOT compared "
                       "with it" % (base, err, d))
        continue

    drifts = []       # (name, rel, kind, locked, installed)
    matched = 0
    nover = 0
    platform = 0
    dev_total = 0
    dev_absent = []
    for rel in sorted(ents):
        v = ents[rel]
        locked = v.get("version")
        if v.get("link") is True or not isinstance(locked, str):
            nover += 1
            continue
        name = rel.split("node_modules/")[-1]
        # MUTATION SITE scoped-filter — install-drift.test.sh inserts a filter on `name` right here to prove
        # (AC5) that a scoped package is really compared, and not passing only because nothing is.
        if v.get("dev"):
            dev_total += 1
        inst, why = installed(rel)
        if why == "absent":
            # not installed is only evidence of a stale install when the lockfile says it SHOULD be there:
            # an optional or platform-restricted package is legitimately absent on this machine.
            if v.get("optional") or v.get("devOptional") or v.get("os") or v.get("cpu") or v.get("libc"):
                platform += 1
            elif v.get("dev"):
                dev_absent.append((name, rel, locked))
            else:
                drifts.append((name, rel, "absent", locked, None))
            continue
        if why == "unreadable":
            drifts.append((name, rel, "unreadable", locked, None))
            continue
        # MUTATION SITE drift-compare — the one comparison this whole script exists for (AC5).
        if inst != locked:
            drifts.append((name, rel, "version", locked, inst))
            continue
        matched += 1

    devnote = ""
    if dev_absent and dev_total and len(dev_absent) == dev_total:
        # every dev entry missing is an install SCOPE (--omit=dev), not a stale install: said out loud, and
        # those entries are declared uncompared rather than passed over.
        devnote = ("install-drift: info — all %d dev entries of %s are absent: the install scope differs "
                   "from the lockfile, they were not compared" % (dev_total, base))
    else:
        for name, rel, locked in dev_absent:
            drifts.append((name, rel, "absent", locked, None))

    total = matched + len(drifts)
    if drifts:
        drift_total += len(drifts)
        for name, rel, kind, locked, inst in drifts[:MAXLINES]:
            if kind == "version":
                lines.append("drift  %s — installed %s, locked %s (%s)" % (name, inst, locked, rel))
            elif kind == "absent":
                lines.append("drift  %s — locked %s, not installed (%s)" % (name, locked, rel))
            else:
                lines.append("drift  %s — locked %s, installed version unreadable (%s)" % (name, locked, rel))
        if len(drifts) > MAXLINES:
            lines.append("drift  … and %d more" % (len(drifts) - MAXLINES))
        summary.append("install-drift: DRIFT — %d of %d compared entries of %s disagree with the installed "
                       "tree in %s" % (len(drifts), total, base, d))
        summary.append("install-drift: run `%s` in %s to make the installed tree match the lockfile"
                       % (CMD.get(pm, "the frozen install of " + pm), d))
    else:
        extra = ""
        if nover or platform:
            extra = " (%d not comparable, %d legitimately absent)" % (nover, platform)
        summary.append("install-drift: OK — %d compared entries of %s match the installed tree in %s%s"
                       % (total, base, d, extra))
    if devnote:
        summary.append(devnote)

for l in lines:
    print(l)
for l in summary:
    print(l)
if drift_total:
    sys.exit(1)
if no_verdict:
    sys.exit(3)
sys.exit(0)
PY
}

# --- is anything RUNNING against this checkout? -------------------------------------------------------------
# Three states, never two. "Nothing is registered" and "nobody could tell me what is registered" are different
# answers and only one of them is safe to install on; the same for processes. Every reader below therefore
# reports WHICH of the three it reached, and an unknown always ends in a deferral (§2 of the reinstall path).
#
# WT_STATE is set by read_worktrees: norepo (nothing can be registered here — a plain directory with a
# lockfile is a supported input and must not defer forever), read (the list is the truth below), unreadable
# (git is absent, or it could not answer: defer). $DIR itself is never in WT_PATHS.
WT_STATE=""; WT_WHY=""; WT_PATHS=""; WT_NAMED=""
read_worktrees() {
  local gerr grc
  if ! command -v git >/dev/null 2>&1; then
    WT_STATE=unreadable; WT_WHY="git is not on PATH, so the worktrees of this checkout cannot be listed"; return
  fi
  gerr=$(git -C "$DIR" rev-parse --git-dir 2>&1 >/dev/null); grc=$?
  if [[ $grc -ne 0 ]]; then
    # "not a git repository" is an ANSWER (nothing can be registered); anything else is git failing to answer.
    if printf '%s' "$gerr" | grep -qi 'not a git repository'; then WT_STATE=norepo; return; fi
    WT_STATE=unreadable; WT_WHY="git could not say whether $DIR is a repository (exit $grc: $(printf '%s' "$gerr" | tr '\n' ' ' | cut -c1-90))"; return
  fi
  local porcelain prc
  porcelain=$(git -C "$DIR" worktree list --porcelain 2>/dev/null); prc=$?
  if [[ $prc -ne 0 ]]; then
    WT_STATE=unreadable; WT_WHY="\`git worktree list\` in $DIR exited $prc, so what is registered against this checkout is unknown"; return
  fi
  # The porcelain travels in the environment, not on stdin: stdin here is the reader program itself.
  local decoded drc
  decoded=$(WT_PORCELAIN="$porcelain" python3 - "$DIR" "$EXCEPT" <<'PY'
import os, sys
d = sys.argv[1].rstrip("/")
except_names = set(sys.argv[2].split())
except_slugs = set(n.replace("/", "-") for n in except_names)
entries, cur = [], {}
for line in os.environ.get("WT_PORCELAIN", "").splitlines() + [""]:
    if not line.strip():
        if cur.get("worktree"):
            entries.append(cur)
        cur = {}
        continue
    k, _, v = line.partition(" ")
    cur[k] = v
for w in entries:
    p = w["worktree"]
    if p.rstrip("/") == d:
        continue
    br = w.get("branch", "").replace("refs/heads/", "") or "(detached)"
    # --except names a worktree the CALLER has declared finished (the PR it has just merged). It removes it
    # from the registered list — the "I cannot tell" dimension — and from nothing else: a live process
    # inside it still blocks below, because the caller can declare an agent done, not a process gone.
    excepted = br in except_names or p.rstrip("/").split("/")[-1] in except_slugs
    print(("-" if excepted else "+") + "\t" + p + "\t" + br)
PY
  ); drc=$?
  if [[ $drc -ne 0 ]]; then
    WT_STATE=unreadable; WT_WHY="the worktree list of $DIR could not be decoded (reader exited $drc)"; return
  fi
  WT_STATE=read
  WT_PATHS=$(printf '%s\n' "$decoded" | grep -v '^$' | cut -f2)
  WT_NAMED=$(printf '%s\n' "$decoded" | grep '^+' | cut -f3 | grep -v '^$')
}

# live_runs — one "<pid>\t<command>\t<directory>" per LIVE process of this user, other than this script's own
# ancestors and descendants, whose current directory is inside the checkout or inside one of its worktrees.
# This is the evidence the deferral rests on: a process, not a directory entry. Exit 3 = no prober could run,
# which is an unknown and defers, never an empty answer.
live_runs() {
  WT_ROOTS="$WT_PATHS" python3 - "$DIR" "$$" <<'PY'
import os, shutil, subprocess, sys

d = sys.argv[1].rstrip("/")
me = int(sys.argv[2])
roots = sorted({r.rstrip("/") for r in os.environ.get("WT_ROOTS", "").splitlines() if r.strip()} | {d})


def ps_map():
    """{pid: (ppid, command)} — or None when ps could not answer."""
    try:
        r = subprocess.run(["ps", "-Ao", "pid=,ppid=,comm="], capture_output=True, text=True, timeout=30)
    except Exception:
        return None
    if r.returncode != 0:
        return None
    m = {}
    for line in r.stdout.splitlines():
        parts = line.split(None, 2)
        if len(parts) < 2:
            continue
        try:
            m[int(parts[0])] = (int(parts[1]), parts[2] if len(parts) > 2 else "?")
        except ValueError:
            continue
    return m or None


spawned = set()                                      # the pids of the probers themselves — see below


def cwds():
    """{pid: current directory} — or None when no prober is available on this machine."""
    if os.path.isdir("/proc"):                      # Linux: exact, and needs no external command
        out, ok = {}, False
        for e in os.listdir("/proc"):
            if not e.isdigit():
                continue
            try:
                out[int(e)] = os.readlink("/proc/%s/cwd" % e)
                ok = True
            except Exception:
                continue                            # a process of another user, or one that just exited
        if ok:
            return out
    exe = shutil.which("lsof")                      # macOS/BSD: this user's own processes
    if not exe:
        return None
    # Popen, not run(), for one reason: lsof LISTS ITSELF, and it inherits this script's working directory —
    # which is inside the checkout whenever the closing step is run from the repository root. Without its own
    # pid recorded here it looks exactly like an agent running in the checkout and defers every reinstall
    # forever (measured on the end-to-end fixture of this task).
    try:
        p = subprocess.Popen([exe, "-a", "-d", "cwd", "-w", "-F", "pn", "-u", str(os.getuid())],
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        spawned.add(p.pid)
        stdout, _ = p.communicate(timeout=120)
    except Exception:
        return None
    if not stdout or not stdout.strip():             # lsof exits 1 on partial information; empty is no answer
        return None
    out, pid = {}, None
    for line in stdout.splitlines():
        if line[:1] == "p":
            try:
                pid = int(line[1:])
            except ValueError:
                pid = None
        elif line[:1] == "n" and pid is not None:
            out.setdefault(pid, line[1:])
    return out or None


# Order matters: the directory snapshot first, the process table SECOND. A pid the first reader saw and the
# second one no longer knows has exited in between — a process that is gone is not a run in progress, and
# taking the tables the other way round would report it as one.
cw = cwds()
pm = ps_map()
if pm is None or cw is None:
    sys.exit(3)


def ancestry(p):
    seen = set()
    while p and p > 0 and p not in seen:
        seen.add(p)
        p = pm.get(p, (0, ""))[0]
    return seen


mine = ancestry(me)                                  # this run and everything that launched it
for pid in sorted(cw):
    if pid in spawned or pid not in pm:              # a prober of ours, or a process that has since exited
        continue
    if pid in mine or me in ancestry(pid):           # ours, or launched by us
        continue
    c = cw[pid].rstrip("/")
    for r in roots:
        if c == r or c.startswith(r + "/"):
            print("%d\t%s\t%s" % (pid, pm.get(pid, (0, "?"))[1], c))
            break
PY
}

# log_deferral <message> — write the deferral to the handoff log, and say out loud what actually happened.
# A deferral that is not logged is the silence this whole script exists to remove, so the claim is made only
# when the line is IN the file: `handoff.sh log` prints its own success line and exits 0 even when its write
# raised (measured in the PI-51 review), so neither its exit code nor its output is evidence of a write.
log_deferral() {
  local msg="$1" key="$2" hs="$SELF_DIR/handoff.sh" root out rc
  [[ $DOLOG -eq 1 ]] || return 0
  if [[ ! -f "$hs" ]]; then
    echo "install-drift: NOT LOGGED — handoff.sh is not next to this script (looked in $SELF_DIR): the deferral above is in this output only, record it by hand" >&2
    return 0
  fi
  root=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)
  # The evidence is that the memory gained a line, not that it contains one: a deferral repeats verbatim run
  # after run, so "the text is in there" is also true when this write failed and last week's succeeded. The
  # count is taken over the whole composed memory — fragments and frozen sources — so no line is invisible
  # to it and a write that landed in a brand new fragment is seen exactly like any other.
  local before after
  before=$(count_logged "$root" "$key")
  out=$(cd "$DIR" && bash "$hs" log "$msg" 2>&1); rc=$?
  after=$(count_logged "$root" "$key")
  if [[ -n "$root" && "$after" -gt "$before" ]]; then
    echo "install-drift: logged the deferred reinstall with handoff.sh log"
  else
    echo "install-drift: NOT LOGGED — the deferral above could not be written to the handoff log (handoff.sh exited $rc: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-120)): record it by hand" >&2
  fi
}

# count_logged <repo root> <key> — how many log lines carrying <key> the handoff memory holds, all of it.
# The evidence is the COMPOSED log (`handoff.sh recent --all`), never a grep of a particular file: since
# PI-16 a write creates a new immutable fragment under docs/handoff/ and docs/SESSION_HANDOFF.md and its
# archive are frozen sources that no write touches again. Grepping those two would therefore count every
# generation of the memory except the one this write lands in, and a write that succeeded would read as a
# silence — the exact inversion of the defect this guard exists for. The composer spans fragments and
# frozen sources alike, so it is what every reader of the memory sees. Only when it is not available — a
# sibling handoff.sh older than the composer — is the frozen pair read directly, as it was before.
count_logged() {
  local root="$1" key="$2" hs="$SELF_DIR/handoff.sh" out n=0 f
  [[ -n "$root" ]] || { echo 0; return; }
  if out=$(cd "$root" && bash "$hs" recent --all 2>/dev/null); then
    printf '%s\n' "$out" | grep -cF "$key" || true
    return
  fi
  for f in "$root/docs/SESSION_HANDOFF.md" "$root/docs/SESSION_HANDOFF_ARCHIVE.md"; do
    [[ -f "$f" ]] && n=$((n + $(grep -cF "$key" "$f" 2>/dev/null || echo 0)))
  done
  echo "$n"
}

# ---------------------------------------------------------------------------------------------------------
if [[ "$SUB" == check ]]; then
  check_tree
  exit $?
fi

# --- reinstall --------------------------------------------------------------------------------------------
LOCKS=$(present_locks)
if [[ -z "$LOCKS" ]]; then
  echo "install-drift: SKIP — no lockfile in $DIR, nothing to reinstall"
  exit 0
fi
LOCKNAME=$(printf '%s\n' "$LOCKS" | head -1); PM="${LOCKNAME#*:}"; LOCKNAME="${LOCKNAME%%:*}"
NLOCKS=$(printf '%s\n' "$LOCKS" | grep -c .)
[[ "$NLOCKS" -gt 1 ]] && echo "install-drift: note — $NLOCKS lockfiles in $DIR; $LOCKNAME ($PM) is the one this run acts on"
CMD=$(install_cmd "$PM") || { echo "install-drift: usage error — no install command declared for $PM" >&2; exit 2; }

# 1. Is a reinstall needed at all? The effect decides whenever it can be read (the installed tree really
#    disagrees), and the event decides when it cannot (--since: the merge brought a new lockfile).
NEEDED=0; WHY=""
if [[ ! -d "$DIR/node_modules" ]]; then
  NEEDED=1; WHY="$DIR has $LOCKNAME but nothing installed"
else
  DOUT=$(check_tree); DRC=$?
  case $DRC in
    1) NEEDED=1; WHY="the installed tree disagrees with $LOCKNAME"
       printf '%s\n' "$DOUT" | grep -E '^install-drift: (DRIFT|NOT SUPPORTED)' ;;
    0) printf '%s\n' "$DOUT" | grep -E '^install-drift: (OK|SKIP)'
       echo "install-drift: SKIP — the installed tree in $DIR already matches $LOCKNAME, not reinstalled"
       exit 0 ;;
    *) printf '%s\n' "$DOUT" | grep -E '^install-drift: '
       if [[ -z "$SINCE" ]]; then
         echo "install-drift: CANNOT TELL — no drift check for $PM and no --since <ref> to read a lockfile change from; reinstall by hand with \`$CMD\` in $DIR if a dependency bump was just merged"
         exit 3
       fi
       LOCKARGS=""; for item in $LOCKFILES; do LOCKARGS="$LOCKARGS ${item%%:*}"; done
       # shellcheck disable=SC2086
       TOUCHED=$(git -C "$DIR" diff --name-only "$SINCE" HEAD -- $LOCKARGS 2>/dev/null)
       if [[ -z "$TOUCHED" ]]; then
         if ! git -C "$DIR" rev-parse --verify -q "$SINCE^{commit}" >/dev/null 2>&1; then
           echo "install-drift: CANNOT TELL — $SINCE cannot be resolved in $DIR, and there is no drift check for $PM"
           exit 3
         fi
         echo "install-drift: SKIP — no lockfile changed since $SINCE and $PM cannot be drift-checked, not reinstalled"
         exit 0
       fi
       NEEDED=1; WHY="$(printf '%s\n' "$TOUCHED" | tr '\n' ' ')changed since $SINCE" ;;
  esac
fi
[[ $NEEDED -eq 1 ]] || { echo "install-drift: SKIP — nothing indicates a stale install in $DIR"; exit 0; }

# 2. May it run now? A reinstall replaces the very code a running check is executing: it does not fail that
#    run, it silently changes what it measured. So the answer to any doubt is to wait, never to install.
#    Three sources of evidence, any one of them blocks; a worktree that is merely REGISTERED is not one of
#    them (see the threat model at the top) — it is reported, and it only blocks while nobody could tell us
#    whether anything is alive inside it.
BLOCK=""
[[ -n "$RUNNING" ]] && BLOCK="$RUNNING"
read_worktrees
case "$WT_STATE" in
  unreadable) BLOCK="${BLOCK:+$BLOCK; }$WT_WHY" ;;
esac
RUNS=""; RRC=0
if [[ "$WT_STATE" != unreadable ]]; then
  RUNS=$(live_runs); RRC=$?
  if [[ $RRC -ne 0 ]]; then
    # An unread list is never an empty one: if the prober could not run, assume something is.
    BLOCK="${BLOCK:+$BLOCK; }what is running in $DIR could not be read (no usable process list on this machine), so a run in progress cannot be ruled out"
  elif [[ -n "$RUNS" ]]; then
    N=$(printf '%s\n' "$RUNS" | grep -c .)
    BLOCK="${BLOCK:+$BLOCK; }$N live process(es) with their working directory in this checkout: $(printf '%s\n' "$RUNS" | awk -F'\t' '{printf "%s(pid %s) in %s; ", $2, $1, $3}')"
  fi
fi
if [[ -n "$BLOCK" ]]; then
  echo "install-drift: DEFERRED — no reinstall while anything is running against this checkout: it would swap the installed code under a run in progress and corrupt what that run measured — $BLOCK"
  echo "install-drift: run \`$CMD\` in $DIR (or this script again) once they report — $WHY"
  LOGKEY="DEFERRED REINSTALL — $CMD in $DIR"
  log_deferral "$LOGKEY — $WHY — not run: $BLOCK" "$LOGKEY"
  exit 4
fi
# Nothing is running. Registered worktrees, if any, are said out loud anyway: they are what this script used
# to defer on, and an operator who sees the reinstall go ahead with agent worktrees on disk must be able to
# tell that it was a decision and not an oversight.
if [[ -n "$WT_NAMED" ]]; then
  echo "install-drift: note — $(printf '%s\n' "$WT_NAMED" | grep -c .) worktree(s) of this checkout are registered but nothing is running in them, so they do not hold the reinstall: $(printf '%s\n' "$WT_NAMED" | tr '\n' ' ')"
fi

# 3. Run it.
if [[ $DRYRUN -eq 1 ]]; then
  echo "install-drift: would run \`$CMD\` in $DIR — $WHY"
  exit 0
fi
PMBIN="${CMD%% *}"
command -v "$PMBIN" >/dev/null 2>&1 || {
  echo "install-drift: CANNOT REINSTALL — \`$PMBIN\` is not on PATH, so \`$CMD\` cannot run in $DIR — $WHY"
  exit 1
}
echo "install-drift: running \`$CMD\` in $DIR — $WHY"
ILOG=$(cd "$DIR" && bash -c "$CMD" 2>&1); IRC=$?
if [[ $IRC -ne 0 ]]; then
  printf '%s\n' "$ILOG" | grep -vE '^\s*$' | tail -10 | sed 's/^/      /'
  echo "install-drift: INSTALL FAILED — \`$CMD\` exited $IRC in $DIR; the installed tree is still not the lockfile's"
  exit 1
fi
# 4. And say whether it actually closed the gap — a reinstall that ran is not the same as a tree that matches.
AOUT=$(check_tree); ARC=$?
printf '%s\n' "$AOUT" | grep -E '^(drift |install-drift: )' | tail -12
case $ARC in
  1) echo "install-drift: REINSTALLED — \`$CMD\` ran in $DIR, but the tree still disagrees with $LOCKNAME"; exit 1;;
  *) echo "install-drift: REINSTALLED — \`$CMD\` ran in $DIR — $WHY"; exit 0;;
esac
