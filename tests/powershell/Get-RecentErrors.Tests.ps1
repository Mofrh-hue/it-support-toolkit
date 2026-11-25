BeforeAll {
    if (-not (Get-Command Get-WinEvent -ErrorAction SilentlyContinue)) {
        function global:Get-WinEvent { param($FilterHashtable, $ErrorAction) }
    }
    . "$PSScriptRoot/../../powershell/Get-RecentErrors.ps1"

    function New-FakeEvent ($Log, $Source, $Id, $HoursAgo, $Message) {
        [pscustomobject]@{
            LogName      = $Log
            ProviderName = $Source
            Id           = $Id
            TimeCreated  = (Get-Date).AddHours(-$HoursAgo)
            Message      = $Message
        }
    }
}

Describe 'ConvertTo-ErrorSummary' {
    BeforeAll {
        $script:events = @(
            New-FakeEvent 'System' 'Disk' 7 1 'The device has a bad block.'
            New-FakeEvent 'System' 'Disk' 7 3 'The device has a bad block.'
            New-FakeEvent 'System' 'Disk' 153 2 'The IO operation was retried.'
            New-FakeEvent 'Application' 'Application Error' 1000 5 "Faulting application name: outlook.exe`r`nMore details here"
        )
    }

    It 'groups events by source, most frequent first' {
        $summary = @(ConvertTo-ErrorSummary -EventRecord $script:events)

        $summary | Should -HaveCount 2
        $summary[0].Source | Should -Be 'Disk'
        $summary[0].Count | Should -Be 3
        $summary[1].Source | Should -Be 'Application Error'
    }

    It 'shows the most recent event of each group' {
        $summary = @(ConvertTo-ErrorSummary -EventRecord $script:events)
        $summary[0].LastEventId | Should -Be 7
        $summary[0].LatestMessage | Should -Be 'The device has a bad block.'
    }

    It 'keeps only the first line of a multi-line message' {
        $summary = @(ConvertTo-ErrorSummary -EventRecord $script:events)
        $summary[1].LatestMessage | Should -Be 'Faulting application name: outlook.exe'
    }

    It 'shortens very long messages' {
        $long = New-FakeEvent 'System' 'Service Control Manager' 7031 1 ('x' * 300)
        $summary = ConvertTo-ErrorSummary -EventRecord @($long)
        $summary.LatestMessage.Length | Should -Be 100
        $summary.LatestMessage | Should -Match '\.\.\.$'
    }

    It 'limits the output to Top sources' {
        @(ConvertTo-ErrorSummary -EventRecord $script:events -Top 1) | Should -HaveCount 1
    }

    It 'returns nothing for no events' {
        @(ConvertTo-ErrorSummary -EventRecord @()) | Should -HaveCount 0
    }
}

Describe 'Get-ErrorEvent' {
    It 'asks only for Critical and Error events from System and Application' {
        Mock Get-WinEvent { @() }

        Get-ErrorEvent -StartTime (Get-Date).AddHours(-4)

        Should -Invoke Get-WinEvent -Times 1 -ParameterFilter {
            ($FilterHashtable.LogName -join ',') -eq 'System,Application' -and
            ($FilterHashtable.Level -join ',') -eq '1,2'
        }
    }
}
