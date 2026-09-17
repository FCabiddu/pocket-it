#!/usr/bin/env bash
# Self-test for install-drift.sh (PI-51).
#
# What it has to establish, and how:
#  * the drift check answers for a CLASS, not for an example — the lockfile formats it declares, every entry
#    shape a lockfile can hold (plain, scoped, transitive-only/nested, link, optional, dev), and every tree
#    shape a checkout can be in (no lockfile, nothing installed, node_modules borrowed through a symlink).
#    The list of lockfiles is read out of the script's own LOCKFILES declaration at run time, so one added
#    there is covered here without editing this file; a FLOOR list of this suite's own catches the opposite
#    accident, a declaration that shrank (a loop over an emptied declaration passes on nothing).
#  * no silent pass: a lockfile this script cannot read must SAY so and exit non-zero, never look clean.
#  * the expected values are this suite's own — fixtures with hand-written versions, and a hand-written table
#    of install commands — never read back out of the code under test.
#  * mutation, both directions (AC5): with the version comparison removed, the drifted fixtures must go
#    green; with scoped packages excluded, the scoped fixture must go green while the plain one stays red.
cd "$(dirname "$0")"
SCRIPT="$PWD/install-drift.sh"
S=$(mktemp -d "${TMPDIR:-/tmp}/install-drift-test.XXXXXX"); S=$(cd "$S" && pwd -P)
cleanup(){ rm -rf "$S" 2>/dev/null; }
trap cleanup EXIT
fail=0
ok(){ if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
q(){ "$@" >/dev/null 2>&1; }
has(){ printf '%s\n' "$1" | grep -qF "$2"; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null

# --- fixture helpers ---------------------------------------------------------------------------------------
# inst <dir> <path under the checkout> <name> <version> — an installed package with that version in its own
# package.json. The versions written here are this suite's oracle; nothing reads them back out of the script.
inst(){ mkdir -p "$1/$2"; printf '{"name":"%s","version":"%s"}\n' "$3" "$4" > "$1/$2/package.json"; }
lock(){ mkdir -p "$1"; cat > "$1/$2"; }          # lock <dir> <filename> <<< body
runc(){ OUT=$(bash "$SCRIPT" check "$1" 2>&1); RC=$?; }
runr(){ local d="$1"; shift; OUT=$(bash "$SCRIPT" reinstall "$d" "$@" 2>&1); RC=$?; }

# the v3 lockfile every entry-shape fixture starts from: a plain package, a scoped one, and a transitive-only
# entry nested under another package (the shape npm writes when two versions of one package coexist).
v3lock(){ cat <<'J'
{
  "name": "fixture", "lockfileVersion": 3,
  "packages": {
    "": {"name": "fixture", "version": "1.0.0"},
    "node_modules/react": {"version": "18.3.1", "resolved": "https://r/react"},
    "node_modules/@scope/pkg": {"version": "2.0.0"},
    "node_modules/a": {"version": "1.0.0"},
    "node_modules/a/node_modules/b": {"version": "2.2.2"}
  }
}
J
}
# install_v3 <dir> [react version] [scoped version] [nested b version] — the tree the lockfile above describes
install_v3(){
  inst "$1" node_modules/react react "${2:-18.3.1}"
  inst "$1" node_modules/@scope/pkg @scope/pkg "${3:-2.0.0}"
  inst "$1" node_modules/a a 1.0.0
  inst "$1" node_modules/a/node_modules/b b "${4:-2.2.2}"
}

# =========================== 1. the matching tree, and every drifted entry shape ============================
F="$S/match"; mkdir -p "$F"; v3lock > "$F/package-lock.json"; install_v3 "$F"
runc "$F"
ok "match — an install that matches the lockfile exits 0" "[ $RC -eq 0 ]"
ok "match — and says how many entries it actually compared (4, not 0: nothing passed unread)" "has \"\$OUT\" 'install-drift: OK — 4 compared entries of package-lock.json match'"
ok "match — a matching tree prints no drift line" "! has \"\$OUT\" 'drift  '"

F="$S/drift-plain"; mkdir -p "$F"; v3lock > "$F/package-lock.json"; install_v3 "$F" 18.2.0
runc "$F"
ok "AC3 plain — a top-level package installed at another version exits 1" "[ $RC -eq 1 ]"
ok "AC3 plain — the line names the package, the installed version and the locked one" "has \"\$OUT\" 'drift  react — installed 18.2.0, locked 18.3.1 (node_modules/react)'"
ok "AC3 plain — the summary names the lockfile and the checkout" "has \"\$OUT\" 'install-drift: DRIFT — 1 of 4 compared entries of package-lock.json disagree with the installed tree in $F'"
ok "AC3 plain — the install command to run is printed, frozen and by name" "has \"\$OUT\" 'install-drift: run \`npm ci\` in $F'"

F="$S/drift-scoped"; mkdir -p "$F"; v3lock > "$F/package-lock.json"; install_v3 "$F" 18.3.1 1.0.0
runc "$F"
ok "AC3 scoped — a drifted @scope/name package exits 1" "[ $RC -eq 1 ]"
ok "AC3 scoped — the line names the scoped package in full" "has \"\$OUT\" 'drift  @scope/pkg — installed 1.0.0, locked 2.0.0 (node_modules/@scope/pkg)'"

F="$S/drift-nested"; mkdir -p "$F"; v3lock > "$F/package-lock.json"; install_v3 "$F" 18.3.1 2.0.0 1.1.1
runc "$F"
ok "AC3 transitive — a nested, transitive-only entry is compared too, and exits 1" "[ $RC -eq 1 ]"
ok "AC3 transitive — the line names the nested path, not just the package" "has \"\$OUT\" 'drift  b — installed 1.1.1, locked 2.2.2 (node_modules/a/node_modules/b)'"

F="$S/drift-absent"; mkdir -p "$F"; v3lock > "$F/package-lock.json"; install_v3 "$F"; rm -rf "$F/node_modules/react"
runc "$F"
ok "AC3 absent — a package the lockfile requires and the tree does not have exits 1" "[ $RC -eq 1 ]"
ok "AC3 absent — the line says it is locked and not installed" "has \"\$OUT\" 'drift  react — locked 18.3.1, not installed (node_modules/react)'"

F="$S/drift-unreadable"; mkdir -p "$F"; v3lock > "$F/package-lock.json"; install_v3 "$F"
printf 'not json at all' > "$F/node_modules/react/package.json"
runc "$F"
ok "AC3 unreadable — an installed package whose manifest cannot be read is drift, never a pass" "[ $RC -eq 1 ]"
ok "AC3 unreadable — the line says the installed version could not be read" "has \"\$OUT\" 'drift  react — locked 18.3.1, installed version unreadable'"

# --- the borrowed tree: node_modules is a symlink to another checkout's, which is how the gap appears -------
F="$S/borrower"; mkdir -p "$F"; v3lock > "$F/package-lock.json"
LENDER="$S/lender"; mkdir -p "$LENDER"; install_v3 "$LENDER" 18.2.0
ln -s "$LENDER/node_modules" "$F/node_modules"
runc "$F"
ok "AC3 symlinked — a node_modules borrowed from another checkout is read through the symlink" "[ $RC -eq 1 ]"
ok "AC3 symlinked — and its drifted package is named" "has \"\$OUT\" 'drift  react — installed 18.2.0, locked 18.3.1'"

# =========================== 2. what is legitimately absent, and what is not =================================
F="$S/optional"; mkdir -p "$F"
lock "$F" package-lock.json <<'J'
{"lockfileVersion":3,"packages":{
 "":{"name":"f"},
 "node_modules/react":{"version":"18.3.1"},
 "node_modules/fsevents":{"version":"2.3.3","optional":true},
 "node_modules/win-only":{"version":"1.0.0","os":["win32"]}}}
J
inst "$F" node_modules/react react 18.3.1
runc "$F"
ok "absent-by-design — an optional and a platform-restricted package missing is not drift" "[ $RC -eq 0 ]"
ok "absent-by-design — and the one real entry was still compared (1, never 0)" "has \"\$OUT\" 'install-drift: OK — 1 compared entries'"
ok "absent-by-design — the two uncompared entries are counted out loud, not passed over" "has \"\$OUT\" '(0 not comparable, 2 legitimately absent)'"

F="$S/link"; mkdir -p "$F"
lock "$F" package-lock.json <<'J'
{"lockfileVersion":3,"packages":{
 "":{"name":"f"},
 "node_modules/react":{"version":"18.3.1"},
 "node_modules/web":{"resolved":"apps/web","link":true},
 "apps/web":{"name":"web","version":"9.9.9"}}}
J
inst "$F" node_modules/react react 18.3.1
runc "$F"
ok "link — a workspace link carries no version and is reported as not comparable, never as drift" "[ $RC -eq 0 ] && has \"\$OUT\" '(1 not comparable, 0 legitimately absent)'"

F="$S/dev-all"; mkdir -p "$F"
lock "$F" package-lock.json <<'J'
{"lockfileVersion":3,"packages":{
 "":{"name":"f"},
 "node_modules/react":{"version":"18.3.1"},
 "node_modules/vitest":{"version":"1.0.0","dev":true},
 "node_modules/eslint":{"version":"8.0.0","dev":true}}}
J
inst "$F" node_modules/react react 18.3.1
runc "$F"
ok "dev scope — every dev entry absent is an install scope, not a stale install: exit 0" "[ $RC -eq 0 ]"
ok "dev scope — and it is stated, with the number of entries left uncompared" "has \"\$OUT\" 'install-drift: info — all 2 dev entries of package-lock.json are absent'"

F="$S/dev-partial"; mkdir -p "$F"
lock "$F" package-lock.json <<'J'
{"lockfileVersion":3,"packages":{
 "":{"name":"f"},
 "node_modules/react":{"version":"18.3.1"},
 "node_modules/vitest":{"version":"1.0.0","dev":true},
 "node_modules/eslint":{"version":"8.0.0","dev":true}}}
J
inst "$F" node_modules/react react 18.3.1; inst "$F" node_modules/vitest vitest 1.0.0
runc "$F"
ok "dev partial — dev deps installed but one missing is an incomplete install, exit 1" "[ $RC -eq 1 ]"
ok "dev partial — the missing dev package is named" "has \"\$OUT\" 'drift  eslint — locked 8.0.0, not installed'"

# =========================== 3. the lockfile formats, read from the script's own declaration =================
DECL=$(grep -m1 '^LOCKFILES="' "$SCRIPT" | sed 's/^LOCKFILES="//; s/"$//')
SUPPORTED=$(grep -m1 '^SUPPORTED_PM="' "$SCRIPT" | sed 's/^SUPPORTED_PM="//; s/"$//')
# This suite's own floor, never read out of the script: a declaration that shrank (or emptied) would shrink
# every loop below with it and leave them passing on nothing.
FLOOR="package-lock.json:npm pnpm-lock.yaml:pnpm yarn.lock:yarn bun.lockb:bun"
R=0
for item in $FLOOR; do
  case " $DECL " in *" $item "*) ;; *) R=1; echo "      install-drift.sh no longer declares $item, which this suite requires";; esac
