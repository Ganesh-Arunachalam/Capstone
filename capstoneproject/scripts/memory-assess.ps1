<#
.SYNOPSIS
    Pre-Change Assessment — VM Memory Performance Baseline.
.DESCRIPTION
    Captures a comprehensive memory and system baseline before any fault
    injection activity. Output is written to a timestamped JSON report and
    echoed to the console. Run this FIRST, before memory-restore.ps1 or
    memory-fault.ps1.

    Collected data:
      - Physical memory totals and availability
      - Committed/virtual memory
      - Page-file configuration and current usage
      - Top-10 memory-consuming processes
      - Running services
      - Key performance counter snapshot (30-second average)
      - VM hardware configuration (processor count, NUMA nodes)

.PARAMETER ReportPath
    Directory where the JSON report is saved.
    Defaults to $env:TEMP\MemoryAssessment.

.NOTES
    Run as Administrator. Tested on Windows Server 2022 Datacenter.
    Output file is required input for memory-restore.ps1 validation.
#>

[CmdletBinding()]
param(
    [string]$ReportPath = "$env:TEMP\MemoryAssessment"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region ── Helpers ──────────────────────────────────────────────────────────────

function ConvertTo-GB ([long]$Bytes) { [math]::Round($Bytes / 1GB, 2) }
function ConvertTo-MB ([long]$Bytes) { [math]::Round($Bytes / 1MB, 2) }

function Get-CounterAverage {
    param([string]$CounterPath, [int]$SampleCount = 5, [int]$SampleInterval = 6)
    try {
        $samples = Get-Counter -Counter $CounterPath `
                               -SampleInterval $SampleInterval `
                               -MaxSamples $SampleCount `
                               -ErrorAction Stop
        $avg = ($samples.CounterSamples | Measure-Object -Property CookedValue -Average).Average
        [math]::Round($avg, 2)
    }
    catch { $null }
}

#endregion

#region ── Banner ────────────────────────────────────────────────────────────────

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
Write-Host "`n=== Memory Pre-Change Assessment  [$timestamp] ===" -ForegroundColor Cyan
Write-Host "    Host : $env:COMPUTERNAME"
Write-Host "    User : $env:USERDOMAIN\$env:USERNAME`n"

#endregion

#region ── 1. Physical Memory ────────────────────────────────────────────────────

Write-Host "--- [1/6] Physical Memory ---" -ForegroundColor Yellow

$os   = Get-CimInstance -ClassName Win32_OperatingSystem
$cs   = Get-CimInstance -ClassName Win32_ComputerSystem

$totalRAM_GB     = ConvertTo-GB $os.TotalVisibleMemorySize
$freeRAM_GB      = ConvertTo-GB ($os.FreePhysicalMemory * 1KB)
$usedRAM_GB      = [math]::Round($totalRAM_GB - $freeRAM_GB, 2)
$usedRAM_Pct     = [math]::Round(($usedRAM_GB / $totalRAM_GB) * 100, 1)
$totalVirtual_GB = ConvertTo-GB ($os.TotalVirtualMemorySize * 1KB)
$freeVirtual_GB  = ConvertTo-GB ($os.FreeVirtualMemory * 1KB)

$memSummary = [ordered]@{
    TotalPhysicalGB    = $totalRAM_GB
    UsedPhysicalGB     = $usedRAM_GB
    FreePhysicalGB     = $freeRAM_GB
    UsedPhysicalPct    = $usedRAM_Pct
    TotalVirtualGB     = $totalVirtual_GB
    FreeVirtualGB      = $freeVirtual_GB
    CommittedGB        = ConvertTo-GB (($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) * 1KB)
}

Write-Host "  Total Physical : $totalRAM_GB GB"
Write-Host "  Used           : $usedRAM_GB GB  ($usedRAM_Pct%)"
Write-Host "  Free           : $freeRAM_GB GB"
Write-Host "  Total Virtual  : $totalVirtual_GB GB"
Write-Host "  Free Virtual   : $freeVirtual_GB GB"

#endregion

#region ── 2. Page File ──────────────────────────────────────────────────────────

Write-Host "`n--- [2/6] Page File Configuration ---" -ForegroundColor Yellow

$pageFiles = Get-CimInstance -ClassName Win32_PageFileUsage | ForEach-Object {
    [ordered]@{
        Path            = $_.Name
        AllocatedSizeMB = $_.AllocatedBaseSize
        CurrentUsageMB  = $_.CurrentUsage
        PeakUsageMB     = $_.PeakUsage
        UsagePct        = if ($_.AllocatedBaseSize -gt 0) {
                              [math]::Round(($_.CurrentUsage / $_.AllocatedBaseSize) * 100, 1)
                          } else { 0 }
    }
}

$pageFileSettings = Get-CimInstance -ClassName Win32_PageFileSetting | ForEach-Object {
    [ordered]@{
        Path        = $_.Name
        InitialSizeMB = $_.InitialSize
        MaximumSizeMB = $_.MaximumSize
        Managed     = ($_.InitialSize -eq 0 -and $_.MaximumSize -eq 0)
    }
}

foreach ($pf in $pageFiles) {
    Write-Host "  Path           : $($pf.Path)"
    Write-Host "  Allocated      : $($pf.AllocatedSizeMB) MB"
    Write-Host "  Current Usage  : $($pf.CurrentUsageMB) MB  ($($pf.UsagePct)%)"
    Write-Host "  Peak Usage     : $($pf.PeakUsageMB) MB"
}

if (-not $pageFiles) { Write-Host "  No page file detected." -ForegroundColor DarkYellow }

#endregion

#region ── 3. Top Memory-Consuming Processes ────────────────────────────────────

Write-Host "`n--- [3/6] Top-10 Memory-Consuming Processes ---" -ForegroundColor Yellow

$topProcesses = Get-Process |
    Sort-Object WorkingSet64 -Descending |
    Select-Object -First 10 |
    ForEach-Object {
        [ordered]@{
            PID           = $_.Id
            Name          = $_.ProcessName
            WorkingSetMB  = ConvertTo-MB $_.WorkingSet64
            PrivateBytesMB= ConvertTo-MB $_.PrivateMemorySize64
            VirtualMB     = ConvertTo-MB $_.VirtualMemorySize64
        }
    }

$topProcesses | ForEach-Object {
    Write-Host ("  {0,-30} PID:{1,-6} WS:{2,8} MB   Private:{3,8} MB" -f `
        $_.Name, $_.PID, $_.WorkingSetMB, $_.PrivateBytesMB)
}

#endregion

#region ── 4. Running Services ──────────────────────────────────────────────────

Write-Host "`n--- [4/6] Running Services ---" -ForegroundColor Yellow

$runningServices = Get-Service |
    Where-Object { $_.Status -eq 'Running' } |
    Sort-Object DisplayName |
    ForEach-Object {
        [ordered]@{
            Name        = $_.Name
            DisplayName = $_.DisplayName
            StartType   = $_.StartType.ToString()
        }
    }

Write-Host "  Running service count: $($runningServices.Count)"
$runningServices | Select-Object -First 5 | ForEach-Object {
    Write-Host "  $($_.Name)  [$($_.StartType)]"
}
Write-Host "  ... (full list in report)"

#endregion

#region ── 5. Performance Counter Baseline (30-second window) ───────────────────

Write-Host "`n--- [5/6] Performance Counters (30-second average) ---" -ForegroundColor Yellow
Write-Host "  Sampling — please wait ~30 seconds..." -ForegroundColor DarkGray

$perfBaseline = [ordered]@{
    AvailableMBytesAvg          = Get-CounterAverage '\Memory\Available MBytes'
    CommittedBytesPct           = Get-CounterAverage '\Memory\% Committed Bytes In Use'
    PageFaultsSec               = Get-CounterAverage '\Memory\Page Faults/sec'
    PagesInputSec               = Get-CounterAverage '\Memory\Pages Input/sec'
    PagesOutputSec              = Get-CounterAverage '\Memory\Pages Output/sec'
    PageReadsSec                = Get-CounterAverage '\Memory\Page Reads/sec'
    CacheBytesMB                = if ($null -ne (Get-CounterAverage '\Memory\Cache Bytes')) {
                                      [math]::Round((Get-CounterAverage '\Memory\Cache Bytes') / 1MB, 2)
                                  } else { $null }
    PoolNonpagedBytesMB         = if ($null -ne (Get-CounterAverage '\Memory\Pool Nonpaged Bytes')) {
                                      [math]::Round((Get-CounterAverage '\Memory\Pool Nonpaged Bytes') / 1MB, 2)
                                  } else { $null }
    ProcessorTimePct            = Get-CounterAverage '\Processor(_Total)\% Processor Time'
}

Write-Host "  Available MBytes (avg)    : $($perfBaseline.AvailableMBytesAvg) MB"
Write-Host "  % Committed Bytes (avg)   : $($perfBaseline.CommittedBytesPct) %"
Write-Host "  Page Faults/sec (avg)     : $($perfBaseline.PageFaultsSec)"
Write-Host "  Pages Input/sec (avg)     : $($perfBaseline.PagesInputSec)"
Write-Host "  Pages Output/sec (avg)    : $($perfBaseline.PagesOutputSec)"
Write-Host "  % Processor Time (avg)    : $($perfBaseline.ProcessorTimePct) %"

#endregion

#region ── 6. VM / Hardware Configuration ───────────────────────────────────────

Write-Host "`n--- [6/6] VM Hardware Configuration ---" -ForegroundColor Yellow

$proc         = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
$numaNodes    = (Get-CimInstance -ClassName Win32_SystemMemoryArray -ErrorAction SilentlyContinue | Measure-Object).Count

$vmConfig = [ordered]@{
    ComputerName    = $env:COMPUTERNAME
    OSCaption       = $os.Caption
    OSBuildNumber   = $os.BuildNumber
    LogicalCPUs     = $cs.NumberOfLogicalProcessors
    PhysicalCPUs    = $cs.NumberOfProcessors
    CPUName         = $proc.Name
    NUMANodeCount   = $numaNodes
    TotalPhysicalGB = $totalRAM_GB
    SystemType      = $cs.SystemType
    HyperVGuest     = (Get-Service -Name vmicheartbeat -ErrorAction SilentlyContinue) -ne $null
}

Write-Host "  OS            : $($vmConfig.OSCaption)  (Build $($vmConfig.OSBuildNumber))"
Write-Host "  Logical CPUs  : $($vmConfig.LogicalCPUs)"
Write-Host "  Physical RAM  : $($vmConfig.TotalPhysicalGB) GB"
Write-Host "  Hyper-V Guest : $($vmConfig.HyperVGuest)"

#endregion

#region ── Assemble Report ───────────────────────────────────────────────────────

$report = [ordered]@{
    AssessmentTimestamp = (Get-Date -Format 'o')
    Hostname            = $env:COMPUTERNAME
    VMConfiguration     = $vmConfig
    PhysicalMemory      = $memSummary
    PageFiles           = $pageFiles
    PageFileSettings    = $pageFileSettings
    TopProcesses        = $topProcesses
    RunningServices     = $runningServices
    PerfBaseline        = $perfBaseline
}

if (-not (Test-Path $ReportPath)) {
    New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
}

$reportFile = Join-Path $ReportPath "baseline_$timestamp.json"
$report | ConvertTo-Json -Depth 5 | Set-Content -Path $reportFile -Encoding UTF8

Write-Host "`n=== Assessment Complete ===" -ForegroundColor Green
Write-Host "  Report saved : $reportFile"
Write-Host "  NEXT STEP    : Run memory-restore.ps1 to validate the restore mechanism."
Write-Host "  THEN         : Run memory-fault.ps1 only after restore is validated.`n"

#endregion
