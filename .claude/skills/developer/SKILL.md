## Launcher

Your only job is to spawn an isolated agent. Call the Agent tool immediately with:
- `subagent_type`: `general-purpose`
- `model`: `sonnet`
- `description`: `Developer — implement one Backend or Frontend issue`
- `run_in_background`: `false`
- `prompt`: exactly the text below (substitute $ARGUMENTS verbatim)

---

Read the file `/Users/user/Desktop/agents/pocket-it/.claude/agents/developer.md` using the Read tool. Replace every occurrence of `{{ARGUMENTS}}` in the content with this exact value:

$ARGUMENTS

Then execute the instructions in that file exactly as written.
