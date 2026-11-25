#!/usr/bin/env bats
# Tests for the Bash scripts. Real system data is replaced with fixture files,
# so the WARNING / CRITICAL paths can be tested on any machine.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  FIX="$BATS_TEST_DIRNAME/fixtures"
  export DF_OUTPUT_FILE="$FIX/df-healthy.txt"
  export MEMINFO_FILE="$FIX/meminfo-healthy.txt"
  export LOADAVG_FILE="$FIX/loadavg-low.txt"
  export UPTIME_FILE="$FIX/uptime-1d.txt"
  export CPU_COUNT=4
}

# ---------- system-health.sh ----------

@test "system-health: healthy machine reports OK and exits 0" {
  run "$ROOT/bash/system-health.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK      ] Disk /: 43% used"* ]]
  [[ "$output" == *"[OK      ] Memory: 30% used of 15.5 GB"* ]]
  [[ "$output" == *"Overall: OK"* ]]
}

@test "system-health: a 95% full disk is CRITICAL and exits 2" {
  export DF_OUTPUT_FILE="$FIX/df-full.txt"
  run "$ROOT/bash/system-health.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"[CRITICAL] Disk /: 95% used"* ]]
  [[ "$output" == *"[WARNING ] Disk /data: 84% used"* ]]
  [[ "$output" == *"Overall: CRITICAL"* ]]
}

@test "system-health: high memory use is CRITICAL" {
  export MEMINFO_FILE="$FIX/meminfo-high.txt"
  run "$ROOT/bash/system-health.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"[CRITICAL] Memory: 95% used"* ]]
}

@test "system-health: CPU load is measured per CPU" {
  export LOADAVG_FILE="$FIX/loadavg-high.txt"
  run "$ROOT/bash/system-health.sh"
  # 7.80 load on 4 CPUs = 195% of capacity
  [[ "$output" == *"[CRITICAL] CPU load: 7.80 (1 min) on 4 CPU(s) = 195% of capacity"* ]]
}

@test "system-health: 100 days without a reboot is a WARNING" {
  export UPTIME_FILE="$FIX/uptime-100d.txt"
  run "$ROOT/bash/system-health.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[WARNING ] Uptime: 100d 0h"* ]]
}

@test "system-health: custom thresholds are respected" {
  run "$ROOT/bash/system-health.sh" -w 30 -c 40
  [ "$status" -eq 2 ]
  [[ "$output" == *"[CRITICAL] Disk /: 43% used"* ]]
  [[ "$output" == *"[WARNING ] Disk /data: 32% used"* ]]
}

@test "system-health: quiet mode hides OK lines" {
  export DF_OUTPUT_FILE="$FIX/df-full.txt"
  run "$ROOT/bash/system-health.sh" -q
  [[ "$output" != *"[OK      ]"* ]]
  [[ "$output" == *"[CRITICAL] Disk /"* ]]
}

@test "system-health: rejects warning threshold above critical" {
  run "$ROOT/bash/system-health.sh" -w 95 -c 90
  [ "$status" -eq 3 ]
  [[ "$output" == *"WARN < CRIT"* ]]
}

@test "system-health: runs against the real machine" {
  unset DF_OUTPUT_FILE MEMINFO_FILE LOADAVG_FILE UPTIME_FILE CPU_COUNT
  run "$ROOT/bash/system-health.sh"
  [ "$status" -le 2 ]
  [[ "$output" == *"Overall:"* ]]
}

# ---------- network-check.sh ----------

@test "network-check: an open local port is reachable" {
  python3 -m http.server 8765 --bind 127.0.0.1 >/dev/null 2>&1 &
  server=$!
  sleep 1
  run "$ROOT/bash/network-check.sh" -p 8765 127.0.0.1
  kill "$server"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ OK ] 127.0.0.1"*"port 8765 reachable"* ]]
}

