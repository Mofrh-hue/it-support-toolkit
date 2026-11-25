<#
.SYNOPSIS
    Summarises recent errors from the Windows event logs.

.DESCRIPTION
    Reads Critical and Error events from the System and Application logs for
    the last few hours and groups them by source, so you can see at a glance
    which component keeps failing - instead of scrolling through Event Viewer.

.PARAMETER Hours
    How far back to look. Default 24.

.PARAMETER Top
    How many sources to show. Default 10.

.EXAMPLE
    .\Get-RecentErrors.ps1 -Hours 4

.EXAMPLE
    .\Get-RecentErrors.ps1 -Hours 72 -Top 5 | Export-Csv errors.csv -NoTypeInformation
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 720)]
    [int] $Hours = 24,

    [ValidateRange(1, 100)]
    [int] $Top = 10
)

function Get-ErrorEvent {
    <# Critical (1) and Error (2) events from System and Application since StartTime. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [datetime] $StartTime)
    $filter = @{
        LogName   = 'System', 'Application'
        Level     = 1, 2
        StartTime = $StartTime
    }
    try {
        Get-WinEvent -FilterHashtable $filter -ErrorAction Stop
    }
    catch [System.Exception] {
        # Get-WinEvent throws when nothing matches; treat that as "no errors"
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { return @() }
        throw
    }
}

function ConvertTo-ErrorSummary {
    <# Groups events by log and source, most frequent first. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $EventRecord,
        [int] $Top = 10
    )
    if ($EventRecord.Count -eq 0) { return @() }

    $EventRecord |
        Group-Object -Property LogName, ProviderName |
        Sort-Object -Property Count -Descending |
        Select-Object -First $Top |
        ForEach-Object {
            $latest = $_.Group | Sort-Object -Property TimeCreated -Descending | Select-Object -First 1
            $message = ($latest.Message -split "`r?`n")[0]
            if ($message.Length -gt 100) { $message = $message.Substring(0, 97) + '...' }
            [pscustomobject]@{
                Count         = $_.Count
                Log           = $latest.LogName
                Source        = $latest.ProviderName
                LastEventId   = $latest.Id
                LastSeen      = $latest.TimeCreated
                LatestMessage = $message
            }
        }
}

if ($MyInvocation.InvocationName -ne '.') {
    $since = (Get-Date).AddHours(-$Hours)
    $events = @(Get-ErrorEvent -StartTime $since)
    if ($events.Count -eq 0) {
        Write-Output "No critical or error events in the last $Hours hour(s)."
        exit 0
    }
    Write-Output "$($events.Count) error event(s) in the last $Hours hour(s), top sources:"
    ConvertTo-ErrorSummary -EventRecord $events -Top $Top
}
