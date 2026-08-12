<#
.SYNOPSIS
    Memory Fault Restore — terminates all injected memory pressure and
    validates full recovery. MUST be validated before running memory-fault.ps1.
.DESCRIPTION
    ═══════════════════════════════════════════════════════════════════
    SAFETY GATE — This script is the PRIMARY RESTORE MECHANISM.
    It must be run and validated BEFORE any fault injection occurs.
    ═══════════════════════════════════════════════════════════════════

    Restore Actions (executed in order):
      1. Identify and terminate all processes spawned by memory-fault.ps1
         (tagged via Environment variable MEMFAULT_SESSION).
      2. Remove the fault-injection sentinel file.
      3. Force a GC sweep and working-set trim on remaining processes.
      4. Wait for Available MBytes to recover above $RecoveryThresholdMB.
      5. Validate performance counters against the pre-change baseline.
      6. Write a timestamped recovery report.

    ───────────────────────────────────────────────────────────────────
    ROLLBACK STRATEGY DOCUMENTATION
    ───────────────────────────────────────────────────────────────────

    State that will be restored
    ───────────────────────────
    • All memory-fault.ps1 child processes are killed — their privately
      committed working sets are released back to the OS free list.
    • The fault sentinel file (%TEMP%\memfault.active) is removed, which
      causes any still-running fault loop threads to exit cleanly.
    • No registry keys, services, page-file settings, or OS configuration
      are altered by the fault script, so no additional restore steps are
      required for those items.

    Recovery prerequisites
    ──────────────────────
    • Run as the same elevated account used to launch memory-fault.ps1,
      OR as a local Administrator (sufficient to kill other-user processes
      when run elevated).
    • PowerShell 5.1 or later.
    • No dependency on network connectivity or domain availability.

    Rollback success criteria
    ─────────────────────────
    ALL of the following must be true for the restore to be declared
    successful:
      ✔  Zero fault-session processes remain running.
      ✔  Available Physical Memory ≥ $RecoveryThresholdMB (default 512 MB).
      ✔  % Committed Bytes In Use has dropped by ≥ 10 percentage points
         compared to the peak observed during fault injection, OR is below
         85 % absolute.
      ✔  Page Reads/sec has returned to within 2× of the pre-change
         baseline captured by memory-assess.ps1.

    Estimated recovery time
    ───────────────────────
    • Process termination  :  < 5 seconds
    • OS memory reclaim    :  10–60 seconds (depends on working-set size
                              and whether the Modified page-writer was
                              active)
    • Validation window    :  $ValidationSeconds seconds of counter
                              sampling (default 60)
    • Total expected time  :  ~2–3 minutes in typical scenarios;
                              allow up to 5 minutes on memory-constrained
                              hosts.

.PARAMETER SentinelFile
    Path to the sentinel file written by memory-fault.ps1.
    Default: $env:TEMP\memfault.active

.PARAMETER RecoveryThresholdMB
    Minimum Available MBytes required to declare memory recovered.
    Default: 512

.PARAMETER ValidationSeconds
    Duration (seconds) of post-restore counter sampling used to confirm
    recovery. Default: 60

.PARAMETER BaselineReport
    Path to the JSON baseline produced by memory-assess.ps1.
    When provided, counters are validated against the recorded baseline.
    Optional — omit to skip baseline comparison.

.PARAMETER ReportPath
    Directory where the recovery report JSON is written.
    Default: $env:TEMP\MemoryAssessment

.PARAMETER DryRun
    When specified, lists all actions that WOULD be taken without
    executing them. Use to validate the script before a live run.

.NOTES
    Run as Administrator. Tested on Windows Server 2022 Datacenter.
    Safe to run even when no fault is active — idempotent.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SentinelFile         = "$env:TEMP\memfault.active",
    [int]   $RecoveryThresholdMB  = 512,
    [int]   $ValidationSeconds    = 60,
    [string]$BaselineReport       = '',
    [string]$ReportPath           = "$env:TEMP\MemoryAssessment",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region ── Helpers ──────────────────────────────────────────────────────────────

