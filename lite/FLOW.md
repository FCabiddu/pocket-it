# The lite flow

The flow described by `CLAUDE.md` (rules v7), the agents in `.claude/agents/`, the scripts in `bin/` and the hooks in `hooks/`. It is updated whenever one of them changes. What every agent, script and hook does is in the [README](../README.md#lite).

## 1 · The big picture

Once, at the start of a project, `project-ready.sh` checks that the project has the scripts the flow uses (`templates/README.md`); whatever is missing, the architect creates from the templates. A feature goes through these steps; small work (a bug, a change) is done by the main session alone, on a branch, with a PR and a merge.

```mermaid
flowchart LR
    R(["Request"]) --> A["1 · analyst<br/>requirements"] --> U{"user approves?"}
    U -- "yes" --> AR["2 · architect<br/>design"] --> TW["3 · task-writer<br/>tasks and waves"]
    TW --> O["4 · Wave<br/>developer + reviewer"] --> T["5 · tester<br/>E2E"] --> M["6 · main"]
    M -- "next wave" --> O
    M -- "done" --> F(["Done"])
```

## 2 · A wave

The tasks of a wave run in parallel, each with its own developer.

```mermaid
flowchart TD
    B["branch wave/slug-N<br/>from main"] --> D["developer<br/>code + fast tests"]
    D --> R{"reviewer<br/>reads the code"}
    R -- "changes" --> D
    R -- "ok" --> P["merge into the wave branch<br/>(tsc, lint, unit run automatically)"]
```

## 3 · E2E and errors

At the end of a wave, before `main`, tester and security work in parallel; their findings are fixed together. If the project's directives defer the E2E (for example to the release), the tester writes them without running them and the wave goes to `main` with its approved PR. If a choice is needed that the design did not make, the architect decides (and the user, if there is something to decide).

```mermaid
flowchart TD
    T["tester<br/>writes and runs the E2E"] --> V{"green?"}
    S["security<br/>looks for holes in the wave's diff"] --> SO{"ok?"}
    SO -- "holes" --> D
    SO -- "SECURITY OK<br/>security-ok.sh" --> M
    V -- "yes" --> M["the wave goes to main<br/>(merge-pr.sh requires the security sign-off)"]
    V -- "wrong test" --> T
    V -- "app bugs" --> D["developer fixes<br/>every finding of the round<br/>reviewer checks"]
    D -- "one RERUN (rerun):<br/>rerun the reds" --> T
    D -. "still red after 2 rounds" .-> U["ask the user"]
```

## End of a wave

With the wave on `main`: `errors.sh` and the agents' reports; every friction is one line in `docs/recap/friction.md` (the third time it is damage), every damage a recap discussed with the user; then `clean-wave.sh` removes the wave's tasks from `main`, and the next wave starts.
