#!/usr/bin/env bash
# Segna che l'agente security ha risposto `SICUREZZA OK` sulla PR di un'onda verso main.
#   sicurezza-ok.sh <PR>     (da dentro il repo)
# Mette lo stato «security» = success sul commit di testa della PR. merge-pr.sh non porta
# un'onda su main senza quello stato sul commit che mergia: un commit aggiunto dopo l'ok
# (una correzione, un merge di main) chiede un nuovo controllo di security.
set -euo pipefail
die() { echo "sicurezza-ok: $1" >&2; exit "${2:-1}"; }
pr="${1:-}"; [ -n "$pr" ] || die "uso: sicurezza-ok.sh <PR>" 2
read -r state branch base head < <(gh pr view "$pr" --json state,headRefName,baseRefName,headRefOid -q '.state + " " + .headRefName + " " + .baseRefName + " " + .headRefOid')
[ "$state" = OPEN ] || die "la PR $pr è $state, non OPEN"
case "$branch" in onda/*) ;; *) die "la PR $pr non è di un'onda ($branch)";; esac
[ "$base" = main ] || die "la PR $pr va verso $base, non verso main"
gh api -X POST "repos/{owner}/{repo}/statuses/$head" -f state=success -f context=security \
  -f description="SICUREZZA OK dell'agente security" >/dev/null
echo "sicurezza-ok: PR $pr, commit ${head:0:8} segnato"
