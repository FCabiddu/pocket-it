# Retries a network command (gh, git fetch/push/ls-remote) when it fails because of the network:
# DNS down or GitHub unreachable for 1-2 minutes (frictions of 08/10 and 14/10).
# An error that is not network-related (missing PR, rejected merge) exits at once.
#   source network.sh; rete gh pr view 12 --json state
# NET_WAITS: seconds to wait between attempts (default «10 20 30 60», about 2 minutes).

rete_errore='error connecting to|could not resolve host|could not resolve hostname|temporary failure in name resolution|connection (reset|refused|timed out)|operation timed out|tls handshake|unable to access|i/o timeout|no such host|network is unreachable|unexpected eof|http 50[234]'

rete() {
  local err rc attesa
  err=$(mktemp)
  for attesa in ${NET_WAITS-10 20 30 60} fine; do
    rc=0; "$@" 2>"$err" || rc=$?
    if [ "$rc" -eq 0 ]; then cat "$err" >&2; rm -f "$err"; return 0; fi
    if [ "$attesa" = fine ] || ! grep -qiE "$rete_errore" "$err"; then
      cat "$err" >&2; rm -f "$err"; return "$rc"
    fi
    echo "rete: $1 failed because of the network ($(grep -iEm1 "$rete_errore" "$err")), retrying in $attesa s" >&2
    sleep "$attesa"
  done
}
