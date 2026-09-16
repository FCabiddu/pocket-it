#!/usr/bin/env bash
# pocket-it cleanup-merged — removes the worktrees and local branches left behind by merged task PRs
# (developer/reviewer worktrees anywhere under <repo>/.claude/worktrees/* — worktree.sh names them after the
# branch slug, older ones used agent-* — or the legacy <parent>/.worktrees/<task>, hundreds of MB each with
# node_modules), so that cleanup is a step of the flow instead of a manual chore. Discovery is by
# `git worktree list`, not by directory name, so any path under .claude/worktrees/ is covered.
# Usage (from any worktree of the project): bash ~/.claude/agents/pocket-it/bin/cleanup-merged.sh [--dry-run] [--all]
#   --dry-run  print what would happen, touch nothing
#   --all      also consider worktrees on epic/*, main, master and fix-* branches (never the main checkout, never the current one)
# A worktree is removed when its branch has commits of its own and they are merged: by ancestry into origin/main,
# origin/master or any origin/epic/* (local base branches count too), or by a merged PR whose head contains the branch
# tip, as `gh` reports it (squash merge, remote branch gone or not). Whether the branch has commits of its own is read
# from its own reflog, never from topology against bases that may since have been merged and deleted: a branch whose
# reflog shows no commit made on it since `branch: Created from …` is work not started or not yet committed and is
# kept, and so is a branch whose reflog cannot tell (none, pruned, or inherited through `branch -c`/`-m`). A branch created from its own remote branch (a checkout of work
# already pushed) is removed only on a merged PR.
# Locked worktrees (PI-31) — a second protection, independent of everything above: worktree.sh creates an agent's worktree
# locked ("pocket-it: agent worktree for <branch> since <date>"), and such a worktree is never judged by its reflog or by
# ancestry. It is released and removed only when it is clean and a merged PR's head contains its tip; otherwise it is kept
# and the report line says it is locked, by what, and why it stays. A locked worktree missing on disk has its lock released
# and its entry pruned (its branch is deleted only on that same merged-PR condition). A lock with any other reason was
# placed by someone else and is never released.
# Only clean worktrees are removed; dirty ones (or ones whose `git status` fails) are kept. Detached-HEAD scratch
# worktrees (PI-34: `.claude/worktrees/verify-<pid>-*`, `wave-overlay-<epoch>` and `reviewer-conflict-pr<N>` —
# verify.sh, the reviewer's wave overlay pass and its conflict resolution; the legacy `/tmp/*` layout still
# recognised too) are removed only when every one of these holds:
#   - the path sits under this repo's own `.claude/worktrees/`, with a basename in exactly one of those digit-
#     bearing forms — never a bare basename match, so a same-named folder elsewhere (`../verify-elsewhere`) or
#     an agent's own worktree whose branch merely slugs to a lookalike name (`verify-login`, no pid) is left alone;
#   - `git status --porcelain` is empty and no merge or rebase is in progress there (uncommitted or half-resolved
#     work is kept, never force-removed);
#   - every commit reachable from its `HEAD` is also reachable from some remote-tracking ref (`git rev-list HEAD
#     --not --remotes` empty) — a resolution committed but not yet pushed (the window between `git commit` and
#     `git push` in the reviewer's own conflict-resolution flow, or a real agent worktree with a local commit
#     never pushed) is kept, since removing it would lose the only copy of that commit;
#   - no process has it open or as a cwd (`lsof +D`).
# None of these is gated by age, so a `kill -9`'d run must not leave an orphan waiting 24 h, but a live, dirty or
# not-yet-pushed one is never swept just because it is old. `lsof` missing falls back to the old 24h-age rule for
# the case that is otherwise clean, on a remote and unused. The corresponding local branch is then deleted and
# `git worktree prune`
# runs. One line per action, a summary with the freed size at the end.
# Remote branches (PI-38): `gh pr merge --delete-branch` fails its own cleanup in two silent shapes (run from a
# worktree: aborts before the remote delete because the base is checked out elsewhere; run from the main checkout
# while another worktree still holds the branch: the remote delete can succeed while the local one fails) and
# nothing retries either. Independently of the worktree/local-branch handling above, a separate pass (below the
# main loop) reads every merged PR once and deletes any remote branch — one with no worktree currently checked
# out for it — whose current tip equals that PR's own head: never by ancestry (squash breaks it by construction,
# AC3), never a protected/base branch, and never a branch with commits pushed since — but that last guarantee is
# only as good as the single `g fetch --prune -q origin` near the top of this script (its own failure discarded,
# exit code unchecked): `refs/remotes/origin/*` is read here exactly as that fetch last left it, so a push that
# lands on origin after it and before this pass's own `push --delete` (the whole length of the worktree loop
# above) is judged on a tip this script has not seen yet and can be deleted. Outside this script's own model —
# left to whoever pushes to a branch a merge has already closed — not a bug to fix here. A branch with an open PR,
# a closed-unmerged PR, or no PR at all never
# appears in the merged list and is left alone. This pass reads which branches are still checked out only after
# the worktree loop above has run, so a branch whose worktree that same loop just removed as merged is reaped
# right here, in this same run — the remote delete only ever touches a remote ref, never a live worktree's own
# checkout, local branch or files, so nothing about a worktree still present is disturbed either way. A branch
# still checked out in one of this repo's own worktrees when this pass runs is left alone entirely and picked up
# by this pass on a later run once it no longer is. `gh` missing or `gh pr list` failing skips the whole pass;
# the delete push failing skips only that one branch — either way one report line, no error, exit 0, the rest
# of the cleanup (worktrees, local branches) unaffected. A failed push is never assumed to be "no network, no
# permission" (PI-44): already-gone-from-origin is told apart from a real failure, whose own message is what
# gets reported — see `reap_remote_branches`'s own comment.
# Exit 0 always (2 on usage error). Safe to run repeatedly.
set -uo pipefail
DRY=0; ALL=0
for a in "$@"; do case "$a" in --dry-run) DRY=1;; --all) ALL=1;; *) echo "usage: cleanup-merged.sh [--dry-run] [--all]" >&2; exit 2;; esac; done
git rev-parse --git-common-dir >/dev/null 2>&1 || { echo "usage: run cleanup-merged.sh inside a git repository" >&2; exit 2; }

