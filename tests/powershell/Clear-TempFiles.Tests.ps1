BeforeAll {
    . "$PSScriptRoot/../../powershell/Clear-TempFiles.ps1"
}

Describe 'Clear-TempFiles' {
    BeforeEach {
        # Fresh test folder: two old files (one in a subfolder) and one new file
        $script:dir = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $script:dir 'sub') -Force | Out-Null

        $old1 = Join-Path $script:dir 'old-installer.tmp'
        $old2 = Join-Path $script:dir 'sub/old-cache.tmp'
        $new = Join-Path $script:dir 'new-document.tmp'
        Set-Content -Path $old1 -Value ('a' * 2048)
        Set-Content -Path $old2 -Value ('b' * 1024)
        Set-Content -Path $new -Value 'keep me'
        (Get-Item $old1).LastWriteTime = (Get-Date).AddDays(-30)
        (Get-Item $old2).LastWriteTime = (Get-Date).AddDays(-10)
    }

    It 'finds only files older than the cutoff, including subfolders' {
        $files = @(Get-OldFile -Path $script:dir -OlderThanDays 7)
        $files | Should -HaveCount 2
        $files.Name | Should -Not -Contain 'new-document.tmp'
    }

    It 'respects a longer cutoff' {
        @(Get-OldFile -Path $script:dir -OlderThanDays 20) | Should -HaveCount 1
    }

    It 'deletes old files, keeps new ones and reports the result' {
        $summary = Remove-OldFile -Path $script:dir -OlderThanDays 7

        $summary.Deleted | Should -Be 2
        $summary.Skipped | Should -Be 0
        Test-Path (Join-Path $script:dir 'old-installer.tmp') | Should -BeFalse
        Test-Path (Join-Path $script:dir 'new-document.tmp') | Should -BeTrue
    }

    It 'does not delete anything with -WhatIf' {
        $summary = Remove-OldFile -Path $script:dir -OlderThanDays 7 -WhatIf

        $summary.Deleted | Should -Be 0
        @(Get-ChildItem $script:dir -File -Recurse) | Should -HaveCount 3
    }

    It 'warns and returns nothing for a folder that does not exist' {
        $result = Get-OldFile -Path (Join-Path $TestDrive 'missing') -OlderThanDays 7 -WarningVariable warn -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $warn | Should -Match 'Folder not found'
    }
}
