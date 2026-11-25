#!/usr/bin/env bash
# collect-logs.sh — gather the information a second-line or vendor support team
# usually asks for, into one .tar.gz you can attach to a ticket.
#
# Collects: OS and hardware summary, disk and memory, network config, top
# processes, failed services and recent system logs. Lines that look like
# passwords, tokens or keys are masked before anything is saved.
#
# Usage: collect-logs.sh [-o OUTPUT_DIR] [-n LOG_LINES] [-h]

set -euo pipefail

OUT_DIR="."
LINES=500

usage() {
  cat <<'EOF'
Usage: collect-logs.sh [-o OUTPUT_DIR] [-n LOG_LINES]

  -o DIR   where to write the bundle (default: current folder)
  -n N     how many recent log lines to include (default 500)
  -h       show this help
EOF
}

while getopts ":o:n:h" opt; do
  case "$opt" in
    o) OUT_DIR="$OPTARG" ;;
    n) LINES="$OPTARG" ;;
    h) usage; exit 0 ;;
    :) echo "Option -$OPTARG needs a value" >&2; exit 3 ;;
    *) echo "Unknown option: -$OPTARG" >&2; usage >&2; exit 3 ;;
  esac
done

if ! [[ "$LINES" =~ ^[0-9]+$ ]]; then
  echo "-n must be a whole number (got $LINES)" >&2
  exit 3
fi
mkdir -p "$OUT_DIR"

HOST=$(hostname)
STAMP=$(date '+%Y%m%d-%H%M%S')
NAME="support-bundle-${HOST}-${STAMP}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/$NAME"

# Mask anything that looks like a secret: password=..., token: ..., api_key ...
redact() {
  sed -E 's/((pass(word)?|passwd|secret|token|api[_-]?key)[[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1********/Ig'
}

# capture FILE COMMAND... — run a command, save its output (or the error) to FILE
capture() {
  local file=$1; shift
  {
    echo "\$ $*"
    if command -v "$1" >/dev/null 2>&1; then
      "$@" 2>&1 || echo "(command exited with an error)"
    else
      echo "(not available on this system)"
    fi
  } | redact > "$WORK/$NAME/$file"
}

capture 01-os.txt          cat /etc/os-release
capture 02-uname.txt       uname -a
capture 03-uptime.txt      uptime
capture 04-disk.txt        df -h
capture 05-memory.txt      free -h
capture 06-ip-addr.txt     ip addr
capture 07-routes.txt      ip route
capture 08-dns.txt         cat /etc/resolv.conf
capture 09-processes.txt   ps aux --sort=-%cpu
capture 10-failed-services.txt systemctl --failed --no-pager

if command -v journalctl >/dev/null 2>&1; then
  capture 11-system-log.txt journalctl -n "$LINES" --no-pager
elif [[ -r /var/log/syslog ]]; then
  capture 11-system-log.txt tail -n "$LINES" /var/log/syslog
elif [[ -r /var/log/messages ]]; then
  capture 11-system-log.txt tail -n "$LINES" /var/log/messages
else
  echo "(no readable system log found)" > "$WORK/$NAME/11-system-log.txt"
fi

{
  echo "Support bundle for $HOST"
  echo "Created: $(date '+%Y-%m-%d %H:%M:%S %Z') by $(id -un)"
  echo "Files:"
  (cd "$WORK/$NAME" && ls -1)
} > "$WORK/$NAME/00-README.txt"

ARCHIVE="$OUT_DIR/$NAME.tar.gz"
tar -czf "$ARCHIVE" -C "$WORK" "$NAME"
echo "Support bundle created: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"
echo "Review it before sending — secrets are masked, but hostnames and IPs are included."
