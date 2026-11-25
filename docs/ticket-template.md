# Ticket Note Template

Copy this into the ticket when you escalate or close it. A complete note means the next person can pick the ticket up without contacting the user again.

```text
SUMMARY
One sentence: what is wrong, for whom.
e.g. "Outlook crashes on start for one user since this morning's update."

USER / DEVICE
User:            name, team, contact
Device:          hostname, OS and version
Scope:           one user / several users / everyone

WHEN IT STARTED
Date and time, and anything that changed just before (update, move, new app).

ERROR
Exact message, error code or screenshot.

STEPS TAKEN
1. Ran Get-SystemHealth.ps1: disk C: 96% used (CRITICAL), others OK.
2. Ran Clear-TempFiles.ps1: freed 3.2 GB. Disk now 88%.
3. Restarted the PC. Problem still there.
4. Ran Get-RecentErrors.ps1 -Hours 24: 14x "Application Error" for outlook.exe.

RESULT
Fixed / Not fixed / Workaround given (describe the workaround).

NEXT STEP / ESCALATED TO
Team, and what you need from them.

ATTACHMENTS
Script output, support bundle, screenshots.
```

## Writing tips

- **Facts, not guesses.** Write "Disk was 96% full", not "Disk probably full".
- **Record what didn't work.** Steps that failed save the next team the most time.
- **Keep the user's words for the symptom**, and add the technical detail next to them.
- **Don't paste passwords or personal data** into the ticket.