@test "network-check: a closed port fails with exit 2" {
  run "$ROOT/bash/network-check.sh" -t 1 127.0.0.1:1
  [ "$status" -eq 2 ]
  [[ "$output" == *"[FAIL] 127.0.0.1"*"port 1 not reachable"* ]]
}

@test "network-check: a name that does not resolve is reported as a DNS failure" {
  run "$ROOT/bash/network-check.sh" no-such-host.invalid
  [ "$status" -eq 2 ]
  [[ "$output" == *"DNS lookup failed"* ]]
}

@test "network-check: one good and one bad target exits 1" {
  python3 -m http.server 8766 --bind 127.0.0.1 >/dev/null 2>&1 &
  server=$!
  sleep 1
  run "$ROOT/bash/network-check.sh" -t 1 127.0.0.1:8766 no-such-host.invalid
  kill "$server"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Summary: 1 reachable, 1 failed"* ]]
}

@test "network-check: rejects an invalid port" {
  run "$ROOT/bash/network-check.sh" -p 70000 localhost
  [ "$status" -eq 3 ]
}

# ---------- service-check.sh ----------

fake_systemctl() {
  export SYSTEMCTL="$FIX/fake-systemctl.sh"
  export FAKE_STATE_DIR="$BATS_TEST_TMPDIR"
  export RESTART_WAIT=0
}

@test "service-check: running services are OK" {
  fake_systemctl
  export FAKE_ACTIVE="nginx ssh"
  run "$ROOT/bash/service-check.sh" nginx ssh
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ OK ] nginx"* ]]
}

@test "service-check: a stopped service is reported and exits 2" {
  fake_systemctl
  export FAKE_ACTIVE="ssh"
  run "$ROOT/bash/service-check.sh" ssh nginx
  [ "$status" -eq 2 ]
  [[ "$output" == *"[DOWN] nginx"*"inactive"* ]]
}

@test "service-check: -r restarts a stopped service and exits 1" {
  fake_systemctl
  export FAKE_ACTIVE="" FAKE_FIXABLE="nginx"
  run "$ROOT/bash/service-check.sh" -r nginx
  [ "$status" -eq 1 ]
  [[ "$output" == *"[FIXD] nginx"* ]]
}

@test "service-check: a service that fails to restart points to its logs" {
  fake_systemctl
  export FAKE_ACTIVE="" FAKE_FIXABLE=""
  run "$ROOT/bash/service-check.sh" -r postgresql
  [ "$status" -eq 2 ]
  [[ "$output" == *"journalctl -u postgresql"* ]]
}

@test "service-check: no service names is a usage error" {
  run "$ROOT/bash/service-check.sh"
  [ "$status" -eq 3 ]
}

# ---------- collect-logs.sh ----------

@test "collect-logs: creates a bundle with the expected files" {
  run "$ROOT/bash/collect-logs.sh" -o "$BATS_TEST_TMPDIR" -n 20
  [ "$status" -eq 0 ]
  archive=$(ls "$BATS_TEST_TMPDIR"/support-bundle-*.tar.gz)
  run tar -tzf "$archive"
  [[ "$output" == *"00-README.txt"* ]]
  [[ "$output" == *"04-disk.txt"* ]]
  [[ "$output" == *"11-system-log.txt"* ]]
}

@test "collect-logs: masks passwords and tokens" {
  # Put a fake secret into the environment of a captured command via a fake 'uptime'
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "db_password=Hunter2 token: abc123 user=ahmed"\n' > "$BATS_TEST_TMPDIR/bin/uptime"
  chmod +x "$BATS_TEST_TMPDIR/bin/uptime"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run "$ROOT/bash/collect-logs.sh" -o "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  archive=$(ls "$BATS_TEST_TMPDIR"/support-bundle-*.tar.gz)
  content=$(tar -xzOf "$archive" --wildcards '*/03-uptime.txt')
  [[ "$content" != *"Hunter2"* ]]
  [[ "$content" != *"abc123"* ]]
  [[ "$content" == *"user=ahmed"* ]]
}
