# IT Support Toolkit

[![CI](https://github.com/Mofrh-hue/it-support-toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/Mofrh-hue/it-support-toolkit/actions/workflows/ci.yml)

PowerShell and Bash scripts for the first checks on common support tickets ("the internet is down", "my PC is slow", "the service stopped"), plus a troubleshooting runbook and a ticket note template.

Each script prints a short, readable result and returns a **monitoring-style exit code**, so it can be used by hand on a ticket or run by a scheduler or monitoring tool. Every script is covered by automated tests that run on **Windows and Linux** in GitHub Actions.

> Portfolio project: scripts I wrote to automate the first steps I take on a support ticket. They only read system information, apart from the two clearly marked actions: deleting old temp files and restarting a service.

## What's inside

| Ticket | Windows (PowerShell) | Linux (Bash) |
|---|---|---|
| "My PC / the server is slow" | `Get-SystemHealth.ps1`: disk, memory, uptime, pending reboot | `system-health.sh`: disk, memory, CPU load, uptime |
| "The internet / an app is down" | `Test-NetworkHealth.ps1`: DNS and TCP port check per target | `network-check.sh`: gateway, DNS and TCP port check |
| "An app keeps crashing" | `Get-RecentErrors.ps1`: groups recent event-log errors by source | - |
| "The disk is full" | `Clear-TempFiles.ps1`: deletes old temp files, supports `-WhatIf` | - |
| "A service stopped" | - | `service-check.sh`: checks systemd services, `-r` restarts them |
| "Escalate to second line / vendor" | - | `collect-logs.sh`: support bundle (.tar.gz) with secrets masked |

Documents:

- **[Troubleshooting runbook](docs/troubleshooting-runbook.md)**: step-by-step handling of the common tickets above, and when to escalate.
- **[Ticket note template](docs/ticket-template.md)**: what a complete escalation note contains.

## Example output

```text
$ ./bash/system-health.sh
System health for web-01 — 2026-11-25 15:07  (warn 80%, crit 90%)
[CRITICAL] Disk /: 95% used, 4.9 GB free
[WARNING ] Disk /data: 84% used, 81.9 GB free
[OK      ] Memory: 8% used of 7.8 GB
[OK      ] CPU load: 0.72 (1 min) on 2 CPU(s) = 36% of capacity
[OK      ] Uptime: 0d 0h
Overall: CRITICAL
```

```text
$ ./bash/network-check.sh -t 2 127.0.0.1:8080 intranet.invalid 127.0.0.1:5432
Default gateway: 192.0.2.1

[ OK ] 127.0.0.1                    127.0.0.1 port 8080 reachable
[FAIL] intranet.invalid             DNS lookup failed — check DNS server settings
[FAIL] 127.0.0.1                    127.0.0.1 port 5432 not reachable within 2s — firewall, proxy or service down

Summary: 1 reachable, 2 failed
```

Telling **"DNS failed"** apart from **"port not reachable"** is what makes this useful on a ticket. The first is a DNS problem on the user's side; the second is a firewall, proxy or a service that is down.

## Usage

**Windows** (PowerShell 5.1 or 7+):

```powershell
.\powershell\Get-SystemHealth.ps1 -WarnPercent 75 -CritPercent 90
.\powershell\Test-NetworkHealth.ps1 -Target intranet.local, mail.example.com:993
.\powershell\Get-RecentErrors.ps1 -Hours 24 -Top 5
.\powershell\Clear-TempFiles.ps1 -OlderThanDays 14 -WhatIf   # preview first
```

If scripts are blocked, allow them for the current window only: `Set-ExecutionPolicy -Scope Process Bypass`.

**Linux** (after cloning, make the scripts executable once: `chmod +x bash/*.sh`):

```bash
./bash/system-health.sh -w 75 -c 90
./bash/network-check.sh -p 443 app.example.com db.internal:5432
./bash/service-check.sh nginx postgresql        # check only
sudo ./bash/service-check.sh -r nginx           # check and restart if down
./bash/collect-logs.sh -o /tmp -n 1000          # support bundle
```

Every script has built-in help: `Get-Help .\powershell\Get-SystemHealth.ps1 -Full` or `./bash/system-health.sh -h`.

### Exit codes

| Code | Health and network scripts | service-check.sh |
|---|---|---|
| 0 | Everything OK | All services running |
| 1 | WARNING, or some targets failed | Restarted and now running |
| 2 | CRITICAL, or all targets failed | Still down |
| 3 | Wrong arguments | Wrong arguments, or no systemd |

## Testing

| Suite | Tool | Tests | Runs on |
|---|---|---|---|
| Bash scripts | [Bats](https://github.com/bats-core/bats-core) + ShellCheck | 21 | Ubuntu |
| PowerShell scripts | [Pester 5](https://pester.dev) + PSScriptAnalyzer | 41 | Windows and Ubuntu |

How the tests are built:

- **Fake system data instead of a broken machine.** The Bash scripts read disk, memory and load from files that tests can replace, so a 95% full disk or a 100-day uptime can be tested on any machine.
- **Mocks for Windows commands.** Pester mocks `Get-CimInstance`, `Get-WinEvent` and `Test-Path`, so the WARNING and CRITICAL paths are tested without changing the real system.
- **Real network checks where it's safe.** The port tests open a real listener on `127.0.0.1` and check both an open and a closed port.
- **A fake `systemctl`** checks the restart logic, including a service that refuses to start.
- **Secret masking is tested.** A test feeds a fake password and token into the log collector and checks that neither appears in the bundle.

Run the tests locally:

```bash
npm install && npx bats tests/bash          # Bash
shellcheck bash/*.sh
```

```powershell
Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser
Invoke-Pester ./tests/powershell                 # PowerShell
```

## Project structure

```
powershell/                 Windows scripts
bash/                       Linux scripts
docs/                       Runbook and ticket template
tests/bash/                 Bats tests and fixtures (fake df, meminfo, systemctl...)
tests/powershell/           Pester tests
.github/workflows/ci.yml    Lint + tests on Ubuntu and Windows
```

---

Author: **Ahmed Mofrh Fahmy**, QA Test Lead · [GitHub profile](https://github.com/Mofrh-hue)