done
ok "declaration — LOCKFILES still covers this suite's floor (npm, pnpm, yarn, bun)" "[ $R -eq 0 ]"
NDECL=$(printf '%s\n' $DECL | grep -c .)
ok "declaration — LOCKFILES really was read (at least the 4 of the floor)" "[ ${NDECL:-0} -ge 4 ]"

# every declared lockfile, in a tree that has something installed: a verdict (0/1) or an explicit refusal —
# never exit 0 without having compared anything.
R=0
for item in $DECL; do
  lf="${item%%:*}"; pm="${item#*:}"
  D="$S/fmt-$pm-${lf//./_}"; mkdir -p "$D"
  if [ "$pm" = npm ]; then v3lock > "$D/$lf"; install_v3 "$D" 18.2.0
  else printf 'lockfile body this script cannot read\n' > "$D/$lf"; inst "$D" node_modules/react react 18.2.0; fi
  runc "$D"
  case " $SUPPORTED " in
    *" $pm "*)
      [ "$RC" -eq 1 ] || { R=1; echo "      $lf ($pm) is supported but a drifted tree exited $RC"; }
      has "$OUT" "drift  react" || { R=1; echo "      $lf ($pm) gave no drift line"; };;
    *)
      [ "$RC" -eq 3 ] || { R=1; echo "      $lf ($pm) is not supported but exited $RC, not 3"; }
      has "$OUT" "install-drift: NOT SUPPORTED — drift check not supported for $pm ($lf)" \
        || { R=1; echo "      $lf ($pm) did not say, by name, that it was not compared: $OUT"; }
      has "$OUT" "install-drift: OK" && { R=1; echo "      $lf ($pm) called an uncompared tree OK"; };;
  esac
