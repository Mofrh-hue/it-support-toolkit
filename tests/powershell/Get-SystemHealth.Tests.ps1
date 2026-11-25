BeforeAll {
    # Windows-only commands are stubbed when missing, so the tests also run
    # with PowerShell on Linux/macOS. On Windows the real commands are mocked.
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function global:Get-CimInstance { param($ClassName, $Filter) }
    }
    . "$PSScriptRoot/../../powershell/Get-SystemHealth.ps1"
}

Describe 'Get-UsageStatus' {
    It 'returns <Expected> for <Percent>%' -ForEach @(
        @{ Percent = 10; Expected = 'OK' }
        @{ Percent = 79.9; Expected = 'OK' }
        @{ Percent = 80; Expected = 'WARNING' }
        @{ Percent = 89.9; Expected = 'WARNING' }
        @{ Percent = 90; Expected = 'CRITICAL' }
        @{ Percent = 100; Expected = 'CRITICAL' }
    ) {
        Get-UsageStatus -Percent $Percent | Should -Be $Expected
    }

    It 'uses custom thresholds' {
        Get-UsageStatus -Percent 60 -Warn 50 -Crit 70 | Should -Be 'WARNING'
    }
}

Describe 'Get-DiskHealth' {
    It 'flags a nearly full disk as CRITICAL and a healthy one as OK' {
        Mock Get-CimInstance {
            [pscustomobject]@{ DeviceID = 'C:'; Size = 100GB; FreeSpace = 5GB }
            [pscustomobject]@{ DeviceID = 'D:'; Size = 500GB; FreeSpace = 400GB }
        }

        $result = @(Get-DiskHealth)

        $result | Should -HaveCount 2
        $result[0].Check | Should -Be 'Disk C:'
        $result[0].Status | Should -Be 'CRITICAL'
        $result[0].Details | Should -Be '95% used, 5 GB free'
        $result[1].Status | Should -Be 'OK'
    }

    It 'skips drives that report no size' {
        Mock Get-CimInstance { [pscustomobject]@{ DeviceID = 'E:'; Size = $null; FreeSpace = $null } }
        @(Get-DiskHealth) | Should -HaveCount 0
    }
}

Describe 'Get-MemoryHealth' {
    It 'calculates used memory from total and free' {
        # 16 GB total, 1.6 GB free -> 90% used
        Mock Get-CimInstance { [pscustomobject]@{ TotalVisibleMemorySize = 16777216; FreePhysicalMemory = 1677722 } }

        $result = Get-MemoryHealth

        $result.Status | Should -Be 'CRITICAL'
        $result.Details | Should -Be '90% used of 16 GB'
    }
}

Describe 'Get-UptimeHealth' {
    It 'warns when the machine has not restarted for a long time' {
        Mock Get-CimInstance { [pscustomobject]@{ LastBootUpTime = (Get-Date).AddDays(-45) } }
        (Get-UptimeHealth).Status | Should -Be 'WARNING'
    }

    It 'is OK after a recent restart' {
        Mock Get-CimInstance { [pscustomobject]@{ LastBootUpTime = (Get-Date).AddHours(-5) } }
        $result = Get-UptimeHealth
        $result.Status | Should -Be 'OK'
        $result.Details | Should -Match '^0d [45]h$'
    }
}

Describe 'Get-PendingRebootHealth' {
    It 'warns when a reboot key exists' {
        Mock Test-Path { $true }
        (Get-PendingRebootHealth).Status | Should -Be 'WARNING'
    }

    It 'is OK when no reboot key exists' {
        Mock Test-Path { $false }
        (Get-PendingRebootHealth).Status | Should -Be 'OK'
    }
}

Describe 'Get-OverallExitCode' {
    It 'returns <Expected> for <Statuses>' -ForEach @(
        @{ Statuses = @('OK', 'OK'); Expected = 0 }
        @{ Statuses = @('OK', 'WARNING'); Expected = 1 }
        @{ Statuses = @('WARNING', 'CRITICAL', 'OK'); Expected = 2 }
    ) {
        $results = $Statuses | ForEach-Object { [pscustomobject]@{ Status = $_ } }
        Get-OverallExitCode -Results $results | Should -Be $Expected
    }
}
