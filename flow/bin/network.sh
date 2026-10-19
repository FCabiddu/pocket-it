# Retries a network command (gh, git fetch/push/ls-remote) when it fails because of the network:
# DNS down or GitHub unreachable for 1-2 minutes (frictions of 08/10 and 14/10).
# An error that is not network-related (missing PR, rejected merge) exits at once.
#   source network.sh; retry gh pr view 12 --json state
# NET_WAITS: seconds to wait between attempts (default «10 20 30 60», about 2 minutes).

retry_error_rx='error connecting to|could not resolve host|could not resolve hostname|temporary failure in name resolution|connection (reset|refused|timed out)|operation timed out|tls handshake|unable to access|i/o timeout|no such host|network is unreachable|unexpected eof|http 50[234]'

retry() {
  local err rc pause
  err=$(mktemp)
  for pause in ${NET_WAITS-10 20 30 60} end; do
    rc=0; "$@" 2>"$err" || rc=$?
    if [ "$rc" -eq 0 ]; then cat "$err" >&2; rm -f "$err"; return 0; fi
    if [ "$pause" = end ] || ! grep -qiE "$retry_error_rx" "$err"; then
      cat "$err" >&2; rm -f "$err"; return "$rc"
    fi
    echo "retry: $1 failed because of the network ($(grep -iEm1 "$retry_error_rx" "$err")), retrying in $pause s" >&2
    sleep "$pause"
  done
}