done
ok "AC3 formats — every declared lockfile either gives a verdict or refuses by name, none passes in silence" "[ $R -eq 0 ]"

# npm lockfile versions 1, 2 and 3 — the same drifted package, found in all three
F="$S/v1"; mkdir -p "$F"
lock "$F" package-lock.json <<'J'
{"name":"f","lockfileVersion":1,"dependencies":{
 "react":{"version":"18.3.1"},
 "a":{"version":"1.0.0","dependencies":{"b":{"version":"2.2.2"}}}}}
J
inst "$F" node_modules/react react 18.2.0; inst "$F" node_modules/a a 1.0.0; inst "$F" node_modules/a/node_modules/b b 1.1.1
runc "$F"
ok "AC3 lockfile v1 — the dependencies tree is read, top level and nested alike (exit 1)" "[ $RC -eq 1 ]"
ok "AC3 lockfile v1 — the top-level drift is named" "has \"\$OUT\" 'drift  react — installed 18.2.0, locked 18.3.1'"
ok "AC3 lockfile v1 — the nested, transitive-only drift is named with its path" "has \"\$OUT\" 'drift  b — installed 1.1.1, locked 2.2.2 (node_modules/a/node_modules/b)'"

F="$S/v2"; mkdir -p "$F"
lock "$F" package-lock.json <<'J'
{"name":"f","lockfileVersion":2,
 "packages":{"":{"name":"f"},"node_modules/react":{"version":"18.3.1"},"node_modules/@scope/pkg":{"version":"2.0.0"}},
 "dependencies":{"react":{"version":"18.3.1"},"@scope/pkg":{"version":"2.0.0"}}}
J
inst "$F" node_modules/react react 18.2.0; inst "$F" node_modules/@scope/pkg @scope/pkg 1.0.0
runc "$F"
ok "AC3 lockfile v2 — a file carrying both blocks is read once, not twice (2 entries, both drifted)" "[ $RC -eq 1 ] && has \"\$OUT\" 'DRIFT — 2 of 2 compared entries'"
ok "AC3 lockfile v2 — the scoped package is among them" "has \"\$OUT\" 'drift  @scope/pkg — installed 1.0.0, locked 2.0.0'"

F="$S/npm-shrinkwrap"; mkdir -p "$F"; v3lock > "$F/npm-shrinkwrap.json"; install_v3 "$F" 18.2.0
runc "$F"
ok "AC3 shrinkwrap — npm-shrinkwrap.json is read like a package-lock" "[ $RC -eq 1 ] && has \"\$OUT\" 'of npm-shrinkwrap.json disagree'"

F="$S/badjson"; mkdir -p "$F"; printf 'not json {{{\n' > "$F/package-lock.json"; inst "$F" node_modules/react react 1.0.0
runc "$F"
ok "AC3 unparsable — a lockfile that cannot be parsed is refused, not passed (exit 3)" "[ $RC -eq 3 ]"
ok "AC3 unparsable — and the refusal names the file and the reason" "has \"\$OUT\" 'install-drift: NOT SUPPORTED — package-lock.json cannot be parsed'"

F="$S/unknown-shape"; mkdir -p "$F"; printf '{"lockfileVersion":9}\n' > "$F/package-lock.json"; inst "$F" node_modules/react react 1.0.0
runc "$F"
ok "AC3 unknown shape — a future lockfile shape is refused, never read as empty-and-clean" "[ $RC -eq 3 ]"
ok "AC3 unknown shape — the refusal names the version it did not understand" "has \"\$OUT\" 'declares neither \"packages\" nor \"dependencies\" (lockfileVersion 9)'"

F="$S/multi"; mkdir -p "$F"; v3lock > "$F/package-lock.json"; printf 'pnpm body\n' > "$F/pnpm-lock.yaml"; install_v3 "$F" 18.2.0
runc "$F"
ok "AC3 two lockfiles — the readable one is compared and drifts (exit 1)" "[ $RC -eq 1 ] && has \"\$OUT\" 'drift  react'"
ok "AC3 two lockfiles — and the unreadable one is still declared uncompared in the same run" "has \"\$OUT\" 'drift check not supported for pnpm (pnpm-lock.yaml)'"

# =========================== 4. nothing to compare — behaviour unchanged (AC4) ===============================
F="$S/nolock"; mkdir -p "$F"; inst "$F" node_modules/react react 1.0.0
runc "$F"
ok "AC4 — a checkout with no lockfile exits 0 and says why" "[ $RC -eq 0 ] && has \"\$OUT\" 'install-drift: SKIP — no lockfile'"
F="$S/nonm"; mkdir -p "$F"; v3lock > "$F/package-lock.json"
runc "$F"
ok "AC4 — a lockfile with nothing installed exits 0 and says why" "[ $RC -eq 0 ] && has \"\$OUT\" 'install-drift: SKIP — no node_modules'"
F="$S/empty"; mkdir -p "$F"; echo hi > "$F/README.md"
runc "$F"
ok "AC4 — a non-JS project is nothing to check, exit 0" "[ $RC -eq 0 ]"
runc "$S/no-such-directory-here"
ok "usage — a directory that does not exist is a usage error, exit 2" "[ $RC -eq 2 ]"
OUT=$(bash "$SCRIPT" 2>&1); RC=$?
ok "usage — no subcommand is a usage error, exit 2" "[ $RC -eq 2 ]"
OUT=$(bash "$SCRIPT" nonsense "$S/empty" 2>&1); RC=$?
ok "usage — an unknown subcommand is a usage error, exit 2" "[ $RC -eq 2 ]"

