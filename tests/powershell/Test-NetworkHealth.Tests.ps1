BeforeAll {
    . "$PSScriptRoot/../../powershell/Test-NetworkHealth.ps1"
}

Describe 'Split-Target' {
    It 'uses the default port when none is given' {
        $t = Split-Target -Value 'example.com' -DefaultPort 443
        $t.Host | Should -Be 'example.com'
        $t.Port | Should -Be 443
    }

    It 'reads the port from host:port' {
        $t = Split-Target -Value 'intranet.local:8443'
        $t.Host | Should -Be 'intranet.local'
        $t.Port | Should -Be 8443
    }
}

Describe 'Resolve-HostAddress' {
    It 'resolves localhost' {
        Resolve-HostAddress -HostName 'localhost' | Should -Not -BeNullOrEmpty
    }

    It 'returns nothing for a name that does not exist' {
        Resolve-HostAddress -HostName 'no-such-host.invalid' | Should -BeNullOrEmpty
    }
}

Describe 'Test-TcpPort' {
    BeforeAll {
        # Open a real listener on a free local port
        $script:listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $script:listener.Start()
        $script:openPort = $script:listener.LocalEndpoint.Port
    }
    AfterAll {
        $script:listener.Stop()
    }

    It 'returns true for an open port' {
        Test-TcpPort -HostName '127.0.0.1' -Port $script:openPort -TimeoutMs 2000 | Should -BeTrue
    }

    It 'returns false for a closed port' {
        Test-TcpPort -HostName '127.0.0.1' -Port 1 -TimeoutMs 1000 | Should -BeFalse
    }
}

Describe 'Test-Target' {
    It 'reports a DNS failure when the name does not resolve' {
        Mock Resolve-HostAddress { $null }
        Mock Test-TcpPort { $true }

        $r = Test-Target -Value 'broken.example'

        $r.Status | Should -Be 'FAIL'
        $r.Details | Should -Match 'DNS'
        Should -Invoke Test-TcpPort -Times 0
    }

    It 'reports a blocked port when DNS works but TCP does not' {
        Mock Resolve-HostAddress { '10.0.0.5' }
        Mock Test-TcpPort { $false }

        $r = Test-Target -Value 'app.example:8080'

        $r.Status | Should -Be 'FAIL'
        $r.Address | Should -Be '10.0.0.5'
        $r.Port | Should -Be 8080
        $r.Details | Should -Match 'firewall'
    }

    It 'reports OK when both checks pass' {
        Mock Resolve-HostAddress { '10.0.0.5' }
        Mock Test-TcpPort { $true }
        (Test-Target -Value 'app.example').Status | Should -Be 'OK'
    }
}

Describe 'Get-NetworkExitCode' {
    It 'returns <Expected> for <Statuses>' -ForEach @(
        @{ Statuses = @('OK', 'OK'); Expected = 0 }
        @{ Statuses = @('OK', 'FAIL'); Expected = 1 }
        @{ Statuses = @('FAIL', 'FAIL'); Expected = 2 }
    ) {
        $results = $Statuses | ForEach-Object { [pscustomobject]@{ Status = $_ } }
        Get-NetworkExitCode -Results $results | Should -Be $Expected
    }
}
