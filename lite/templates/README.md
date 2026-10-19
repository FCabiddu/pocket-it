# What the lite flow expects from a project

The agents and the scripts in `lite/bin/` are the same for every project; what changes from one project to the next lives in a few project files with a fixed contract. `lite/bin/project-ready.sh` checks that they exist: the main session runs it once, at the start of a project, and if it is red the `architect` creates the missing pieces from these templates, adapts them to the stack and tries them out.

| Project file | Used by | What it must do | Template |
|---|---|---|---|
| `CLAUDE.md` with the line `Technical directives file: \`<path>\`` | every agent | say where the directives are | — |
| the directives file | every agent | stack, structure, patterns, tests, invariants, security, environment (`architect.md`) | — |
| `docs/security/audit-<date>.md` | `security`, `project-ready.sh` | the first security audit of the whole project (`security.md`, Audit job) | — |
| `scripts/pre-merge.sh` | `merge-pr.sh`, before every merge | fast checks (typecheck, lint, unit) on the PR code merged with its base; exit 0 or 1. Without it, `merge-pr.sh` does not merge | `pre-merge.sh` |
| `scripts/e2e.sh <spec...>` | the `tester` | one E2E run at a time on the machine (a local queue), build if needed, one line in the log `<git-common-dir>/e2e-runs/` | `e2e.sh` |
| `scripts/e2e-select.sh [--base] [--head] [--check]` | the `tester` | from the changed files, the specs to run on stdout and the reason on stderr; `--check` checks the map | `e2e-select.sh` + `spec-per-folder.txt` |
| `.claude/settings.json` | Claude Code, on every Bash command of the agents | the sandbox (below): network only to GitHub and npm, no reading of `.env*`, `~/.ssh`, `~/.aws`, local servers allowed; `gh` and the `lite/bin` scripts that use it run outside the sandbox | `settings.json` |

The `E2E:` line in `CLAUDE.md` says when the E2E run: `E2E: end of wave` (at the end of every wave: the tester runs them, step 6 of the global rules), `E2E: at release` (at release: the tester writes them without running them, `e2e.sh` refuses to start unless `E2E_FORCE=1`, and they run only in the round before a release, for example with a `scripts/release.sh`: build, checks, E2E) or `E2E: none` (none, below). `project-ready.sh` requires the line.

The line `Deploy from main: yes` or `Deploy from main: no` in `CLAUDE.md` says whether a merge to `main` deploys to production (and consumes builds or credits); `project-ready.sh` requires it, so the main session knows and tells the user before the first merge to `main`. With `sì`, every merge to `main` is a deploy and the global rule applies: only on explicit instruction.

The line `Commands only with approval: <regex>, <regex>, ...` in `CLAUDE.md` lists the commands an agent never runs on its own: the hook `lite/hooks/costly-commands.sh` stops the subagent that tries (exit 2) and tells it to ask in its report; the main session passes, because it is the one that asks the user. Python regexes separated by commas (so no commas inside), searched in the command text, even inside `bash -c '...'`; example: `Commands only with approval: netlify deploy, supabase db push, node scripts/genera-.*\.mjs`. A project with none writes `Commands only with approval: none`. `project-ready.sh` requires the line. The levels:

| Level | Examples | Who decides |
|---|---|---|
| free | tests, lint, local builds, git on one's own branch | the agent |
| with a trace | `gh pr create`, `npm install`, calls to test services | the agent, and it ends up in the PR body |
| only with approval | paid AI calls, databases with real data, deploys, sending email | the user, through the main session: the `Commands only with approval` line |

A project without E2E (a library, a CLI covered by unit tests only) writes `E2E: none` in `CLAUDE.md`: no `e2e.sh` or `e2e-select.sh`, and the waves have no tester task.

## Sandbox

`.claude/settings.json` (template `settings.json`, tried out on 2026-10-16 on a Next.js project) closes every Bash command of the agents inside the Claude Code sandbox: it writes only in the project and in temporary folders, talks only to `github.com`, `api.github.com`, `*.githubusercontent.com` and `registry.npmjs.org`, does not read `.env*` (not even through the symlink made by `worktree-new.sh`), `~/.ssh` or `~/.aws`. `permissions.deny` on `Read(**/.env*)` is needed separately, because `denyRead` does not stop the Read tool. A project that needs other domains (a test API, a CDN) adds them to `allowedDomains`. Worth knowing:
- `gh` fails TLS verification inside the sandbox (Go programs, documented by Claude Code), so it sits in `excludedCommands` together with the `lite/bin` scripts that call it (`merge-pr.sh`, `worktree-new.sh`, `security-ok.sh`, `clean-wave.sh`). The exclusion holds only for a bare call: with a pipe, `$(...)`, `cd` or another command on the same line everything stays in the sandbox and `gh` fails. That is why PRs are opened with `--body-file` and `gh` is never called from inside other scripts.
- `git fetch`/`push` pass only with an HTTPS remote (`https://github.com/<user>/<repo>.git`, credentials in the keychain): over SSH the sandbox proxy does not let the connection through.
- The dev server and `curl` on localhost work (`allowLocalBinding`); `pgrep`/`pkill` work with `com.apple.sysmond` in `allowMachLookup`. Playwright's Chromium cannot register its Mach service and exits at startup: in `playwright.config.ts` pass `--single-process` when `SANDBOX_RUNTIME` is set; outside the sandbox nothing changes.
- A wrong key (for example `allowMachLookup: true` instead of a list) makes the whole file be ignored, sandbox included, without stopping the session. `project-ready.sh` checks keys and types; in the session `/sandbox` says whether it is active, and sandboxed commands see `SANDBOX_RUNTIME=1`.

In the templates only the «TO ADAPT» (to adapt) block changes; the rest (queue, log, output) is what the agents expect. A project may rewrite `e2e-select.sh` with finer logic (for example following imports), as long as it keeps the contract and the output.