# =========================== 5. mutation, both directions (AC5) ==============================================
# The mutants are copies: the live script is never edited, so a killed run cannot leave a mutated tool behind.
MUT_OFF="$S/mutant-no-compare.sh"
sed 's/^        if inst != locked:$/        if False:/' "$SCRIPT" > "$MUT_OFF"
ok "AC5 mutation 1 — the comparison line really was mutated in the copy" "! grep -q 'if inst != locked:' '$MUT_OFF'"
MOUT=$(bash "$MUT_OFF" check "$S/drift-plain" 2>&1); MRC=$?
ok "AC5 mutation 1 — with the version comparison removed the drifted fixture exits 0" "[ $MRC -eq 0 ]"
ok "AC5 mutation 1 — and it really ran (it says OK; it did not crash into a false green)" "has \"\$MOUT\" 'install-drift: OK — 4 compared entries'"

MUT_SCOPED="$S/mutant-skip-scoped.sh"
awk '{ if ($0 ~ /^        inst, why = installed\(rel\)$/) print "        if name.startswith(\"@\"): continue"; print }' "$SCRIPT" > "$MUT_SCOPED"
ok "AC5 mutation 2 — the scoped filter really was inserted in the copy" "grep -q 'name.startswith' '$MUT_SCOPED'"
MOUT=$(bash "$MUT_SCOPED" check "$S/drift-scoped" 2>&1); MRC=$?
ok "AC5 mutation 2 — ignoring scoped packages makes the scoped fixture exit 0" "[ $MRC -eq 0 ]"
ok "AC5 mutation 2 — and it ran: 3 of the 4 entries are still compared" "has \"\$MOUT\" 'install-drift: OK — 3 compared entries'"
MOUT=$(bash "$MUT_SCOPED" check "$S/drift-plain" 2>&1); MRC=$?
ok "AC5 mutation 2 — the same mutant still finds the unscoped drift (the mutation is the scoped dimension alone)" "[ $MRC -eq 1 ]"

# =========================== 6. reinstall — the command, and when it may run ==================================
# The expected install commands are this suite's own table, written from the criterion, never read out of the
# script. A package manager the script declares but this table does not know is a failure, not a skip.
expected_cmd(){ case "$1" in
  npm)  echo "npm ci";;
  pnpm) echo "pnpm install --frozen-lockfile";;
  yarn) echo "yarn install --frozen-lockfile";;
  bun)  echo "bun install --frozen-lockfile";;
  *)    return 1;; esac; }
R=0
for item in $DECL; do
  lf="${item%%:*}"; pm="${item#*:}"
  want=$(expected_cmd "$pm") || { R=1; echo "      no expected install command in this suite for \"$pm\" ($lf) — add it, do not skip it"; continue; }
  D="$S/cmd-$pm-${lf//./_}"; mkdir -p "$D"; printf 'body\n' > "$D/$lf"     # no node_modules: a reinstall is needed outright
  runr "$D" --dry-run
  [ "$RC" -eq 0 ] || { R=1; echo "      reinstall --dry-run on $lf exited $RC"; }
  has "$OUT" "install-drift: would run \`$want\` in $D" || { R=1; echo "      $lf ($pm): $OUT — want \`$want\`"; }
done
ok "AC1 — every declared lockfile reinstalls with its own package manager's frozen install" "[ $R -eq 0 ]"

D="$S/yarn-berry"; mkdir -p "$D"; printf '__metadata:\n  version: 8\n' > "$D/yarn.lock"
runr "$D" --dry-run
ok "AC1 — a yarn berry lockfile gets --immutable, which is the only form berry accepts" "has \"\$OUT\" 'would run \`yarn install --immutable\`'"
D="$S/yarn-berry-rc"; mkdir -p "$D"; printf '# yarn lockfile v1\n' > "$D/yarn.lock"; printf 'nodeLinker: node-modules\n' > "$D/.yarnrc.yml"
runr "$D" --dry-run
ok "AC1 — a .yarnrc.yml also identifies berry, whatever the lockfile header says" "has \"\$OUT\" 'would run \`yarn install --immutable\`'"

D="$S/noreinstall"; mkdir -p "$D"; echo hi > "$D/README.md"
runr "$D"
ok "AC4 — reinstall on a project with no lockfile does nothing, exit 0" "[ $RC -eq 0 ] && has \"\$OUT\" 'install-drift: SKIP — no lockfile'"

# --- a real repository, a stand-in npm, and the deferral rule -----------------------------------------------
R="$S/repo"; q git init -q -b main "$R"
v3lock > "$R/package-lock.json"; echo hi > "$R/README.md"
q git -C "$R" add -A; q git -C "$R" commit -qm base
drift_repo(){ install_v3 "$R" 18.2.0; }        # put the repo back in its drifted state
drift_repo
STUB="$S/stub"; mkdir -p "$STUB"; NPMLOG="$S/npm-calls.log"; : > "$NPMLOG"
cat > "$STUB/npm" <<SH
#!/usr/bin/env bash
# stand-in npm: records the arguments and the directory, and performs what \`npm ci\` would (the lockfile's
# version lands in the installed tree). Nothing is downloaded and nothing outside the fixture is touched.
printf '%s | %s\n' "\$*" "\$PWD" >> "$NPMLOG"
[[ "\$1" == ci ]] || exit 9
printf '{"name":"react","version":"18.3.1"}\n' > "\$PWD/node_modules/react/package.json"
SH
chmod +x "$STUB/npm"
NPMFAIL="$S/stubfail"; mkdir -p "$NPMFAIL"
printf '#!/usr/bin/env bash\necho "fixture: install refused" >&2\nexit 7\n' > "$NPMFAIL/npm"; chmod +x "$NPMFAIL/npm"

