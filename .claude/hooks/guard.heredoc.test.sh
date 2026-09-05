#!/usr/bin/env bash
# A commit whose heredoc body mentions blocked commands must be ALLOWED (false-positive check).
cd "$(dirname "$0")"
payload=$(python3 -c '
import json
body = "refactor: guard blocks pkill and gh pr merge\n\nAlso never git push origin main.\n"
cmd = "git commit -m \"$(cat <<" + chr(39) + "EOF" + chr(39) + "\n" + body + "EOF\n)\""
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}}))
')
if printf '%s' "$payload" | bash ./guard.sh >/dev/null 2>&1; then
  echo "ok    ALLOW  commit with heredoc mentioning blocked commands"; exit 0
else
  echo "FAIL  heredoc commit message was blocked"; exit 1
fi