abs(){ (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)   # worktree.sh sits beside this script: the --unlock hint is a runnable command
CUR=$(abs "$(git rev-parse --show-toplevel)")

# git prints a lock reason C-quoted ("…", \" \\ \n \t \ooo) when it holds a quote, a backslash or a non-ASCII byte: read it back
cunquote(){ local s="$1" o="" i c
  [[ ${#s} -ge 2 && "$s" == \"*\" ]] || { printf '%s' "$s"; return 0; }
  s="${s:1:${#s}-2}"
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    if [[ "$c" == '\' ]]; then
      i=$((i+1)); c="${s:i:1}"
      case "$c" in
        n) c=$'\n';; t) c=$'\t';;
        [0-7]) printf -v c "\\${s:i:3}"; i=$((i+2));;
      esac
    fi
    o="$o$c"
  done
  printf '%s' "$o"; }
# Parse `git worktree list --porcelain` (bash 3.2 friendly: one "path US sha US branch US flags US lock reason" string per
# entry, US = the unit separator \x1f, which no branch name can hold — "|", ";", "$" and the like are valid in branch names).
SEP=$'\x1f'
entries=(); path=""; sha=""; branch=""; flags=""; lockr=""
flush(){ [[ -n "$path" ]] && entries+=("$path$SEP$sha$SEP$branch$SEP$flags$SEP$lockr"); path=""; sha=""; branch=""; flags=""; lockr=""; return 0; }
while IFS= read -r line; do
  case "$line" in
    "worktree "*) flush; path="${line#worktree }";;
    "HEAD "*)     sha="${line#HEAD }";;
    "branch "*)   branch="${line#branch refs/heads/}";;
    detached)     flags="$flags detached";;
    locked|"locked "*) flags="$flags locked"; lockr="${line#locked}"; lockr=$(cunquote "${lockr# }");;
    prunable*)    flags="$flags prunable";;
  esac
done < <(git worktree list --porcelain)
flush
MAIN="${entries[0]%%"$SEP"*}"   # the first entry is always the main checkout
g(){ git -C "$MAIN" "$@"; }

