#!/usr/bin/env bash
# network-check.sh — first-line check for "the internet / the app is down" tickets.
#
# For each target it checks, in order:
#   1. DNS     — does the name resolve to an IP address?
#   2. TCP     — can we open a connection to the port (default 443)?
# It also shows the default gateway, so you can tell a local network problem
# from a problem with one remote service.
#
# Exit codes: 0 = all targets reachable, 1 = some failed, 2 = all failed, 3 = usage error
#
# Usage: network-check.sh [-p PORT] [-t SECONDS] [host ...]
#        network-check.sh -p 8080 intranet.local app.example.com

set -euo pipefail

PORT=443
TIMEOUT=3
DEFAULT_TARGETS=(google.com github.com microsoft.com)

usage() {
  cat <<'EOF'
Usage: network-check.sh [-p PORT] [-t SECONDS] [host ...]

  -p PORT     TCP port to test (default 443)
  -t SECONDS  timeout per connection (default 3)
  -h          show this help

With no hosts, checks google.com, github.com and microsoft.com.
A host can include its own port: app.example.com:8443
EOF
}

while getopts ":p:t:h" opt; do
  case "$opt" in
    p) PORT="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;;
    h) usage; exit 0 ;;
    :) echo "Option -$OPTARG needs a value" >&2; exit 3 ;;
    *) echo "Unknown option: -$OPTARG" >&2; usage >&2; exit 3 ;;
  esac
done
shift $((OPTIND - 1))

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
  echo "Port must be a number from 1 to 65535 (got $PORT)" >&2
  exit 3
fi

TARGETS=("$@")
(( ${#TARGETS[@]} == 0 )) && TARGETS=("${DEFAULT_TARGETS[@]}")

default_gateway() {
  if command -v ip >/dev/null 2>&1; then
    ip route show default 2>/dev/null | awk '/default/ { print $3; exit }'
  elif [[ -r /proc/net/route ]]; then
    # Gateway is stored as little-endian hex in /proc/net/route
    awk '$2 == "00000000" { print $3; exit }' /proc/net/route |
      sed -E 's/(..)(..)(..)(..)/0x\4 0x\3 0x\2 0x\1/' |
      xargs -r printf '%d.%d.%d.%d\n'
  fi
}

resolve() {
  getent ahosts "$1" 2>/dev/null | awk '{ print $1; exit }'
}

tcp_open() {
  local host=$1 port=$2
  # Pass host and port as arguments rather than building a command string
  # shellcheck disable=SC2016  # $0/$1 must expand in the child shell, not here
  timeout "$TIMEOUT" bash -c 'exec 3<>"/dev/tcp/$0/$1"' "$host" "$port" 2>/dev/null
}

echo "Network check — $(date '+%Y-%m-%d %H:%M')"
gw=$(default_gateway || true)
if [[ -n "$gw" ]]; then
  echo "Default gateway: $gw"
else
  echo "Default gateway: none found (check the cable / Wi-Fi / VPN first)"
fi
echo

ok=0
failed=0
for target in "${TARGETS[@]}"; do
  host=${target%%:*}
  port=$PORT
  [[ "$target" == *:* ]] && port=${target##*:}

  ip=$(resolve "$host" || true)
  if [[ -z "$ip" ]]; then
    printf '[FAIL] %-28s DNS lookup failed — check DNS server settings\n' "$host"
    failed=$((failed + 1))
    continue
  fi

  if tcp_open "$host" "$port"; then
    printf '[ OK ] %-28s %s port %s reachable\n' "$host" "$ip" "$port"
    ok=$((ok + 1))
  else
    printf '[FAIL] %-28s %s port %s not reachable within %ss — firewall, proxy or service down\n' \
      "$host" "$ip" "$port" "$TIMEOUT"
    failed=$((failed + 1))
  fi
done

echo
echo "Summary: $ok reachable, $failed failed"
if (( failed == 0 )); then exit 0
elif (( ok == 0 )); then exit 2
else exit 1
fi