OUT=$(PATH="$STUB:$PATH" bash "$SCRIPT" reinstall "$R" 2>&1); RC=$?
ok "AC1 — a drifted checkout with nothing running is reinstalled, exit 0" "[ $RC -eq 0 ]"
ok "AC1 — it says which command it ran and where" "has \"\$OUT\" 'install-drift: running \`npm ci\` in $R'"
ok "AC1 — it reports the reinstall in a closing line" "has \"\$OUT\" 'install-drift: REINSTALLED — \`npm ci\` ran in $R'"
ok "AC1 — the install command really was invoked, in the checkout" "grep -qF \"ci | $R\" '$NPMLOG'"
ok "AC1 — and the tree now matches the lockfile" "grep -q '18.3.1' '$R/node_modules/react/package.json'"

: > "$NPMLOG"
OUT=$(PATH="$STUB:$PATH" bash "$SCRIPT" reinstall "$R" 2>&1); RC=$?
ok "AC1 — a second run on an already-matching tree reinstalls nothing, exit 0" "[ $RC -eq 0 ]"
ok "AC1 — it says the tree already matches" "has \"\$OUT\" 'already matches package-lock.json, not reinstalled'"
ok "AC1 — and the install command was not run at all" "[ ! -s '$NPMLOG' ]"

# --- AC2 — what "running" means: a live process, never a directory entry ------------------------------------
# Round 2 (F2). The first round deferred on a REGISTERED worktree. worktree.sh registers and locks one at
# creation and only cleanup-merged.sh releases it, so registration outlives its agent by days: on the repo
# this script lives in, 9 worktrees were registered and 7 locked while nothing at all was running, and every
# reinstall deferred forever — including the one verify.sh prints as its own remedy, whose blocker was the
# worktree of the PR being reviewed. So the evidence is a PROCESS. The pair below is the same world twice,
# with one live `sleep` as the only difference, run in both directions so neither side can pass by accident.
# spawn_in <dir> — a live process whose working directory is <dir>. `exec` makes the backgrounded pid the
# process itself, so the pid this prints is the one whose cwd the prober has to see.
# stdout and stderr go to /dev/null on purpose: a backgrounded process that inherits the pipe of a command
# substitution keeps it open, and `PID=$(spawn_in …)` would wait for the sleep instead of for the pid.
spawn_in(){ ( cd "$1" && exec sleep 120 ) >/dev/null 2>&1 & printf '%s' "$!"; }
stop(){ [ -n "${1:-}" ] && kill "$1" 2>/dev/null; wait "$1" 2>/dev/null; return 0; }

drift_repo
q git -C "$R" branch agent-work
q git -C "$R" worktree add -q "$R/.claude/worktrees/agent-work" agent-work
AGENTPID=$(spawn_in "$R/.claude/worktrees/agent-work")
: > "$NPMLOG"
OUT=$(PATH="$STUB:$PATH" bash "$SCRIPT" reinstall "$R" 2>&1); RC=$?
ok "AC2 — an agent running in a worktree of this checkout defers the reinstall, exit 4" "[ $RC -eq 4 ]"
ok "AC2 — the reason names the harm, not the place" "has \"\$OUT\" 'no reinstall while anything is running against this checkout: it would swap the installed code under a run in progress and corrupt what that run measured'"
ok "AC2 — and names the live process, by pid and by the directory it is in" "has \"\$OUT\" 'live process(es) with their working directory in this checkout' && has \"\$OUT\" '(pid $AGENTPID)' && has \"\$OUT\" '$R/.claude/worktrees/agent-work'"
ok "AC2 — nothing was installed" "[ ! -s '$NPMLOG' ]"
ok "AC2 — the tree is left drifted, exactly as it was" "grep -q '18.2.0' '$R/node_modules/react/package.json'"
ok "AC2 — the command to run once they report is printed in full" "has \"\$OUT\" 'install-drift: run \`npm ci\` in $R (or this script again) once they report'"
ok "AC2 — the deferral is written to the handoff log" "grep -q 'DEFERRED REINSTALL — npm ci in $R' '$R/docs/SESSION_HANDOFF.md'"
ok "AC2 — the log line says why it did not run" "grep -q 'no reinstall while anything is running' '$R/docs/SESSION_HANDOFF.md' || grep -q 'live process' '$R/docs/SESSION_HANDOFF.md'"
ok "AC2 — and the run claims the log only because the line is there" "has \"\$OUT\" 'install-drift: logged the deferred reinstall with handoff.sh log'"

# --running: the caller knows it launched agents this session, and that alone is enough
: > "$NPMLOG"
OUT=$(PATH="$STUB:$PATH" bash "$SCRIPT" reinstall "$R" --running "two developers launched in this session" 2>&1); RC=$?
ok "AC2 — a caller that knows it launched agents defers with --running, exit 4" "[ $RC -eq 4 ]"
ok "AC2 — and its own words are in the reason" "has \"\$OUT\" 'two developers launched in this session'"
ok "AC2 — --running also stops the install" "[ ! -s '$NPMLOG' ]"

# the same world, one process later: the worktree is still registered and still locked, nothing runs in it
stop "$AGENTPID"
q git -C "$R" worktree lock "$R/.claude/worktrees/agent-work"
: > "$NPMLOG"
OUT=$(PATH="$STUB:$PATH" bash "$SCRIPT" reinstall "$R" 2>&1); RC=$?
ok "AC2 — a registered, locked worktree with nothing running in it does NOT hold the reinstall" "[ $RC -eq 0 ] && grep -qF \"ci | $R\" '$NPMLOG'"
ok "AC2 — and the reinstall says the worktrees it decided not to wait for, so the decision is visible" "has \"\$OUT\" 'registered but nothing is running in them' && has \"\$OUT\" 'agent-work'"
ok "AC2 — the tree really was brought back to the lockfile" "grep -q '18.3.1' '$R/node_modules/react/package.json'"
q git -C "$R" worktree unlock "$R/.claude/worktrees/agent-work"