g remote get-url origin >/dev/null 2>&1 && g fetch --prune -q origin 2>/dev/null

# Base branches a task branch can be merged into: remote first, then the local ones (they may be ahead after a local merge).
BASES=""; for r in refs/remotes/origin/main refs/remotes/origin/master 'refs/remotes/origin/epic/*' refs/heads/main refs/heads/master 'refs/heads/epic/*'; do
  BASES="$BASES $(g for-each-ref --format='%(refname:short)' "$r")"; done
merged_into(){ # $1 sha, $2 own branch → prints the first base that contains the sha
  local b; for b in $BASES; do
    [[ "$b" == "$2" || "$b" == "origin/$2" ]] && continue
    g merge-base --is-ancestor "$1" "$b" 2>/dev/null && { echo "$b"; return 0; }
  done; return 1; }
is_anc(){ g merge-base --is-ancestor "$1" "$2" 2>/dev/null; }
history(){ # $1 tip sha, $2 branch → reads the branch's reflog oldest first; prints own | fresh <start> | remote <start> | unknown
  local h s start="" seen=0 own=0
  while read -r h s; do
    case "$s" in
      "branch: Created from "*) start="${s#branch: Created from }";;
      # `branch -c` / `branch -m` carry another ref's reflog along: what came before was written on that ref
      "Branch: copied "*|"Branch: renamed "*) start=""; seen=0; own=0;;
      # an entry that made a commit on this branch, still in its history (a reset past it takes it away)
      commit:*|"commit ("*|cherry-pick:*|revert:*|am:*|*": Merge made by "*) seen=1; is_anc "$h" "$1" && own=1;;
      # a rebase rewrites the commits above: it carries them only if there were some to replay
      *" (finish): refs/heads/"*|"rebase finished: "*) (( seen )) && is_anc "$h" "$1" && own=1;;
    esac   # fast-forwards, resets, `branch -f`, update-ref: moves that make no commit of its own
  done < <(g reflog show --format='%H %gs' "refs/heads/$2" -- 2>/dev/null | awk '{l[NR]=$0} END{for(i=NR;i>0;i--) print l[i]}')
  if (( own )); then echo own
  elif [[ -z "$start" ]]; then echo unknown   # no reflog, pruned past the creation, or copied/renamed: cannot tell, so keep
  elif [[ "$start" == "origin/$2" || "$start" == "refs/remotes/origin/$2" ]]; then echo "remote $start"
  else echo "fresh $start"; fi; }
merged_pr(){ # $1 sha, $2 branch → three answers, never a "no" that is really an "I don't know":
  #   exit 0 "PR #n merged"                  a merged PR's head contains the tip
  #   exit 1 "commits not in merged PR #n"   merged PRs exist, none contains the tip
  #   exit 1 ""                              gh answered: no merged PR for the branch
  #   exit 2 "gh not available" | "gh pr list failed (exit N)" | "gh pr list output unreadable"   cannot tell
  local out rc n oid found="" line
  command -v gh >/dev/null 2>&1 || { echo "gh not available"; return 2; }
  out=$(cd "$MAIN" && gh pr list --state merged --head "$2" --json number,headRefOid --jq '.[] | "\(.number) \(.headRefOid)"' 2>/dev/null); rc=$?
  (( rc == 0 )) || { echo "gh pr list failed (exit $rc)"; return 2; }
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[0-9]+\ [0-9a-f]{40}$ ]] || { echo "gh pr list output unreadable"; return 2; }
  done <<<"$out"
  while read -r n oid; do
    [[ -z "$n" ]] && continue
    is_anc "$1" "$oid" && { echo "PR #$n merged"; return 0; }
    found="$n"
  done <<<"$out"
  [[ -n "$found" ]] && echo "commits not in merged PR #$found"
  return 1; }
