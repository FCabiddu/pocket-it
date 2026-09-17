#!/usr/bin/env bash
# pocket-it install-drift — the installed dependency tree against the lockfile, and the reinstall that closes
# the gap. Two subcommands, one shared declaration of what a lockfile is and which install command owns it.
#
# Usage (from anywhere; <dir> defaults to the current directory):
#   bash install-drift.sh check     [<dir>]
#   bash install-drift.sh reinstall [<dir>] [--since <ref>] [--except <branch>] [--running <what>] [--dry-run]
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
#  * `reinstall` sees the worktrees of this repository, never processes: something running directly in the
#    main checkout, or in a worktree outside the pipeline's own directories, is invisible to it — which is
#    why --running exists, for a caller that knows it launched one.
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
  check      compares the installed tree in <dir> with its lockfile (exit 0 match / 1 drift / 3 no verdict)
  reinstall  runs the lockfile's own frozen install in <dir> when it is needed and nothing is running there
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
case "$SUB" in check|reinstall) ;; *) usage;; esac

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

# live_worktrees — one "<path>\t<branch>" per worktree of this repository, other than $DIR itself, that sits
# in a directory the pipeline runs agents and verifications in. Conservative by construction: a worktree
# whose porcelain line cannot be decoded still counts as present, because the wrong answer to defer to is
# always "wait", never "reinstall under something that is running".
live_worktrees() {
  git -C "$DIR" worktree list --porcelain 2>/dev/null | python3 - "$DIR" "$EXCEPT" <<'PY'
import sys
d = sys.argv[1].rstrip("/")
except_names = set(sys.argv[2].split())
except_slugs = set(n.replace("/", "-") for n in except_names)
entries, cur = [], {}
for line in sys.stdin.read().splitlines() + [""]:
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
    if "/.claude/worktrees/" not in p + "/" and "/.worktrees/" not in p + "/":
        continue
    br = w.get("branch", "").replace("refs/heads/", "") or "(detached)"
    if br in except_names or p.rstrip("/").split("/")[-1] in except_slugs:
        continue
    print(p + "\t" + br)
PY
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
       NEEDED=1; WHY="$(printf '%s' "$TOUCHED" | tr '\n' ' ')changed since $SINCE" ;;
  esac
fi
[[ $NEEDED -eq 1 ]] || { echo "install-drift: SKIP — nothing indicates a stale install in $DIR"; exit 0; }

# 2. May it run now? A reinstall replaces the very code a running check is executing: it does not fail that
#    run, it silently changes what it measured. So the answer to any doubt is to wait, never to install.
BLOCK=""
[[ -n "$RUNNING" ]] && BLOCK="$RUNNING"
WTS=$(live_worktrees)
if [[ -n "$WTS" ]]; then
  N=$(printf '%s\n' "$WTS" | grep -c .)
  BLOCK="${BLOCK:+$BLOCK; }$N worktree(s) of this checkout in use: $(printf '%s\n' "$WTS" | cut -f2 | tr '\n' ' ')"
fi
if [[ -n "$BLOCK" ]]; then
  echo "install-drift: DEFERRED — no reinstall while anything is running against this checkout: it would swap the installed code under a run in progress and corrupt what that run measured — $BLOCK"
  echo "install-drift: run \`$CMD\` in $DIR (or this script again) once they report — $WHY"
  if [[ $DOLOG -eq 1 && -f "$SELF_DIR/handoff.sh" ]]; then
    (cd "$DIR" && bash "$SELF_DIR/handoff.sh" log "DEFERRED REINSTALL — $CMD in $DIR — $WHY — not run: $BLOCK" >/dev/null 2>&1) \
      && echo "install-drift: logged the deferred reinstall with handoff.sh log"
  fi
  exit 4
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
