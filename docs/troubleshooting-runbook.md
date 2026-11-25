# First-Line Troubleshooting Runbook

How I work through the most common support tickets, and which script in this repo does each check. The goal of first-line support is to **fix it or hand it over with the evidence already collected**, so the next team never has to ask "what have you tried?"

## Before you start, on every ticket

1. **Confirm who and what.** User, device name, exact error text or a screenshot, and when it started.
2. **Ask "what changed?"** A new update, a password change, a move to another office, a new app.
3. **Check scope.** Is it one user, one team or everyone? If many users report the same thing, treat it as an incident and tell the team lead before working on single tickets.
4. **Write down every step in the ticket as you go**, including the ones that didn't help.

---

## "The internet / the app is down"

| Step | Windows | Linux |
|---|---|---|
| 1. Is the device on the network at all? | `ipconfig` and look for an IP address and default gateway | `ip addr`, `ip route` |
| 2. Is DNS working, and can we reach the service? | `.\Test-NetworkHealth.ps1 -Target app.example.com` | `./network-check.sh app.example.com` |

How to read the result:

- **No default gateway**: a local problem. Check the cable, Wi-Fi or VPN, then run `ipconfig /renew`.
- **DNS lookup failed for everything**: wrong DNS server, or the VPN dropped. Run `ipconfig /flushdns` and check the DNS settings.
- **DNS works but the port is not reachable**: firewall, proxy or the service itself is down. Test from a second machine. If that fails too, escalate to the network team or the app owner.
- **Some sites work and one doesn't**: the problem is on the service side. Check the status page, then escalate.

## "My PC is slow"

1. Run `.\Get-SystemHealth.ps1`.
2. **Disk CRITICAL**: run `.\Clear-TempFiles.ps1 -WhatIf` to see what would be removed, then run it without `-WhatIf`. Also empty the Recycle Bin and check the Downloads folder with the user.
3. **Memory CRITICAL**: open Task Manager and sort by memory. Browsers with many tabs are the usual cause.
4. **Uptime WARNING or pending reboot**: ask the user to restart. This fixes a large share of slowness tickets.
5. Still slow after all of this: run `.\Get-RecentErrors.ps1 -Hours 72` and look for disk or hardware sources, such as `Disk`, `Ntfs` or `WHEA-Logger`. Escalate to hardware support with that output.

## "An application keeps crashing"

1. Run `.\Get-RecentErrors.ps1 -Hours 24`.
2. Look for `Application Error` or `Application Hang` entries that name the program.
3. Common fixes, in order:
   - Install updates for the app.
   - Use the app's repair option in *Apps & features*.
   - Clear the app's cache or profile folder.
   - Reinstall.
4. Escalate to the app owner with the event summary and the app version.

## "A service on the server is down" (Linux)

1. Run `./service-check.sh nginx` (use the real service name).
2. If it is down, look at the reason first with `journalctl -u nginx -n 50`. Then try `sudo ./service-check.sh -r nginx`.
3. If it will not start, run `./system-health.sh`, because a full disk is a very common cause. Then run `./collect-logs.sh` and attach the bundle to the escalation.

## "User is locked out / forgot password"

1. **Verify the user's identity first**, using your organisation's process. Never reset a password based only on an email or a phone call.
2. Check whether the account is locked, disabled or expired. These need different fixes.
3. Unlock or reset it. Set "must change password at next sign-in".
4. If the account locks again quickly, an old password is probably saved on another device, such as a phone mail app or a mapped drive. Ask the user to update it there.

---

## When to escalate

Escalate, with your notes and the script output attached, when:

- the fix needs admin rights or access you don't have
- more than one user is affected
- the same problem comes back after it was fixed
- hardware may be failing (disk errors, overheating, physical damage)
- it's a possible security incident (phishing, unknown software, unusual sign-ins). **Escalate these straight away and don't try to fix them yourself.**

Use the [ticket note template](ticket-template.md) so every escalation has the same information.