decide(){ # $1 sha, $2 branch → prints the reason; exit 0 = remove, 1 = keep
  local k m r rc
  k=$(history "$1" "$2")
  case "$k" in
    unknown) echo "reflog cannot tell whether it has commits of its own"; return 1;;
    fresh*)  echo "no commits of its own (created from ${k#fresh })"; return 1;;
    own)     m=$(merged_into "$1" "$2") && { echo "merged into $m"; return 0; };;
  esac
  # Squash-merged PRs leave no ancestry: ask gh even if the remote branch still exists, and remove only if the PR's
  # head contains the local tip — commits made after the merge are work the PR never carried.
  r=$(merged_pr "$1" "$2"); rc=$?
  (( rc == 0 )) && { echo "$r"; return 0; }
  if (( rc == 2 )); then
    [[ "$k" == remote* ]] && echo "created from ${k#remote }, merged PRs unknown: $r" || echo "not merged into a base, merged PRs unknown: $r"
    return 1; fi
  [[ -n "$r" ]] && { echo "$r"; return 1; }
  [[ "$k" == remote* ]] && { echo "created from ${k#remote }, no merged PR contains it"; return 1; }
  echo "not merged"; return 1; }
protected(){ case "$1" in epic/*|main|master|fix-*) return 0;; esac; return 1; }
is_scratch_legacy(){ case "$1" in /tmp/*|/private/tmp/*) return 0;; esac; return 1; }   # pre-PI-34 layout, age-gated
# PI-34 round 3: a basename match is not enough — "../verify-elsewhere", outside .claude/worktrees/ entirely,
# used to be swept the same as a real scratch worktree because only the basename was checked. The path itself
# must sit under *this* repo's own .claude/worktrees/ (MAIN, not wherever the script happens to be invoked
# from), and the basename must be one of the exact forms verify.sh/reviewer.md actually create — a digit-bearing
# suffix, never the bare branch slug worktree.sh uses for an agent's own worktree. Round 4: "verify-*" alone
# still matched "verify-login" (an agent's real worktree for a branch literally named "verify-login"); tightened
# to require the pid: "verify-<digits>-<anything>", "wave-overlay-<digits>" (no extra suffix), "reviewer-
# conflict-pr<digits>" (the PR-number-keyed name reviewer.md's conflict resolution now uses, never a pid).
is_scratch_new(){ local p="$1" base
  case "$p" in "$MAIN/.claude/worktrees/"*) ;; *) return 1;; esac
  base=$(basename "$p")
  [[ "$base" =~ ^verify-[0-9]+-.+$ ]] && return 0
  [[ "$base" =~ ^wave-overlay-[0-9]+$ ]] && return 0
  [[ "$base" =~ ^reviewer-conflict-pr[0-9]+$ ]] && return 0
  return 1; }
# PI-34 round 3: a scratch worktree is never force-removed while it might hold work nothing else has a copy of
# — uncommitted changes, staged changes, untracked files, or a merge/rebase paused mid-resolution. Before this,
# the detached-scratch branch below skipped the dirty check the ordinary branch-based path already had, so a
# `verify-login` (an agent's own worktree that merely happens to slug to a name starting "verify-", detached
# during a rebase, holding an uncommitted wip.txt) was removed exactly like a truly disposable one.
scratch_clean(){ local p="$1" st mh rm ra
  st=$(git -C "$p" status --porcelain 2>/dev/null) || return 1
  [[ -n "$st" ]] && return 1
  mh=$(git -C "$p" rev-parse --git-path MERGE_HEAD 2>/dev/null) && [[ -f "$mh" ]] && return 1
  rm=$(git -C "$p" rev-parse --git-path rebase-merge 2>/dev/null) && [[ -d "$rm" ]] && return 1
  ra=$(git -C "$p" rev-parse --git-path rebase-apply 2>/dev/null) && [[ -d "$ra" ]] && return 1
  return 0; }
# PI-34 round 4: `scratch_clean` alone let a *committed* resolution through — clean by `git status`, but its
# commit sat only in this worktree's detached HEAD, on no ref at all: `reviewer-conflict-pr7` between `git
# commit` and `git push` (nothing holds it open in between, across separate Bash calls), and a real agent
# worktree `verify-login` with a local `wip` commit never pushed, were both swept as "clean and unused". A
# scratch is only disposable when every commit reachable from its HEAD is also reachable from some remote-
# tracking ref — i.e. nothing on it exists solely in this one directory.
head_on_remote(){ local p="$1" out rc
  out=$(git -C "$p" rev-list HEAD --not --remotes 2>/dev/null); rc=$?
  (( rc == 0 )) && [[ -z "$out" ]]; }
older_24h(){ [[ -n "$(find "$1" -maxdepth 0 -mmin +1440 2>/dev/null)" ]]; }
in_use(){ command -v lsof >/dev/null 2>&1 && [[ -n "$(lsof +D "$1" 2>/dev/null)" ]]; }   # exit status is not
  # reliable here — measured 1 even with a match printed, once the open file sits below $1 rather than at it —
  # so this reads the actual listing (empty = nothing open there) instead of trusting lsof's own exit code.
kb(){ du -sk "$1" 2>/dev/null | cut -f1; }

removed=0; deleted=0; remote_deleted=0; kept=0; before=0; after=0
# PI-44: `keep` is the ONLY place that announces a kept branch or worktree, so it is the only place that
# increments `kept` — every call site below prints through it instead of its own `echo "kept …"`, which is what
# makes the summary's count equal the number of "kept " lines by construction, for every kept-path today and any
# added later, rather than something each new call site has to remember to do.
keep(){ echo "kept $1 ($2)"; kept=$((kept+1)); }
drop_branch(){ # $1 branch
  [[ -z "$1" ]] && return 0
  if (( DRY )); then echo "would delete branch $1"; deleted=$((deleted+1)); return 0; fi
  if g branch -D "$1" >/dev/null 2>&1; then echo "deleted branch $1"; deleted=$((deleted+1)); else keep "branch $1" "delete failed"; fi; }
# PI-38: every remote branch NOT currently checked out in one of this repo's own worktrees (a branch still
# checked out anywhere is left entirely to the loop above and to a later run once it is not — never touched
# here, so this pass never competes with the current worktree's own decision or removes a ref out from under
# a live worktree), read against every merged PR in one `gh` call. Deletes only a remote branch whose current
# tip equals a merged PR's own head — never by ancestry (AC3: squash breaks it by construction) — so a branch
# with an open PR, a closed-unmerged PR, no PR at all, or commits pushed after the PR merged (its tip then
# differs from every recorded head) is left alone. Protected/base branches are skipped even if a same-named
# PR exists. `gh` missing or `gh pr list` failing is reported and skips the whole pass; a `push --delete` that
# fails is reported and skips only that one branch — never aborts the pass or the script — and (PI-44) is one
# of two things, told apart instead of both being called "no permission or network": the branch is simply
# already gone from origin (this run's own `refs/remotes/origin` cache, taken by the single fetch near the top
# of the script, was stale by the time this push ran — see that fetch's own comment) and that is reported and
# never counted as kept, since nothing was kept by leaving it, it was already gone; or the push genuinely failed,
# which is counted (so the summary's kept count still holds, AC1) and reported with the cause git's own stderr
# gave, collapsed to one line — never a guessed cause.
remote_push_cause(){ # $1 raw stderr from a failed `git push --delete` → the cause actually observed, one line
  local line out=""                        # ("To <url>" is just the destination git prints, never the cause)
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    case "$line" in "To "*) continue;; esac
    out="${out:+$out; }$line"
  done <<<"$1"
  printf '%s' "${out:-cause unknown}"
}
reap_remote_branches(){
  command -v gh >/dev/null 2>&1 || { echo "remote branch cleanup skipped (gh not available)"; return 0; }
  g remote get-url origin >/dev/null 2>&1 || { echo "remote branch cleanup skipped (no origin)"; return 0; }
  local prs rc active wline rline name rsha found pname poid push_err
  prs=$(cd "$MAIN" && gh pr list --state merged --limit 1000 --json headRefName,headRefOid \
        --jq '.[] | "\(.headRefName)\t\(.headRefOid)"' 2>/dev/null); rc=$?
  (( rc == 0 )) || { echo "remote branch cleanup skipped (gh pr list failed, exit $rc)"; return 0; }
  # Read fresh, not from $entries (that snapshot predates the worktree loop above): a branch whose worktree
  # this same run just removed as merged must not be counted active here, or its remote never gets reaped
  # on the very run that made it eligible (PI-38 F1) — it would wait one more run for no reason.
  active=" "
  while IFS= read -r wline; do
    case "$wline" in "branch "*) active="$active ${wline#branch refs/heads/} ";; esac
  done < <(g worktree list --porcelain)
  while IFS= read -r rline; do
    [[ -z "$rline" ]] && continue
    name="${rline%% *}"; rsha="${rline#* }"
    [[ "$name" == "HEAD" || "$name" == "$rsha" ]] && continue
    [[ "$active" == *" $name "* ]] && continue
    protected "$name" && continue
    found=""
    while IFS=$'\t' read -r pname poid; do
      [[ "$pname" == "$name" && "$poid" == "$rsha" ]] && { found=1; break; }
    done <<<"$prs"
    [[ -z "$found" ]] && continue
    if (( DRY )); then echo "would delete remote branch $name (merged)"; remote_deleted=$((remote_deleted+1))
    else
      push_err=$(g push -q origin --delete "$name" 2>&1 1>/dev/null); rc=$?
      if (( rc == 0 )); then
        echo "deleted remote branch $name (merged)"; remote_deleted=$((remote_deleted+1))
      elif [[ "$push_err" == *"remote ref does not exist"* ]]; then
        # AC3: the local `refs/remotes/origin` cache this pass reads was stale — the branch was already gone
        # from the real origin, so nothing was kept by leaving it; never counted as kept, never re-attempted.
        echo "remote branch $name already gone from origin (stale tracking ref)"
      else
        keep "remote branch $name" "delete failed: $(remote_push_cause "$push_err")"
      fi
    fi
  done < <(g for-each-ref --format='%(refname:short) %(objectname)' refs/remotes/origin | sed 's#^origin/##')
}
remove(){ # $1 path, $2 reason, $3 branch to delete afterwards ("" for none), $4 lock reason to release first ("" for none)
  local p="$1" why="$2" b="$3" lr="${4:-}" k; k=$(kb "$p"); before=$((before+${k:-0}))
  if (( DRY )); then [[ -n "$lr" ]] && echo "would unlock worktree $p"; echo "would remove worktree $p ($why)"; removed=$((removed+1)); drop_branch "$b"; return 0; fi
  if [[ -n "$lr" ]]; then
    g worktree unlock "$p" >/dev/null 2>&1 || { keep "$p" "locked: $lr; unlock failed"; k=$(kb "$p"); after=$((after+${k:-0})); return 0; }
    echo "unlocked worktree $p"
  fi
  if g worktree remove --force "$p" >/dev/null 2>&1; then
    echo "removed worktree $p ($why)"; removed=$((removed+1))
    [[ -d "$p" ]] && { k=$(kb "$p"); after=$((after+${k:-0})); }
    drop_branch "$b"
  else
    [[ -n "$lr" ]] && g worktree lock --reason "$lr" "$p" >/dev/null 2>&1   # not removed: it stays protected as it was
    keep "$p" "git worktree remove failed"; k=$(kb "$p"); after=$((after+${k:-0})); fi; }
locked_entry(){ # $1 path, $2 sha, $3 branch, $4 lock reason → the only way out of a lock is a merged PR containing the tip
  local p="$1" sha="$2" b="$3" lr="$4" shown st why rc rel
  shown="locked: ${lr:-no reason given}"
  case "$lr" in "pocket-it: "*) ;; *) keep "$p" "$shown; not a pocket-it lock, never released — its owner runs: git -C $(printf '%q' "$MAIN") worktree unlock $(printf '%q' "$p")"; return 0;; esac
  if [[ ! -d "$p" ]]; then   # deleted from disk: the lock protects nothing any more, only the branch is left to judge
    if (( DRY )); then echo "would unlock and prune worktree $p (missing on disk)"
    elif g worktree unlock "$p" >/dev/null 2>&1; then g worktree prune >/dev/null 2>&1; echo "unlocked and pruned worktree $p (missing on disk)"
    else keep "$p" "$shown; missing on disk, unlock failed"; return 0; fi
    removed=$((removed+1))
    [[ -z "$b" ]] && return 0
    protected "$b" && (( ! ALL )) && { keep "branch $b" "protected"; return 0; }
    why=$(merged_pr "$sha" "$b"); rc=$?
    (( rc == 0 )) && { drop_branch "$b"; return 0; }
    (( rc == 2 )) && why="merged PRs unknown: $why"
    keep "branch $b" "${why:-no merged PR contains its tip}"; return 0; fi
  [[ -z "$b" ]] && { keep "$p" "$shown; no branch"; return 0; }
  rel="release if abandoned or merged without a PR: bash $(printf '%q' "$SELF_DIR/worktree.sh") --unlock $(printf '%q' "$MAIN") $(printf '%q' "$b")"
  protected "$b" && (( ! ALL )) && { keep "$p" "$shown; protected branch $b (--all to judge it); $rel"; return 0; }
  st=$(git -C "$p" status --porcelain 2>/dev/null) || { keep "$p" "$shown; git status failed"; return 0; }
  [[ -n "$st" ]] && { keep "$p" "$shown; dirty"; return 0; }
  why=$(merged_pr "$sha" "$b"); rc=$?
  (( rc == 0 )) && { remove "$p" "$why, lock released" "$b" "$lr"; return 0; }
  (( rc == 2 )) && { keep "$p" "$shown; merged PRs unknown: $why; $rel"; return 0; }
  keep "$p" "$shown; ${why:-no merged PR contains its tip}; $rel"; }

i=0
for e in "${entries[@]}"; do
  i=$((i+1)); (( i == 1 )) && continue
  IFS="$SEP" read -r p sha branch flags lockr <<<"$e"
  [[ "$(abs "$p")" == "$CUR" ]] && { keep "$p" "current worktree"; continue; }
  case " $flags " in *" locked "*) locked_entry "$p" "$sha" "$branch" "$lockr"; continue;; esac
  case " $flags " in *" prunable "*)
    echo "pruned worktree $p (missing on disk)"; removed=$((removed+1)); (( DRY )) || g worktree prune >/dev/null 2>&1
    [[ -n "$branch" ]] && ( protected "$branch" && (( ! ALL )) ) && continue
    [[ -n "$branch" ]] && decide "$sha" "$branch" >/dev/null && drop_branch "$branch"; continue;; esac
  case " $flags " in *" detached "*)
    P="$(abs "$p")"
    if is_scratch_new "$P"; then
      if ! scratch_clean "$p"; then keep "$p" "detached scratch, dirty or mid-merge/rebase — holds work nothing else has a copy of"
      elif ! head_on_remote "$p"; then keep "$p" "detached scratch, HEAD has commits not on any remote — holds work nothing else has a copy of"
      elif in_use "$p"; then keep "$p" "detached scratch, in use"
      elif command -v lsof >/dev/null 2>&1; then remove "$p" "detached scratch, clean and unused" ""
      elif older_24h "$p"; then remove "$p" "detached scratch older than 24 h (lsof unavailable)" ""
      else keep "$p" "detached scratch, cannot confirm unused (lsof unavailable, under 24 h)"; fi
    elif is_scratch_legacy "$P" && older_24h "$p"; then remove "$p" "detached scratch older than 24 h" ""
    else keep "$p" "detached"; fi; continue;; esac
  [[ -z "$branch" ]] && { keep "$p" "no branch"; continue; }
  protected "$branch" && (( ! ALL )) && { keep "$p" "protected branch $branch"; continue; }
  st=$(git -C "$p" status --porcelain 2>/dev/null) || { keep "$p" "git status failed"; continue; }   # unreadable is never clean
  [[ -n "$st" ]] && { keep "$p" "dirty"; continue; }
  why=$(decide "$sha" "$branch") || { keep "$p" "$why"; continue; }
  remove "$p" "$why" "$branch"
done
reap_remote_branches
(( DRY )) || g worktree prune >/dev/null 2>&1

mb=$(awk -v k=$((before-after)) 'BEGIN{printf "%.1f", k/1024}')
if (( DRY )); then echo "cleanup-merged (dry-run): $removed worktrees would be removed, $deleted branches would be deleted, $remote_deleted remote branches would be deleted, $kept kept, would free $mb MB"
else echo "cleanup-merged: $removed worktrees removed, $deleted branches deleted, $remote_deleted remote branches deleted, $kept kept, freed $mb MB"; fi
exit 0
