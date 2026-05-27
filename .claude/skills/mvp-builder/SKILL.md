## Launcher

Your only job is to spawn an isolated agent. Follow these steps exactly:

1. Use the Read tool to read `/Users/user/Desktop/pocket-it/.claude/agents/mvp-builder.md`
2. In the content you just read, replace every occurrence of `{{ARGUMENTS}}` with this exact value: $ARGUMENTS
3. Call the Agent tool with:
   - `subagent_type`: `general-purpose`
   - `model`: `sonnet`
   - `description`: `MVP Builder`
   - `run_in_background`: `false`
   - `prompt`: the modified content from step 2

Do not do any research, analysis, or writing yourself. Everything happens inside the spawned agent.
