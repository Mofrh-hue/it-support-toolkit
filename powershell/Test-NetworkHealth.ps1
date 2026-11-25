<#
.SYNOPSIS
    First-line check for "the internet / the app is down" tickets.

.DESCRIPTION
    For each target, checks whether the name resolves (DNS) and whether a TCP
    connection to the port can be opened. Telling these apart shows whether
    the problem is DNS, a firewall or proxy, or the remote service itself.

    Exit codes: 0 = all reachable, 1 = some failed, 2 = all failed

.PARAMETER Target
    Host names, optionally with a port (app.example.com:8443).
    Default: google.com, github.com, microsoft.com

.PARAMETER Port
    TCP port used when a target has no port of its own. Default 443.

.PARAMETER TimeoutMs
    Connection timeout per target in milliseconds. Default 3000.

.EXAMPLE
    .\Test-NetworkHealth.ps1 -Target intranet.local, mail.example.com -Port 443
#>
[CmdletBinding()]
param(
    [string[]] $Target = @('google.com', 'github.com', 'microsoft.com'),

    [ValidateRange(1, 65535)]
    [int] $Port = 443,

    [ValidateRange(100, 60000)]
    [int] $TimeoutMs = 3000
)

function Split-Target {
    <# Splits "host:port" into a host and a port; uses DefaultPort when there is none. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Value,
        [int] $DefaultPort = 443
    )
    if ($Value -match '^(?<host>[^:]+):(?<port>\d{1,5})$') {
        return [pscustomobject]@{ Host = $Matches.host; Port = [int] $Matches.port }
    }
    return [pscustomobject]@{ Host = $Value; Port = $DefaultPort }
}

function Resolve-HostAddress {
    <# Returns the first IP address for a name, or $null if DNS fails. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $HostName)
    try {
        $addresses = [System.Net.Dns]::GetHostAddresses($HostName)
        $ipv4 = $addresses | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
        if ($ipv4) { return $ipv4.IPAddressToString }
        return ($addresses | Select-Object -First 1).IPAddressToString
    }
    catch {
        return $null
    }
}

function Test-TcpPort {
    <# True if a TCP connection to HostName:Port opens within TimeoutMs. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $HostName,
        [Parameter(Mandatory)] [int] $Port,
        [int] $TimeoutMs = 3000
    )
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $task = $client.ConnectAsync($HostName, $Port)
        $completed = $task.Wait($TimeoutMs)
        return ($completed -and $client.Connected)
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

function Test-Target {
    <# Runs the DNS and TCP checks for one target and returns a result object. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Value,
        [int] $DefaultPort = 443,
        [int] $TimeoutMs = 3000
    )
    $t = Split-Target -Value $Value -DefaultPort $DefaultPort
    $ip = Resolve-HostAddress -HostName $t.Host
    if (-not $ip) {
        return [pscustomobject]@{ Target = $t.Host; Port = $t.Port; Address = ''; Status = 'FAIL'; Details = 'DNS lookup failed - check DNS settings' }
    }
    if (Test-TcpPort -HostName $t.Host -Port $t.Port -TimeoutMs $TimeoutMs) {
        return [pscustomobject]@{ Target = $t.Host; Port = $t.Port; Address = $ip; Status = 'OK'; Details = 'Reachable' }
    }
    return [pscustomobject]@{ Target = $t.Host; Port = $t.Port; Address = $ip; Status = 'FAIL'; Details = 'Port not reachable - firewall, proxy or service down' }
}

function Get-NetworkExitCode {
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory)] [object[]] $Results)
    $failed = @($Results | Where-Object Status -ne 'OK').Count
    if ($failed -eq 0) { return 0 }
    if ($failed -eq $Results.Count) { return 2 }
    return 1
}

if ($MyInvocation.InvocationName -ne '.') {
    Write-Output "Network check - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $results = foreach ($item in $Target) {
        Test-Target -Value $item -DefaultPort $Port -TimeoutMs $TimeoutMs
    }
    $results | Format-Table -AutoSize | Out-String | Write-Output
    $ok = @($results | Where-Object Status -eq 'OK').Count
    Write-Output "Summary: $ok reachable, $($results.Count - $ok) failed"
    exit (Get-NetworkExitCode -Results $results)
}
