<#
.SYNOPSIS
    Monitors system memory utilization and logs samples every 5 seconds.
.DESCRIPTION
    Captures total, free, used memory, and utilization percentage every 5 seconds.
    Logs all actions and samples to C:\Logs\memoryutil.log.
.NOTES
    Compatible with Windows Server 2022 and PowerShell 5.1.
    Stop execution with Ctrl+C.
#>

[CmdletBinding()]
param(
    [int]$IntervalSeconds = 5,
    [string]$LogDirectory = 'C:\Logs',
    [string]$LogFileName = 'memoryutil.log'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$logPath = Join-Path -Path $LogDirectory -ChildPath $LogFileName

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"

    Write-Host $line
    Add-Content -Path $logPath -Value $line
}

try {
    if (-not (Test-Path -Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -Path $logPath)) {
        New-Item -Path $logPath -ItemType File -Force | Out-Null
    }

    Write-Log -Message 'Memory utilization monitor started.'
    Write-Log -Message "Sampling interval: $IntervalSeconds seconds."
    Write-Log -Message "Log file: $logPath"

    while ($true) {
        try {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem

            $totalMB = [math]::Round(([double]$os.TotalVisibleMemorySize / 1024), 2)
            $freeMB = [math]::Round(([double]$os.FreePhysicalMemory / 1024), 2)
            $usedMB = [math]::Round(($totalMB - $freeMB), 2)

            if ($totalMB -gt 0) {
                $usedPercent = [math]::Round((($usedMB / $totalMB) * 100), 2)
            }
            else {
                $usedPercent = 0
            }

            $sample = "MemorySample TotalMB=$totalMB FreeMB=$freeMB UsedMB=$usedMB UtilizationPercent=$usedPercent"
            Write-Log -Message $sample
        }
        catch {
            Write-Log -Level 'ERROR' -Message "Sample collection failed: $($_.Exception.Message)"
        }

        Start-Sleep -Seconds $IntervalSeconds
    }
}
catch {
    Write-Log -Level 'ERROR' -Message "Monitor initialization failed: $($_.Exception.Message)"
    throw
}
finally {
    try {
        Write-Log -Message 'Memory utilization monitor stopped.' -Level 'WARN'
    }
    catch {
        Write-Host 'Unable to write shutdown log entry.'
    }
}
