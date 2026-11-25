#!/usr/bin/env bash
# service-check.sh — check that systemd services are running, and optionally
# restart the ones that are not.
#
# Exit codes: 0 = all running, 1 = restarted successfully, 2 = still down, 3 = usage / no systemd
#
# Usage: service-check.sh [-r] service [service ...]
#        sudo service-check.sh -r nginx postgresql

set -euo pipefail

# Can be pointed at a fake systemctl for testing
SYSTEMCTL="${SYSTEMCTL:-systemctl}"
# Seconds to wait after a restart before re-checking
RESTART_WAIT="${RESTART_WAIT:-2}"
RESTART=0

usage() {
  cat <<'EOF'
Usage: service-check.sh [-r] service [service ...]

  -r   restart services that are not active (needs root / sudo)
  -h   show this help

Exit codes: 0 all running, 1 restarted OK, 2 still down, 3 usage error or no systemd
EOF
}

while getopts ":rh" opt; do
  case "$opt" in
    r) RESTART=1 ;;
    h) usage; exit 0 ;;
    *) echo "Unknown option: -$OPTARG" >&2; usage >&2; exit 3 ;;
  esac
done
shift $((OPTIND - 1))

if (( $# == 0 )); then
  usage >&2
  exit 3
fi

if ! command -v "$SYSTEMCTL" >/dev/null 2>&1; then
  echo "systemctl not found — this script needs a systemd-based Linux system" >&2
  exit 3
fi

restarted=0
down=0

for svc in "$@"; do
  state=$("$SYSTEMCTL" is-active "$svc" 2>/dev/null || true)
  state=${state:-unknown}

  if [[ "$state" == "active" ]]; then
    printf '[ OK ] %-24s active\n' "$svc"
    continue
  fi

  printf '[DOWN] %-24s %s\n' "$svc" "$state"

  if (( RESTART == 0 )); then
    down=$((down + 1))
    continue
  fi

  echo "       restarting $svc ..."
  if "$SYSTEMCTL" restart "$svc" 2>/dev/null && sleep "$RESTART_WAIT" &&
     [[ "$("$SYSTEMCTL" is-active "$svc" 2>/dev/null || true)" == "active" ]]; then
    printf '[FIXD] %-24s active after restart\n' "$svc"
    restarted=$((restarted + 1))
  else
    printf '[FAIL] %-24s still not active — check: journalctl -u %s -n 50\n' "$svc" "$svc"
    down=$((down + 1))
  fi
done

if (( down > 0 )); then exit 2
elif (( restarted > 0 )); then exit 1
else exit 0
fi
