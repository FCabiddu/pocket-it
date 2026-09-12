#!/usr/bin/env bash
# Self-test for guard.sh: each line is "expect|command" where expect is BLOCK or ALLOW.
cd "$(dirname "$0")"
HOOKDIR="$PWD"
fail=0
while IFS='|' read -r expect cmd; do
  [[ -z "$expect" || "$expect" == \#* ]] && continue
  payload=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")
  if printf '%s' "$payload" | bash ./guard.sh >/dev/null 2>&1; then got=ALLOW; else got=BLOCK; fi
  if [[ "$got" == "$expect" ]]; then echo "ok    $got  $cmd"; else echo "FAIL  want $expect got $got  $cmd"; fail=1; fi
done <<'CASES'
BLOCK|gh pr merge 12 --squash
BLOCK|cd repo && gh pr merge --auto 4
BLOCK|git push origin main
BLOCK|git push -u origin main
BLOCK|git push --force origin main
BLOCK|git push origin HEAD:main
BLOCK|pkill -f next-server
BLOCK|killall node
BLOCK|gh variable set APP_STATUS --body prod
BLOCK|sleep 30 && gh pr checks 3
BLOCK|sleep 5; gh pr view 163
ALLOW|gh variable get APP_STATUS >/dev/null 2>&1 || gh variable set APP_STATUS --body dev
ALLOW|git push -u origin task/t-1-2-3-slug
ALLOW|git push -u origin feat/main-menu
ALLOW|git pull --ff-only origin main
ALLOW|git checkout main && git pull origin main
ALLOW|gh pr checks 3 --watch --interval 30
ALLOW|lsof -nP -iTCP:3100 -sTCP:LISTEN -t | xargs -r kill
ALLOW|gh pr ready 12 && gh pr comment 12 --body ok
ALLOW|until gh pr view 3 --json mergeable --jq .mergeable | grep -qv UNKNOWN; do sleep 2; done
ALLOW|git commit -m "docs: explain why pkill/killall and gh pr merge are blocked"
ALLOW|gh pr comment 12 --body "never run git push origin main from an agent"
BLOCK|echo "harmless" && gh pr merge 7
ALLOW|POCKET_IT_USER_MERGE=1 gh pr merge 8 --merge --delete-branch
BLOCK|POCKET_IT_USER_MERGE=0 gh pr merge 8 --merge
BLOCK|git push origin HEAD:main
ALLOW|POCKET_IT_ORCHESTRATOR_PUSH=1 git push origin main
ALLOW|POCKET_IT_ORCHESTRATOR_PUSH=1 git push origin HEAD:main
ALLOW|POCKET_IT_ORCHESTRATOR_PUSH=1 git push -u origin task/pi-10-slug
BLOCK|POCKET_IT_ORCHESTRATOR_PUSH=1 git push --force origin main
BLOCK|POCKET_IT_ORCHESTRATOR_PUSH=1 git push -f origin main
CASES

# --- Fixtures: branch-resolution cases (PI-4). A bare `git push`/`git push origin HEAD` only
# resolves to a block when the branch it actually updates is main/master, so these need real
# git repos checked out on known branches rather than string matching alone.
TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

mk_repo() {
  local dir="$1" branch="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q -b "$branch"
  git -C "$dir" -c user.email=t@t.example -c user.name=test commit -q --allow-empty -m init
}
mk_repo "$TMPROOT/main-repo" main
mk_repo "$TMPROOT/feat-repo" feat/x
mkdir -p "$TMPROOT/not-a-repo" "$TMPROOT/neutral"
MISSING="$TMPROOT/does-not-exist"

expect_case() {
  local expect="$1" cwd="$2" cmd="$3"
  local payload got
  payload=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")
  if (cd "$cwd" && printf '%s' "$payload" | bash "$HOOKDIR/guard.sh") >/dev/null 2>&1; then got=ALLOW; else got=BLOCK; fi
  if [[ "$got" == "$expect" ]]; then echo "ok    $got  [cwd=$(basename "$cwd")] $cmd"; else echo "FAIL  want $expect got $got  [cwd=$(basename "$cwd")] $cmd"; fail=1; fi
}

# AC1 — on branch main, these all resolve to main and must block.
expect_case BLOCK "$TMPROOT/main-repo" "git push"
expect_case BLOCK "$TMPROOT/main-repo" "git push origin HEAD"
expect_case BLOCK "$TMPROOT/main-repo" "git push -u origin HEAD"
expect_case BLOCK "$TMPROOT/main-repo" "git push -q origin HEAD:main"
expect_case BLOCK "$TMPROOT/main-repo" "git push origin HEAD:refs/heads/main"

# AC2 — on branch feat/x, the same forms (plus pushing the branch by name) must pass.
expect_case ALLOW "$TMPROOT/feat-repo" "git push"
expect_case ALLOW "$TMPROOT/feat-repo" "git push origin HEAD"
expect_case ALLOW "$TMPROOT/feat-repo" "git push -u origin HEAD"
expect_case ALLOW "$TMPROOT/feat-repo" "git push -u origin feat/x"

# AC3 — compound commands resolve the branch of the cd target / -C path, not the hook's cwd;
# an unresolvable path falls back to the hook's cwd; a non-repo hook cwd passes.
expect_case BLOCK "$TMPROOT/neutral" "cd $TMPROOT/main-repo && git push origin HEAD"
expect_case ALLOW "$TMPROOT/neutral" "cd $TMPROOT/feat-repo && git push origin HEAD"
expect_case BLOCK "$TMPROOT/neutral" "git -C $TMPROOT/main-repo push origin HEAD"
expect_case ALLOW "$TMPROOT/neutral" "git -C $TMPROOT/feat-repo push origin HEAD"
expect_case BLOCK "$TMPROOT/main-repo" "cd $MISSING && git push origin HEAD"
expect_case ALLOW "$TMPROOT/feat-repo" "cd $MISSING && git push origin HEAD"
expect_case ALLOW "$TMPROOT/not-a-repo" "git push origin HEAD"

# AC4 — force push blocked by name or by current branch being main; allowed on a feature branch.
expect_case BLOCK "$TMPROOT/main-repo" "git push --force"
expect_case BLOCK "$TMPROOT/main-repo" "git push -f origin HEAD"
expect_case BLOCK "$TMPROOT/feat-repo" "git push --force origin main"
expect_case ALLOW "$TMPROOT/feat-repo" "git push -f"

# PI-10 AC1-AC4 — the POCKET_IT_ORCHESTRATOR_PUSH=1 prefix authorizes an implicit push to main
# (bare `git push` resolved from the current branch), but never a force-push, even prefixed.
expect_case BLOCK "$TMPROOT/main-repo" "git push"
expect_case ALLOW "$TMPROOT/main-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push"
expect_case BLOCK "$TMPROOT/main-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push --force"
expect_case BLOCK "$TMPROOT/main-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push -f origin HEAD"
expect_case ALLOW "$TMPROOT/feat-repo" "POCKET_IT_ORCHESTRATOR_PUSH=1 git push"

exit $fail
