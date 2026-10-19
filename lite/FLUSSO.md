# Flusso del sistema lite

Il flusso descritto da `CLAUDE.md` (regole v7), dagli agenti in `.claude/agents/`, dagli script in `bin/` e dagli hook in `hooks/`. Va aggiornato quando cambia uno di questi. Cosa fa ogni agente, script e hook è nel [README](../README.md#lite).

## 1 · Il quadro

All'inizio di un progetto, una volta, `progetto-pronto.sh` controlla che il progetto abbia gli script che il flusso usa (`templates/README.md`); se manca qualcosa, l'architect lo crea dai modelli. Una feature passa da questi passi; il lavoro piccolo (bug, modifica) lo fa la sessione principale da sola, su un branch, con PR e merge.

```mermaid
flowchart LR
    R(["Richiesta"]) --> A["1 · analyst<br/>requisiti"] --> U{"l'utente approva?"}
    U -- "sì" --> AR["2 · architect<br/>design"] --> TW["3 · task-writer<br/>task e onde"]
    TW --> O["4 · Onda<br/>developer + reviewer"] --> T["5 · tester<br/>E2E"] --> M["6 · main"]
    M -- "altra onda" --> O
    M -- "finito" --> F(["Fatto"])
```

## 2 · Un'onda

I task di un'onda girano in parallelo, ognuno con il suo developer.

```mermaid
flowchart TD
    B["branch onda/slug-N<br/>da main"] --> D["developer<br/>codice + test veloci"]
    D --> R{"reviewer<br/>legge il codice"}
    R -- "da correggere" --> D
    R -- "ok" --> P["merge nel branch dell'onda<br/>(tsc, lint, unit automatici)"]
```

## 3 · Gli E2E e gli errori

A fine onda, prima di main, tester e security lavorano in parallelo; le loro righe si correggono insieme. Se le direttive del progetto rimandano gli E2E (per esempio al rilascio), il tester li scrive senza lanciarli e l'onda va su main con la sua PR approvata. Se serve una scelta che il design non ha fatto, decide l'architect (e l'utente se c'è da decidere).

```mermaid
flowchart TD
    T["tester<br/>scrive e lancia gli E2E"] --> V{"verdi?"}
    S["security<br/>cerca i buchi nel diff dell'onda"] --> SO{"ok?"}
    SO -- "buchi" --> D
    SO -- "SICUREZZA OK<br/>sicurezza-ok.sh" --> M
    V -- "sì" --> M["l'onda va su main<br/>(merge-pr.sh vuole l'ok del security)"]
    V -- "test sbagliato" --> T
    V -- "errori dell'app" --> D["developer corregge<br/>tutte le righe del giro<br/>reviewer controlla"]
    D -- "un solo RIGIRA:<br/>rilancia i rossi" --> T
    D -. "2 giri ancora rosso" .-> U["si chiede all'utente"]
```

## Fine onda

Con l'onda su main: `errori.sh` e i report degli agenti; ogni attrito è una riga in `docs/recap/attriti.md` (alla terza volta è un danno), ogni danno un recap discusso con l'utente; poi `pulisci-onda.sh` toglie da main i task dell'onda, e parte l'onda dopo.