# --except: the caller declares the PR it has just merged finished. It drops that worktree from the
# registered list; a process still alive inside it is not something a caller can declare away.
drift_repo
AGENTPID=$(spawn_in "$R/.claude/worktrees/agent-work")
: > "$NPMLOG"
OUT=$(PATH="$STUB:$PATH" bash "$SCRIPT" reinstall "$R" --except agent-work 2>&1); RC=$?
ok "AC2 — --except does not silence a live process inside the excepted worktree, exit 4" "[ $RC -eq 4 ] && [ ! -s '$NPMLOG' ]"
stop "$AGENTPID"
: > "$NPMLOG"
OUT=$(PATH="$STUB:$PATH" bash "$SCRIPT" reinstall "$R" --except agent-work 2>&1); RC=$?
ok "AC1 — the merged PR's own worktree is excluded by name and the reinstall proceeds" "[ $RC -eq 0 ] && grep -qF \"ci | $R\" '$NPMLOG'"
ok "AC1 — an excepted worktree is not even listed as one it decided not to wait for" "! has \"\$OUT\" 'registered but nothing is running in them'"
q git -C "$R" worktree remove --force "$R/.claude/worktrees/agent-work"

# a process in the MAIN checkout, with no worktree registered at all: the same harm, the same answer
drift_repo
MAINPID=$(spawn_in "$R")
: > "$NPMLOG"
OUT=$(PATH="$STUB:$PATH" bash "$SCRIPT" reinstall "$R" 2>&1); RC=$?
ok "AC2 — a process running in the checkout itself defers it too, worktrees or no worktrees" "[ $RC -eq 4 ] && [ ! -s '$NPMLOG' ]"
ok "AC2 — and it is named with its own directory" "has \"\$OUT\" '(pid $MAINPID)'"
stop "$MAINPID"

# --- the readers themselves: three states, never two (F3) ---------------------------------------------------
TOOLBIN="$S/toolsonly"; mkdir -p "$TOOLBIN"
for t in bash git grep sed head cut tr cat awk dirname mkdir rm ln printf ps lsof; do
  p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$TOOLBIN/$t"
done
NOLOCK="$S/reader-down"; mkdir -p "$NOLOCK"; v3lock > "$NOLOCK/package-lock.json"   # nothing installed: a reinstall is needed
: > "$NPMLOG"
OUT=$(PATH="$STUB:$TOOLBIN" bash "$SCRIPT" reinstall "$NOLOCK" 2>&1); RC=$?
ok "AC2 — with no python to read what is running, the reinstall is deferred, not risked (exit 4)" "[ $RC -eq 4 ]"
ok "AC2 — and it says what could not be read" "has \"\$OUT\" 'could not be read'"
ok "AC2 — nothing was installed while the prober was down" "[ ! -s '$NPMLOG' ]"

# git missing: the worktree list is UNREADABLE, which is not the same answer as "no worktrees" (F3, measured:
# the first round installed here, because `git … 2>/dev/null` losing its status reads as an empty list).
NOGIT="$S/nogitbin"; mkdir -p "$NOGIT"
for t in bash grep sed head cut tr cat awk dirname mkdir rm ln printf python3 ps lsof; do
  p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$NOGIT/$t"
done
: > "$NPMLOG"
OUT=$(PATH="$STUB:$NOGIT" bash "$SCRIPT" reinstall "$R" 2>&1); RC=$?
ok "AC2 git-down — without git, what is registered against the checkout is unknown: exit 4" "[ $RC -eq 4 ]"
ok "AC2 git-down — and it says git is the reader that could not answer" "has \"\$OUT\" 'git is not on PATH'"
ok "AC2 git-down — nothing was installed on an unknown" "[ ! -s '$NPMLOG' ]"

# git present but unable to list worktrees: still unreadable, still a deferral — and told apart from both
# "not a repository" (below) and "no worktrees".
GITSTUB="$S/gitstub"; mkdir -p "$GITSTUB"
REALGIT=$(command -v git)
cat > "$GITSTUB/git" <<SH
#!/usr/bin/env bash
for a in "\$@"; do [[ "\$a" == worktree ]] && exit 3; done
exec "$REALGIT" "\$@"
SH
chmod +x "$GITSTUB/git"
: > "$NPMLOG"
OUT=$(PATH="$GITSTUB:$STUB:$PATH" bash "$SCRIPT" reinstall "$R" 2>&1); RC=$?
ok "AC2 git-down — a git that cannot list worktrees defers, exit 4" "[ $RC -eq 4 ]"
ok "AC2 git-down — and the reason is the failed listing, with its exit code" "has \"\$OUT\" 'exited 3, so what is registered against this checkout is unknown'"
ok "AC2 git-down — nothing was installed" "[ ! -s '$NPMLOG' ]"

# not a repository at all: nothing CAN be registered, so this is an answer and not an unknown — a plain
# directory with a lockfile must not defer forever (the third state; without it the two above would be met
# by blocking on any non-zero git status, which would never install in a non-repo project again).
PLAIN="$S/plaindir"; mkdir -p "$PLAIN"; v3lock > "$PLAIN/package-lock.json"; install_v3 "$PLAIN" 18.2.0
: > "$NPMLOG"
OUT=$(PATH="$STUB:$PATH" bash "$SCRIPT" reinstall "$PLAIN" 2>&1); RC=$?
ok "AC2 no-repo — a plain directory with a lockfile is reinstalled, not deferred, exit 0" "[ $RC -eq 0 ] && grep -qF \"ci | $PLAIN\" '$NPMLOG'"
ok "AC2 no-repo — and its drift really was closed" "grep -q '18.3.1' '$PLAIN/node_modules/react/package.json'"

