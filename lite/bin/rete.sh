# Ripete un comando di rete (gh, git fetch/push/ls-remote) quando fallisce per la rete:
# DNS caduto o GitHub non raggiungibile per 1-2 minuti (attriti dell'08/10 e del 14/10).
# Un errore che non è di rete (PR inesistente, merge rifiutato) esce subito.
#   source rete.sh; rete gh pr view 12 --json state
# RETE_ATTESE: secondi di attesa fra i tentativi (default «10 20 30 60», circa 2 minuti).

rete_errore='error connecting to|could not resolve host|could not resolve hostname|temporary failure in name resolution|connection (reset|refused|timed out)|operation timed out|tls handshake|unable to access|i/o timeout|no such host|network is unreachable|unexpected eof|http 50[234]'

rete() {
  local err rc attesa
  err=$(mktemp)
  for attesa in ${RETE_ATTESE-10 20 30 60} fine; do
    rc=0; "$@" 2>"$err" || rc=$?
    if [ "$rc" -eq 0 ]; then cat "$err" >&2; rm -f "$err"; return 0; fi
    if [ "$attesa" = fine ] || ! grep -qiE "$rete_errore" "$err"; then
      cat "$err" >&2; rm -f "$err"; return "$rc"
    fi
    echo "rete: $1 fallito per la rete ($(grep -iEm1 "$rete_errore" "$err")), riprovo fra $attesa s" >&2
    sleep "$attesa"
  done
}
