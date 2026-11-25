<#
.SYNOPSIS
    Quick health check for a Windows PC or server.

.DESCRIPTION
    Checks free space on every fixed disk, memory use, uptime and whether a
    reboot is pending, and prints one line per check with OK, WARNING or
    CRITICAL. Use it as the first step on "my PC is slow" or "the server is
    acting up" tickets.

    Exit codes: 0 = OK, 1 = WARNING, 2 = CRITICAL

.PARAMETER WarnPercent
    Usage percentage that counts as WARNING. Default 80.

.PARAMETER CritPercent
    Usage percentage that counts as CRITICAL. Default 90.

.EXAMPLE
    .\Get-SystemHealth.ps1

.EXAMPLE
    .\Get-SystemHealth.ps1 -WarnPercent 70 -CritPercent 85
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 99)]
    [int] $WarnPercent = 80,

    [ValidateRange(2, 100)]
    [int] $CritPercent = 90
)

function Get-UsageStatus {
    <# Returns OK, WARNING or CRITICAL for a usage percentage. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [double] $Percent,
        [int] $Warn = 80,
        [int] $Crit = 90
    )
    if ($Percent -ge $Crit) { return 'CRITICAL' }
    if ($Percent -ge $Warn) { return 'WARNING' }
    return 'OK'
}

function Get-DiskHealth {
    <# One result per fixed disk (DriveType 3). #>
    [CmdletBinding()]
    param([int] $Warn = 80, [int] $Crit = 90)

    Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' | ForEach-Object {
        if (-not $_.Size) { return }
        $usedPct = [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1)
        $freeGb = [math]::Round($_.FreeSpace / 1GB, 1)
        [pscustomobject]@{
            Check   = "Disk $($_.DeviceID)"
            Status  = Get-UsageStatus -Percent $usedPct -Warn $Warn -Crit $Crit
            Details = "$usedPct% used, $freeGb GB free"
        }
    }
}

function Get-MemoryHealth {
    [CmdletBinding()]
    param([int] $Warn = 80, [int] $Crit = 90)

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    # Both values are reported in KB
    $usedPct = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)
    $totalGb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    [pscustomobject]@{
        Check   = 'Memory'
        Status  = Get-UsageStatus -Percent $usedPct -Warn $Warn -Crit $Crit
        Details = "$usedPct% used of $totalGb GB"
    }
}

function Get-UptimeHealth {
    [CmdletBinding()]
    param([int] $MaxDays = 30)

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $uptime = (Get-Date) - $os.LastBootUpTime
    $text = '{0}d {1}h' -f $uptime.Days, $uptime.Hours
    if ($uptime.TotalDays -ge $MaxDays) {
        [pscustomobject]@{ Check = 'Uptime'; Status = 'WARNING'; Details = "$text - no restart in $MaxDays+ days, ask the user to restart" }
    }
    else {
        [pscustomobject]@{ Check = 'Uptime'; Status = 'OK'; Details = $text }
    }
}

function Test-PendingReboot {
    <# True if Windows Update or a software install is waiting for a restart. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    foreach ($key in $keys) {
        if (Test-Path -Path $key) { return $true }
    }
    return $false
}

function Get-PendingRebootHealth {
    [CmdletBinding()]
    param()
    if (Test-PendingReboot) {
        [pscustomobject]@{ Check = 'Pending reboot'; Status = 'WARNING'; Details = 'Updates are waiting for a restart' }
    }
    else {
        [pscustomobject]@{ Check = 'Pending reboot'; Status = 'OK'; Details = 'None' }
    }
}

function Get-OverallExitCode {
    <# 0 if every result is OK, 1 if any WARNING, 2 if any CRITICAL. #>
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory)] [object[]] $Results)
    if ($Results.Status -contains 'CRITICAL') { return 2 }
    if ($Results.Status -contains 'WARNING') { return 1 }
    return 0
}

# Run only when called as a script, not when dot-sourced by the tests
if ($MyInvocation.InvocationName -ne '.') {
    if ($WarnPercent -ge $CritPercent) {
        Write-Error "WarnPercent ($WarnPercent) must be lower than CritPercent ($CritPercent)."
        exit 3
    }

    Write-Output "System health for $env:COMPUTERNAME - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $results = @(
        Get-DiskHealth -Warn $WarnPercent -Crit $CritPercent
        Get-MemoryHealth -Warn $WarnPercent -Crit $CritPercent
        Get-UptimeHealth
        Get-PendingRebootHealth
    )
    $results | Format-Table -AutoSize | Out-String | Write-Output

    $code = Get-OverallExitCode -Results $results
    Write-Output ("Overall: {0}" -f @('OK', 'WARNING', 'CRITICAL')[$code])
    exit $code
}