# --- AC6 — a deferral is never a silence: the log is claimed only when it happened ---------------------------
# Measured in the round-1 review: `handoff.sh log` prints its success line and exits 0 even when its own
# write raised, and the first round discarded its output entirely — so a deferral could vanish while the run
# said it had been logged. Both failure paths are exercised here, not only the happy one.
ORPHAN="$S/orphan"; mkdir -p "$ORPHAN"; cp "$SCRIPT" "$ORPHAN/install-drift.sh"   # no handoff.sh beside it
drift_repo
ORPHANPID=$(spawn_in "$R")
: > "$NPMLOG"
OUT=$(PATH="$STUB:$PATH" bash "$ORPHAN/install-drift.sh" reinstall "$R" 2>&1); RC=$?
ok "AC6 — with no handoff.sh beside it the deferral still exits non-zero (4)" "[ $RC -eq 4 ]"
ok "AC6 — and it says out loud that the deferral was not logged, naming where it looked" "has \"\$OUT\" 'install-drift: NOT LOGGED — handoff.sh is not next to this script (looked in $ORPHAN)'"
ok "AC6 — it never claims a log it did not write" "! has \"\$OUT\" 'logged the deferred reinstall'"
ok "AC6 — nothing was installed" "[ ! -s '$NPMLOG' ]"

# the log file cannot be written: handoff.sh still exits 0 and still prints its own success line
chmod a-w "$R/docs/SESSION_HANDOFF.md" "$R/docs"
OUT=$(PATH="$STUB:$PATH" bash "$SCRIPT" reinstall "$R" 2>&1); RC=$?
HS_LIES=0; (cd "$R" && bash "$(dirname "$SCRIPT")/handoff.sh" log "AC6 probe" >/dev/null 2>&1) && HS_LIES=1
chmod u+w "$R/docs"; chmod u+w "$R/docs/SESSION_HANDOFF.md"
ok "AC6 — an unwritable handoff log still leaves the deferral at exit 4" "[ $RC -eq 4 ]"
ok "AC6 — the run says NOT LOGGED instead of claiming a write that did not happen" "has \"\$OUT\" 'install-drift: NOT LOGGED — the deferral above could not be written to the handoff log'"
ok "AC6 — and no success line is printed alongside it" "! has \"\$OUT\" 'logged the deferred reinstall'"
ok "AC6 — the claim cannot rest on handoff.sh's exit code, which is 0 on a refused write" "[ $HS_LIES -eq 1 ]"
ok "AC6 — the deferral line itself is still printed, whatever the log did" "has \"\$OUT\" 'install-drift: DEFERRED'"
ok "AC6 — and nothing was installed" "[ ! -s '$NPMLOG' ]"
stop "$ORPHANPID"

OUT=$(PATH="$NPMFAIL:$PATH" bash "$SCRIPT" reinstall "$R" 2>&1); RC=$?
ok "install failure — an install that exits non-zero is reported, exit 1" "[ $RC -eq 1 ]"
ok "install failure — the message names the command and its exit code" "has \"\$OUT\" 'install-drift: INSTALL FAILED — \`npm ci\` exited 7'"
ok "install failure — the installer's own last lines are shown" "has \"\$OUT\" 'fixture: install refused'"

# the package manager is not on this machine at all: refused, never silently skipped
NPMDIR=$(dirname "$(command -v npm 2>/dev/null || echo /nonexistent/npm)")
PATH_NO_NPM=$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF "$NPMDIR" | paste -sd: -)
if PATH="$PATH_NO_NPM" command -v git >/dev/null 2>&1 && PATH="$PATH_NO_NPM" command -v python3 >/dev/null 2>&1 \
   && ! PATH="$PATH_NO_NPM" command -v npm >/dev/null 2>&1; then
  OUT=$(PATH="$PATH_NO_NPM" bash "$SCRIPT" reinstall "$R" 2>&1); RC=$?
  ok "no package manager — a missing npm is refused with its command, exit 1" "[ $RC -eq 1 ] && has \"\$OUT\" 'install-drift: CANNOT REINSTALL — \`npm\` is not on PATH'"
else
  echo "note  no package manager — not exercised on this host: npm shares a directory with git or python3"
fi

# --- the event-based decision: a lockfile this script cannot drift-check, and --since ------------------------
P="$S/pnpmrepo"; q git init -q -b main "$P"
printf 'lockfile: 6.0\n' > "$P/pnpm-lock.yaml"; echo hi > "$P/README.md"
inst "$P" node_modules/react react 1.0.0
q git -C "$P" add -A; q git -C "$P" commit -qm base
BEFORE=$(git -C "$P" rev-parse HEAD)
printf 'lockfile: 6.0\nnew: dep\n' > "$P/pnpm-lock.yaml"
q git -C "$P" add -A; q git -C "$P" commit -qm bump
AFTER=$(git -C "$P" rev-parse HEAD)
runr "$P"
ok "no verdict — a pm with no drift check and no --since says it cannot tell, exit 3" "[ $RC -eq 3 ] && has \"\$OUT\" 'install-drift: CANNOT TELL'"
ok "no verdict — and names the command to run by hand" "has \"\$OUT\" 'reinstall by hand with \`pnpm install --frozen-lockfile\`'"
runr "$P" --since "$BEFORE" --dry-run
ok "AC1 — with --since, a merge that touched the lockfile is what triggers the reinstall" "[ $RC -eq 0 ] && has \"\$OUT\" 'would run \`pnpm install --frozen-lockfile\`'"
ok "AC1 — and the reason names the lockfile and the commit it changed since" "has \"\$OUT\" 'pnpm-lock.yaml changed since $BEFORE'"
runr "$P" --since "$AFTER" --dry-run
ok "AC1 — a merge that touched no lockfile reinstalls nothing, exit 0" "[ $RC -eq 0 ] && has \"\$OUT\" 'no lockfile changed since'"
runr "$P" --since deadbeefdeadbeef --dry-run
ok "no verdict — a --since that cannot be resolved is never read as 'no change', exit 3" "[ $RC -eq 3 ] && has \"\$OUT\" 'cannot be resolved'"


