#!/usr/bin/env bash
# Self-test for guard.sh: each line is "expect|command" where expect is BLOCK or ALLOW.
cd "$(dirname "$0")"
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
CASES
exit $fail
