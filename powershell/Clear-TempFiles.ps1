<#
.SYNOPSIS
    Frees disk space by deleting old temporary files.

.DESCRIPTION
    Deletes files older than a given number of days from temp folders and
    reports how much space was freed. Files that are in use are skipped.
    Supports -WhatIf, so you can see what would be deleted before deleting it.

.PARAMETER Path
    Folders to clean. Default: the current user's TEMP folder.
    Add C:\Windows\Temp when running as administrator.

.PARAMETER OlderThanDays
    Only delete files last changed more than this many days ago. Default 7.

.EXAMPLE
    .\Clear-TempFiles.ps1 -WhatIf

.EXAMPLE
    .\Clear-TempFiles.ps1 -Path $env:TEMP, 'C:\Windows\Temp' -OlderThanDays 14
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]] $Path = @([System.IO.Path]::GetTempPath()),

    [ValidateRange(0, 3650)]
    [int] $OlderThanDays = 7
)

function Get-OldFile {
    <# Files under Path last written before the cutoff date. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [int] $OlderThanDays
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Warning "Folder not found: $Path"
        return
    }
    $cutoff = (Get-Date).AddDays(-$OlderThanDays)
    Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff }
}

function Remove-OldFile {
    <# Deletes old files and returns a summary of what was removed. #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [int] $OlderThanDays
    )
    $deleted = 0
    $skipped = 0
    [long] $bytes = 0
    foreach ($file in @(Get-OldFile -Path $Path -OlderThanDays $OlderThanDays)) {
        if ($PSCmdlet.ShouldProcess($file.FullName, 'Delete')) {
            try {
                $size = $file.Length
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                $deleted++
                $bytes += $size
            }
            catch {
                # Usually a file that is open in another program
                $skipped++
            }
        }
    }
    [pscustomobject]@{
        Path    = $Path
        Deleted = $deleted
        Skipped = $skipped
        FreedMB = [math]::Round($bytes / 1MB, 1)
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $summary = foreach ($folder in $Path) {
        Remove-OldFile -Path $folder -OlderThanDays $OlderThanDays
    }
    $summary | Format-Table -AutoSize | Out-String | Write-Output
    if (-not $WhatIfPreference) {
        Write-Output ("Total freed: {0} MB" -f ($summary | Measure-Object -Property FreedMB -Sum).Sum)
    }
}
