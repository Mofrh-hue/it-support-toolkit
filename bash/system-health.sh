#!/usr/bin/env bash
# system-health.sh — quick health check for a Linux server or workstation.
#
# Checks disk usage, memory usage, CPU load and uptime, and prints one line
# per check with a status of OK, WARNING or CRITICAL.
#
# Exit codes (monitoring-style): 0 = OK, 1 = WARNING, 2 = CRITICAL
#
# Usage: system-health.sh [-w WARN%] [-c CRIT%] [-q] [-h]

set -euo pipefail

WARN=80
CRIT=90
QUIET=0

# Data sources can be overridden (used by the tests to simulate a full disk etc.)
MEMINFO_FILE="${MEMINFO_FILE:-/proc/meminfo}"
LOADAVG_FILE="${LOADAVG_FILE:-/proc/loadavg}"
UPTIME_FILE="${UPTIME_FILE:-/proc/uptime}"
DF_OUTPUT_FILE="${DF_OUTPUT_FILE:-}"
CPU_COUNT="${CPU_COUNT:-}"

usage() {
  cat <<'EOF'
Usage: system-health.sh [-w WARN%] [-c CRIT%] [-q] [-h]

  -w N   warning threshold in percent (default 80)
  -c N   critical threshold in percent (default 90)
  -q     quiet: only print checks that are not OK
  -h     show this help

Exit codes: 0 OK, 1 WARNING, 2 CRITICAL
EOF
}

while getopts ":w:c:qh" opt; do
  case "$opt" in
    w) WARN="$OPTARG" ;;
    c) CRIT="$OPTARG" ;;
    q) QUIET=1 ;;
    h) usage; exit 0 ;;
    :) echo "Option -$OPTARG needs a value" >&2; usage >&2; exit 3 ;;
    *) echo "Unknown option: -$OPTARG" >&2; usage >&2; exit 3 ;;
  esac
done

if ! [[ "$WARN" =~ ^[0-9]+$ && "$CRIT" =~ ^[0-9]+$ ]] || (( WARN >= CRIT || CRIT > 100 )); then
  echo "Thresholds must be whole numbers with WARN < CRIT <= 100 (got -w $WARN -c $CRIT)" >&2
  exit 3
fi

OVERALL=0

# status_for PERCENT -> prints OK / WARNING / CRITICAL
status_for() {
  local pct=$1
  if (( pct >= CRIT )); then echo CRITICAL
  elif (( pct >= WARN )); then echo WARNING
  else echo OK
  fi
}

# report STATUS MESSAGE — prints the line and raises the overall exit code
report() {
  local status=$1 msg=$2 code=0
  case "$status" in
    WARNING) code=1 ;;
    CRITICAL) code=2 ;;
  esac
  (( code > OVERALL )) && OVERALL=$code
  if (( QUIET == 0 || code > 0 )); then
    printf '[%-8s] %s\n' "$status" "$msg"
  fi
}

check_disks() {
  local df_out
  if [[ -n "$DF_OUTPUT_FILE" ]]; then
    df_out=$(cat "$DF_OUTPUT_FILE")
  else
    df_out=$(df -P -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null || df -P)
  fi
  # Columns: Filesystem 1024-blocks Used Available Capacity Mounted-on
  while read -r _fs _size _used avail cap mount; do
    [[ "$cap" =~ ^([0-9]+)%$ ]] || continue
    local pct=${BASH_REMATCH[1]}
    local free_gb
    free_gb=$(awk -v kb="$avail" 'BEGIN { printf "%.1f", kb / 1048576 }')
    report "$(status_for "$pct")" "Disk $mount: ${pct}% used, ${free_gb} GB free"
  done <<< "$(tail -n +2 <<< "$df_out")"
}

check_memory() {
  local total avail
  total=$(awk '/^MemTotal:/ { print $2 }' "$MEMINFO_FILE")
  avail=$(awk '/^MemAvailable:/ { print $2 }' "$MEMINFO_FILE")
  if [[ -z "$total" || -z "$avail" || "$total" -eq 0 ]]; then
    report WARNING "Memory: could not read $MEMINFO_FILE"
    return
  fi
  local used_pct=$(( (total - avail) * 100 / total ))
  local total_gb
  total_gb=$(awk -v kb="$total" 'BEGIN { printf "%.1f", kb / 1048576 }')
  report "$(status_for "$used_pct")" "Memory: ${used_pct}% used of ${total_gb} GB"
}

check_load() {
  local cpus load1
  cpus=${CPU_COUNT:-$(nproc 2>/dev/null || echo 1)}
  read -r load1 _ < "$LOADAVG_FILE"
  # Load per CPU as a percentage: 1.0 load on 1 CPU = 100%
  local pct
  pct=$(awk -v l="$load1" -v c="$cpus" 'BEGIN { printf "%d", (l / c) * 100 }')
  report "$(status_for "$pct")" "CPU load: $load1 (1 min) on $cpus CPU(s) = ${pct}% of capacity"
}

check_uptime() {
  local secs days hours
  read -r secs _ < "$UPTIME_FILE"
  secs=${secs%.*}
  days=$(( secs / 86400 ))
  hours=$(( (secs % 86400) / 3600 ))
  if (( days >= 90 )); then
    report WARNING "Uptime: ${days}d ${hours}h — no reboot in 90+ days, check for pending updates"
  else
    report OK "Uptime: ${days}d ${hours}h"
  fi
}

echo "System health for $(hostname) — $(date '+%Y-%m-%d %H:%M')  (warn ${WARN}%, crit ${CRIT}%)"
check_disks
check_memory
check_load
check_uptime

case $OVERALL in
  0) echo "Overall: OK" ;;
  1) echo "Overall: WARNING" ;;
  2) echo "Overall: CRITICAL" ;;
esac
exit "$OVERALL"