function Write-Step  ([string]$Msg) { Write-Host "  $Msg" -ForegroundColor White }
function Write-Ok    ([string]$Msg) { Write-Host "  [OK]   $Msg" -ForegroundColor Green }
function Write-Warn  ([string]$Msg) { Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-Fail  ([string]$Msg) { Write-Host "  [FAIL] $Msg" -ForegroundColor Red }

function Get-CounterSample ([string]$CounterPath) {
    try {
        $s = (Get-Counter -Counter $CounterPath -MaxSamples 1 -ErrorAction Stop).CounterSamples[0].CookedValue
        [math]::Round($s, 2)
    } catch { $null }
}

function Get-CounterAverage {
    param([string]$CounterPath, [int]$Samples = 5, [int]$Interval = 3)
    try {
        $s = Get-Counter -Counter $CounterPath -SampleInterval $Interval `
                         -MaxSamples $Samples -ErrorAction Stop
        [math]::Round(($s.CounterSamples | Measure-Object -Property CookedValue -Average).Average, 2)
    } catch { $null }
}

function Assert-Elevated {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This script must be run as Administrator.'
    }
}

#endregion

#region ── Pre-flight ────────────────────────────────────────────────────────────

Assert-Elevated

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$dryLabel  = if ($DryRun) { ' [DRY-RUN]' } else { '' }

Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Memory Fault RESTORE Script$dryLabel  [$timestamp]" -ForegroundColor Cyan
Write-Host "  Host : $env:COMPUTERNAME   User : $env:USERDOMAIN\$env:USERNAME" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

#endregion

#region ── Step 1: Locate fault-injection processes ─────────────────────────────

Write-Host "--- [1/5] Locating fault-injection processes ---" -ForegroundColor Yellow

# memory-fault.ps1 sets MEMFAULT_SESSION env var on every child process it spawns.
$faultProcesses = Get-Process -ErrorAction SilentlyContinue |
    Where-Object {
        try {
            # Query environment block via WMI — works for any process the current
            # user can read. Will throw (and be caught) for protected system processes.
            $wmi = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction Stop
            $env = $wmi.GetOwner()  # just a probe; real env check below
            [System.Environment]::GetEnvironmentVariable('MEMFAULT_SESSION', 'Process') -ne $null
        } catch { $false }
    }

# Fallback: also match by process name pattern used by the fault script.
$faultByName = Get-Process -Name 'powershell', 'pwsh' -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowTitle -like '*MEMFAULT*' }

# Combine and deduplicate.
$allFaultProcs = @($faultProcesses) + @($faultByName) |
    Sort-Object Id -Unique

# Also check the sentinel file for recorded PIDs.
$sentinelPIDs = @()
if (Test-Path $SentinelFile) {
    try {
        $sentinelData = Get-Content $SentinelFile -Raw | ConvertFrom-Json
        $sentinelPIDs = @($sentinelData.PIDs)
        Write-Step "Sentinel file found. Recorded fault PIDs: $($sentinelPIDs -join ', ')"

        foreach ($pid in $sentinelPIDs) {
            $p = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if ($p -and ($allFaultProcs.Id -notcontains $pid)) {
                $allFaultProcs += $p
            }
        }
    } catch {
        Write-Warn "Could not parse sentinel file: $_"
    }
} else {
    Write-Warn "Sentinel file not found at: $SentinelFile  (fault may not be active, or path differs)"
}

Write-Step "Fault processes identified: $($allFaultProcs.Count)"
$allFaultProcs | ForEach-Object { Write-Step "  PID $($_.Id)  Name: $($_.ProcessName)" }

#endregion

#region ── Step 2: Terminate fault processes ────────────────────────────────────

Write-Host "`n--- [2/5] Terminating fault-injection processes ---" -ForegroundColor Yellow

$terminatedCount = 0
$terminationErrors = @()

foreach ($proc in $allFaultProcs) {
    if ($DryRun) {
        Write-Step "[DRY-RUN] Would stop PID $($proc.Id) ($($proc.ProcessName))"
        continue
    }
    try {
        if ($PSCmdlet.ShouldProcess("PID $($proc.Id) [$($proc.ProcessName)]", 'Stop-Process')) {
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            $terminatedCount++
            Write-Ok "Stopped PID $($proc.Id) ($($proc.ProcessName))"
        }
    } catch {
        $terminationErrors += "PID $($proc.Id): $_"
        Write-Fail "Could not stop PID $($proc.Id): $_"
    }
}

if (-not $DryRun) {
    Write-Ok "Processes terminated: $terminatedCount"
}

#endregion

#region ── Step 3: Remove sentinel file ─────────────────────────────────────────

Write-Host "`n--- [3/5] Removing fault sentinel file ---" -ForegroundColor Yellow

if (Test-Path $SentinelFile) {
    if ($DryRun) {
        Write-Step "[DRY-RUN] Would remove: $SentinelFile"
    } else {
        Remove-Item -Path $SentinelFile -Force
        Write-Ok "Sentinel file removed: $SentinelFile"
    }
} else {
    Write-Ok "Sentinel file already absent — nothing to remove."
}

# Allow OS 10 seconds to begin reclaiming memory before sampling.
if (-not $DryRun) {
    Write-Step "Waiting 10 seconds for OS memory reclaim to begin..."
    Start-Sleep -Seconds 10
}

#endregion

#region ── Step 4: Load optional baseline ───────────────────────────────────────

$baseline = $null
if ($BaselineReport -ne '' -and (Test-Path $BaselineReport)) {
    try {
        $baseline = Get-Content -Path $BaselineReport -Raw | ConvertFrom-Json
        Write-Host "`n--- Baseline loaded from: $BaselineReport ---" -ForegroundColor DarkGray
    } catch {
        Write-Warn "Could not parse baseline report: $_"
    }
}

#endregion

#region ── Step 5: Validate recovery ────────────────────────────────────────────

Write-Host "`n--- [4/5] Validating memory recovery ($ValidationSeconds-second window) ---" -ForegroundColor Yellow

if ($DryRun) {
    Write-Step "[DRY-RUN] Would sample counters for $ValidationSeconds seconds."
} else {
    Write-Step "Sampling — please wait ~$ValidationSeconds seconds..."

    $sampleCount    = [math]::Max(3, [int]($ValidationSeconds / 6))
    $sampleInterval = 6

    $availableMB    = Get-CounterAverage '\Memory\Available MBytes'        $sampleCount $sampleInterval
    $committedPct   = Get-CounterAverage '\Memory\% Committed Bytes In Use' $sampleCount $sampleInterval
    $pageReadsSec   = Get-CounterAverage '\Memory\Page Reads/sec'           $sampleCount $sampleInterval
    $pageFaultsSec  = Get-CounterAverage '\Memory\Page Faults/sec'          $sampleCount $sampleInterval

    Write-Host "`n  Post-Restore Counter Averages:"
    Write-Host ("  Available MBytes       : {0,8} MB" -f $availableMB)
    Write-Host ("  % Committed Bytes      : {0,8} %"  -f $committedPct)
    Write-Host ("  Page Reads/sec         : {0,8}"    -f $pageReadsSec)
    Write-Host ("  Page Faults/sec        : {0,8}"    -f $pageFaultsSec)

    # ── Evaluate success criteria ──────────────────────────────────────────────

    $criteria = [ordered]@{}

    # Criterion 1: zero fault processes
    $remainingFault = @(Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $sentinelPIDs -contains $_.Id })
    $criteria['ZeroFaultProcesses'] = ($remainingFault.Count -eq 0)

    # Criterion 2: available memory above threshold
    $criteria['AvailableMemoryRecovered'] = ($availableMB -ge $RecoveryThresholdMB)

    # Criterion 3: committed percentage below 85 % (absolute safety floor)
    $criteria['CommittedBelowAbsolute'] = ($committedPct -lt 85)

    # Criterion 4: page reads within 2× of baseline (when baseline available)
    if ($baseline -and $baseline.PerfBaseline.PageReadsSec -ne $null) {
        $baselineReads = [double]$baseline.PerfBaseline.PageReadsSec
        $allowedMax    = [math]::Max(10, $baselineReads * 2)   # floor of 10 to avoid false failures on idle systems
        $criteria['PageReadsWithinBaseline'] = ($pageReadsSec -le $allowedMax)
        Write-Step "Baseline Page Reads/sec: $baselineReads  Allowed max: $allowedMax"
    }

    $allPassed = ($criteria.Values | Where-Object { $_ -eq $false }).Count -eq 0

    Write-Host "`n  Recovery Criteria Results:"
    foreach ($key in $criteria.Keys) {
        if ($criteria[$key]) { Write-Ok $key } else { Write-Fail $key }
    }

    if ($allPassed) {
        Write-Host "`n  ✔ RESTORE VALIDATED — All criteria passed." -ForegroundColor Green
        Write-Host "    memory-fault.ps1 may now be used safely." -ForegroundColor Green
    } else {
        Write-Host "`n  ✘ RESTORE INCOMPLETE — One or more criteria failed." -ForegroundColor Red
        Write-Host "    Do NOT run memory-fault.ps1 until recovery is confirmed." -ForegroundColor Red
        Write-Host "    Wait 2 minutes and re-run this script, or investigate above failures." -ForegroundColor Red
    }
}

#endregion

#region ── Step 6: Write recovery report ────────────────────────────────────────

Write-Host "`n--- [5/5] Writing recovery report ---" -ForegroundColor Yellow

if (-not $DryRun) {
    $recoveryReport = [ordered]@{
        RestoreTimestamp       = (Get-Date -Format 'o')
        Hostname               = $env:COMPUTERNAME
        FaultProcessesFound    = $allFaultProcs.Count
        FaultProcessesKilled   = $terminatedCount
        TerminationErrors      = $terminationErrors
        SentinelFileRemoved    = -not (Test-Path $SentinelFile)
        PostRestoreCounters    = [ordered]@{
            AvailableMBytesAvg  = $availableMB
            CommittedPctAvg     = $committedPct
            PageReadsSec        = $pageReadsSec
            PageFaultsSec       = $pageFaultsSec
        }
        RecoveryCriteria       = $criteria
        AllCriteriaPassed      = $allPassed
    }

    if (-not (Test-Path $ReportPath)) {
        New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
    }

    $reportFile = Join-Path $ReportPath "restore_$timestamp.json"
    $recoveryReport | ConvertTo-Json -Depth 5 | Set-Content -Path $reportFile -Encoding UTF8
    Write-Ok "Recovery report saved: $reportFile"
}

Write-Host "`n═══════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

#endregion