# =========================== 7. AC1 end to end, in the closing step's REAL order =============================
# Round 2 (F2). Asserting this script in isolation proved nothing about the flow it was written for: both
# skills ran the reinstall BEFORE cleanup-merged.sh, so the merged PR's own worktree was always still
# registered and the reinstall deferred every single time. This section therefore takes the commands out of
# the two SKILL.md files as they are written there, in the order they are written, and runs them on a
# fixture repository that is in exactly the state a closing step finds: a dependency bump merged into main,
# the merged PR's worktree still on disk, and this checkout's node_modules still holding the old versions.
REPO=$(cd "$(dirname "$SCRIPT")/.." && pwd -P)
CLEANUP="$REPO/bin/cleanup-merged.sh"
# bullet_line <file> <pattern> — the 1-based line number of the closing bullet that carries <pattern>.
bullet_line(){ grep -nF "$2" "$1" | grep -E '^[0-9]+:- ' | head -1 | cut -d: -f1; }
# skill_cmd <file> — the reinstall command as the skill writes it, between its backticks.
skill_cmd(){ grep -o '`bash ~/\.claude/agents/pocket-it/bin/install-drift\.sh reinstall [^`]*`' "$1" | head -1 | tr -d '`'; }

for SK in .claude/skills/quickfix/SKILL.md .claude/skills/run-wave/SKILL.md; do
  SKF="$REPO/$SK"; NAME=$(basename "$(dirname "$SK")")
  LC=$(bullet_line "$SKF" 'cleanup-merged.sh'); LR=$(bullet_line "$SKF" 'install-drift.sh reinstall')
  ok "AC1 $NAME — the reinstall bullet comes after cleanup-merged.sh, which is what removes the merged PR's worktree" "[ -n '$LC' ] && [ -n '$LR' ] && [ '$LR' -gt '$LC' ]"
  RAW=$(skill_cmd "$SKF")
  ok "AC1 $NAME — the skill's command excepts the branch it has just merged" "printf '%s' \"\$RAW\" | grep -q -- '--except'"

  # the world a closing step finds: origin, a merged dependency bump, its worktree still registered
  E="$S/e2e-$NAME"; q git init -q --bare "$E-origin.git"; q git init -q -b main "$E"; E=$(cd "$E" && pwd -P)
  v3lock > "$E/package-lock.json"; printf 'node_modules/\n' > "$E/.gitignore"
  q git -C "$E" add -A; q git -C "$E" commit -qm base
  q git -C "$E" remote add origin "$S/e2e-$NAME-origin.git"; q git -C "$E" push -q -u origin main
  q git -C "$E" worktree add -q -b task/dep-bump "$E/.claude/worktrees/task-dep-bump" main
  echo bump > "$E/.claude/worktrees/task-dep-bump/dep.txt"
  q git -C "$E/.claude/worktrees/task-dep-bump" add -A
  q git -C "$E/.claude/worktrees/task-dep-bump" commit -qm "bump a dependency"
  BUMPSHA=$(git -C "$E" rev-parse task/dep-bump)
  q git -C "$E" push -q origin task/dep-bump
  q git -C "$E" merge --no-ff -q -m "merge task/dep-bump" task/dep-bump
  q git -C "$E" push -q origin main
  install_v3 "$E" 18.2.0                      # the shared checkout, still on the versions before the bump
  GHB="$S/gh-$NAME"; mkdir -p "$GHB"
  cat > "$GHB/gh" <<GH
#!/usr/bin/env bash
# stand-in gh: the one merged PR of this fixture, in the two shapes cleanup-merged.sh asks for.
h=""; prev=""; for a in "\$@"; do [[ "\$prev" == --head ]] && h="\$a"; prev="\$a"; done
if [[ -n "\$h" ]]; then [[ "\$h" == task/dep-bump ]] && echo "7 $BUMPSHA"; exit 0; fi
printf 'task/dep-bump\t%s\n' "$BUMPSHA"
exit 0
GH
  chmod +x "$GHB/gh"

  # the closing step, in the skill's own order: cleanup-merged.sh first, then the skill's own command line,
  # with only the tool path and the placeholders resolved — every flag is the skill's.
  COUT=$(cd "$E" && PATH="$GHB:$STUB:$PATH" bash "$CLEANUP" 2>&1)
  ok "AC1 $NAME — cleanup-merged.sh removed the merged PR's worktree first" "[ ! -d '$E/.claude/worktrees/task-dep-bump' ]"
  CMD=$(printf '%s' "$RAW" | sed "s#~/\.claude/agents/pocket-it/bin/install-drift\.sh#$SCRIPT#; s#reinstall \. #reinstall $E #; s#reinstall \.\$#reinstall $E#; s#{[^}]*}#task/dep-bump#g")
  : > "$NPMLOG"
  OUT=$(cd "$E" && PATH="$GHB:$STUB:$PATH" eval "$CMD" 2>&1); RC=$?
  ok "AC1 $NAME — and the skill's own reinstall command then ran the frozen install, exit 0" "[ $RC -eq 0 ] && grep -qF \"ci | $E\" '$NPMLOG'"
  ok "AC1 $NAME — the shared checkout now holds the version the merged lockfile declares" "grep -q '18.3.1' '$E/node_modules/react/package.json'"
  ok "AC1 $NAME — it did not defer on the PR it had just merged" "! has \"\$OUT\" 'install-drift: DEFERRED'"
  ok "AC1 $NAME — and it says what it did, in the line the skill tells the operator to report" "has \"\$OUT\" 'install-drift: REINSTALLED'"
done

# The same proof for the remedy verify.sh prints is in bin/verify.test.sh, where the line is extracted from a
# real run of verify.sh and executed in the world that printed it.

[[ $fail -eq 0 ]] && echo "install-drift.test.sh: ALL PASS" || echo "install-drift.test.sh: FAILURES"
exit $fail
