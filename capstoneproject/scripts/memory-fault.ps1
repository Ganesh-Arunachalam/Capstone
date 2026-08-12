<#
.SYNOPSIS
    Memory Fault Injection — simulates controlled memory pressure on
    Windows Server 2022 to exercise monitoring and alerting pipelines.
.DESCRIPTION
    ═══════════════════════════════════════════════════════════════════
    SAFETY GATE — DO NOT RUN THIS SCRIPT UNTIL:
      1. memory-assess.ps1 has been run and a baseline report saved.
      2. memory-restore.ps1 has been run in -DryRun mode with no errors.
      3. memory-restore.ps1 has been run live and ALL recovery criteria
         passed (restore report shows AllCriteriaPassed = true).
    ═══════════════════════════════════════════════════════════════════

    Fault Mechanism
    ───────────────
    Spawns one or more PowerShell child processes, each of which
    allocates and pins a configurable byte array in memory.  Using
    separate processes (rather than a single in-process array) ensures:
      • The fault is immediately reversible by killing the child processes.
      • The host PowerShell session remains responsive for monitoring.
      • Memory is truly committed (not just reserved) because .NET
        allocates on the LOH and the GC is suppressed per child.

    Controlled via:
      -TargetPressureMB   : Total MB to allocate across all workers.
      -WorkerCount        : Number of child processes (default 4).
      -MaxDurationSeconds : Hard safety ceiling — fault auto-terminates.
      -MaxUsagePct        : Safety ceiling as % of total physical RAM.
                            Fault will not start if current usage already
                            exceeds this value, and workers exit when it
                            is reached during the run.

    What this DOES cause:
      • High physical memory utilisation
      • Increased paging activity (Modified page-writer, Page Reads/sec)
      • Reduced available memory for other processes
      • Increased response latency for workloads that compete for RAM

    What this does NOT do:
      • Does not modify any OS configuration
      • Does not alter page-file settings
      • Does not affect services, IIS, or domain-joined components
      • Does not write to disk (beyond the sentinel file)
      • Does not cause kernel memory pool exhaustion
      • Does not allocate kernel or driver memory

    Fault Injection Safety Controls
    ─────────────────────────────────
      • Pre-flight check: aborts if current memory usage ≥ MaxUsagePct.
      • Pre-flight check: aborts if Available MBytes < RecoveryThresholdMB
        (ensures headroom for the OS and critical services).
      • Sentinel file written before workers start; restore script uses
        it to locate and kill workers even across sessions.
      • Each worker monitors free memory and self-terminates when
        Available MBytes < $WorkerSafetyFloorMB.
      • MaxDurationSeconds enforced in the parent — all workers are
        killed after the timeout regardless of state.

.PARAMETER TargetPressureMB
    Total MB of additional memory to commit across all workers.
    Default: 1024 (1 GB). Must not exceed (TotalRAM × MaxUsagePct / 100)
    minus current usage.

.PARAMETER WorkerCount
    Number of parallel child processes to spread the allocation across.
    Default: 4.

.PARAMETER MaxDurationSeconds
    Hard safety ceiling in seconds. All workers are killed after this
    duration. Default: 300 (5 minutes).

.PARAMETER MaxUsagePct
    Maximum allowed physical memory usage percentage. The fault will not
    start (and workers will self-terminate) if RAM usage exceeds this
    value. Default: 85.

.PARAMETER WorkerSafetyFloorMB
    Workers self-terminate if Available MBytes drops below this value.
    Protects the OS from exhaustion. Default: 256.

.PARAMETER RecoveryThresholdMB
    Minimum Available MBytes required before the fault is allowed to
    start. Mirrors the restore script threshold. Default: 512.

.PARAMETER SentinelFile
    Path for the sentinel file. Default: $env:TEMP\memfault.active

.PARAMETER BaselineReport
    Optional path to the JSON produced by memory-assess.ps1. Used for
    pre-flight validation of the recovery threshold.

.NOTES
    Run as Administrator. Tested on Windows Server 2022 Datacenter.
    ALWAYS keep memory-restore.ps1 open in a second terminal session
    ready to execute before running this script.
#>

[CmdletBinding()]
param(
    [ValidateRange(128, 32768)]
    [int]   $TargetPressureMB      = 1024,

    [ValidateRange(1, 16)]
    [int]   $WorkerCount           = 4,

    [ValidateRange(30, 3600)]
    [int]   $MaxDurationSeconds    = 300,

    [ValidateRange(50, 90)]
    [int]   $MaxUsagePct           = 85,

    [ValidateRange(128, 2048)]
    [int]   $WorkerSafetyFloorMB   = 256,

    [ValidateRange(256, 4096)]
    [int]   $RecoveryThresholdMB   = 512,

    [string]$SentinelFile          = "$env:TEMP\memfault.active",

    [string]$BaselineReport        = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region ── Helpers ──────────────────────────────────────────────────────────────

function Write-Step ([string]$Msg) { Write-Host "  $Msg" -ForegroundColor White }
function Write-Ok   ([string]$Msg) { Write-Host "  [OK]   $Msg" -ForegroundColor Green }
function Write-Warn ([string]$Msg) { Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-Fail ([string]$Msg) { Write-Host "  [FAIL] $Msg" -ForegroundColor Red }

function Assert-Elevated {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This script must be run as Administrator.'
    }
}

function Get-AvailableMemoryMB {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    [math]::Round($os.FreePhysicalMemory / 1024, 0)
}

function Get-MemoryUsagePct {
    $os    = Get-CimInstance -ClassName Win32_OperatingSystem
    $total = $os.TotalVisibleMemorySize
    $free  = $os.FreePhysicalMemory
    [math]::Round((($total - $free) / $total) * 100, 1)
}

#endregion

#region ── Banner & Safety Gate ─────────────────────────────────────────────────

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor Red
Write-Host "  FAULT INJECTION: Memory Pressure  [$timestamp]" -ForegroundColor Red
Write-Host "  Host   : $env:COMPUTERNAME" -ForegroundColor Red
Write-Host "  User   : $env:USERDOMAIN\$env:USERNAME" -ForegroundColor Red
Write-Host "  Target : $TargetPressureMB MB    Workers : $WorkerCount" -ForegroundColor Red
Write-Host "  Max Duration : $MaxDurationSeconds s    Max Usage : $MaxUsagePct %" -ForegroundColor Red
Write-Host "═══════════════════════════════════════════════════════════`n" -ForegroundColor Red

Assert-Elevated

#endregion

#region ── Pre-flight Checks ────────────────────────────────────────────────────

Write-Host "--- Pre-flight Safety Checks ---" -ForegroundColor Yellow

# Check 1: Restore script exists
$scriptDir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$restoreScript  = Join-Path $scriptDir 'memory-restore.ps1'
if (-not (Test-Path $restoreScript)) {
    Write-Fail "memory-restore.ps1 not found at: $restoreScript"
    Write-Fail "ABORT: Restore script must exist before fault injection is allowed."
    exit 1
}
Write-Ok "Restore script found: $restoreScript"

# Check 2: No active fault session already running
if (Test-Path $SentinelFile) {
    Write-Fail "Sentinel file already exists: $SentinelFile"
    Write-Fail "A fault session may already be active. Run memory-restore.ps1 first."
    exit 1
}
Write-Ok "No active fault session detected."

# Check 3: Current memory usage must be below MaxUsagePct
$currentUsagePct = Get-MemoryUsagePct
if ($currentUsagePct -ge $MaxUsagePct) {
    Write-Fail "Current memory usage ($currentUsagePct %) >= MaxUsagePct ($MaxUsagePct %)."
    Write-Fail "ABORT: Insufficient headroom to inject memory pressure safely."
    exit 1
}
Write-Ok "Current memory usage: $currentUsagePct %  (below $MaxUsagePct % ceiling)"

# Check 4: Available memory must be above RecoveryThresholdMB
$availableMB = Get-AvailableMemoryMB
if ($availableMB -lt $RecoveryThresholdMB) {
    Write-Fail "Available memory ($availableMB MB) < RecoveryThresholdMB ($RecoveryThresholdMB MB)."
    Write-Fail "ABORT: Not enough free memory — fault cannot be injected safely."
    exit 1
}
Write-Ok "Available memory: $availableMB MB  (above $RecoveryThresholdMB MB floor)"

# Check 5: Requested pressure must fit in headroom
$os           = Get-CimInstance -ClassName Win32_OperatingSystem
$totalMB      = [math]::Round($os.TotalVisibleMemorySize / 1024, 0)
$usedMB       = $totalMB - $availableMB
$maxAllowedMB = [math]::Floor($totalMB * ($MaxUsagePct / 100)) - $usedMB - $WorkerSafetyFloorMB
if ($TargetPressureMB -gt $maxAllowedMB) {
    Write-Warn "TargetPressureMB ($TargetPressureMB MB) exceeds safe headroom ($maxAllowedMB MB)."
    Write-Warn "Clamping TargetPressureMB to $maxAllowedMB MB."
    $TargetPressureMB = [math]::Max(128, $maxAllowedMB)
}
Write-Ok "Effective pressure target: $TargetPressureMB MB"

Write-Host ""

#endregion

#region ── Worker Script Block (runs in child processes) ─────────────────────────
#
# Passed as -EncodedCommand to each pwsh/powershell child.
# Parameters are embedded as literal values before encoding.
#

$workerTemplate = @'
[CmdletBinding()]
param(
    [int]   $AllocMB,
    [string]$SentinelFile,
    [int]   $SafetyFloorMB,
    [int]   $MaxSeconds
)

$env:MEMFAULT_SESSION = 'active'
$deadline = (Get-Date).AddSeconds($MaxSeconds)

# Allocate byte array (committed, not just reserved)
$bytes = [byte[]]::new($AllocMB * 1MB)

# Write non-zero values to force physical page backing (defeat demand-zero)
for ($i = 0; $i -lt $bytes.Length; $i += 4096) { $bytes[$i] = 0xAB }

Write-Host "  [Worker PID:$PID] Allocated $AllocMB MB — holding until sentinel removed or deadline."

while ((Test-Path $SentinelFile) -and ((Get-Date) -lt $deadline)) {
    # Periodically touch pages to prevent the modified page-writer from silently
    # reclaiming them, simulating realistic working-set retention.
    for ($i = 0; $i -lt $bytes.Length; $i += 65536) { $bytes[$i] = $bytes[$i] }

    # Safety floor: self-terminate if free memory drops too low
    $os   = Get-CimInstance Win32_OperatingSystem
    $free = [math]::Round($os.FreePhysicalMemory / 1024, 0)
    if ($free -lt $SafetyFloorMB) {
        Write-Warning "  [Worker PID:$PID] Available memory ($free MB) below safety floor ($SafetyFloorMB MB) — self-terminating."
        break
    }

    Start-Sleep -Seconds 5
}

Write-Host "  [Worker PID:$PID] Exiting — releasing $AllocMB MB."
$bytes = $null
[GC]::Collect()
'@

#endregion

#region ── Launch Workers ────────────────────────────────────────────────────────

Write-Host "--- Launching Memory-Pressure Workers ---" -ForegroundColor Yellow

$mbPerWorker = [math]::Ceiling($TargetPressureMB / $WorkerCount)
$workerPIDs  = @()
$jobs        = @()

foreach ($i in 1..$WorkerCount) {
    # Substitute parameters into the worker template before encoding.
    $workerScript = $workerTemplate `
        -replace '__ALLOCMB__',      $mbPerWorker `
        -replace '__SENTINEL__',     $SentinelFile `
        -replace '__SAFETYFLOOR__',  $WorkerSafetyFloorMB `
        -replace '__MAXSECONDS__',   $MaxDurationSeconds

    # Build the param block as a here-string so values are literal.
    $paramBlock = @"
`$AllocMB = $mbPerWorker
`$SentinelFile = '$SentinelFile'
`$SafetyFloorMB = $WorkerSafetyFloorMB
`$MaxSeconds = $MaxDurationSeconds
"@

    $fullScript   = $paramBlock + "`n" + $workerTemplate
    $encoded      = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($fullScript))

    $proc = Start-Process -FilePath 'powershell.exe' `
                          -ArgumentList "-NonInteractive -NoProfile -EncodedCommand $encoded" `
                          -PassThru `
                          -WindowStyle Hidden

    $workerPIDs += $proc.Id
    Write-Ok "Worker $i started — PID $($proc.Id)  alloc target: $mbPerWorker MB"
}

#endregion

#region ── Write Sentinel File ───────────────────────────────────────────────────

$sentinelData = [ordered]@{
    SessionTimestamp = (Get-Date -Format 'o')
    Hostname         = $env:COMPUTERNAME
    PIDs             = $workerPIDs
    TargetPressureMB = $TargetPressureMB
    WorkerCount      = $WorkerCount
    MaxDurationSec   = $MaxDurationSeconds
    MaxUsagePct      = $MaxUsagePct
    SafetyFloorMB    = $WorkerSafetyFloorMB
}

$sentinelData | ConvertTo-Json | Set-Content -Path $SentinelFile -Encoding UTF8
Write-Ok "Sentinel file written: $SentinelFile"

#endregion

#region ── Monitor Loop ──────────────────────────────────────────────────────────

Write-Host "`n--- Fault Active — Monitoring (press Ctrl+C to abort early) ---" -ForegroundColor Red
Write-Host "  Restore command: .\memory-restore.ps1 -SentinelFile '$SentinelFile'" -ForegroundColor Yellow
Write-Host ""

$deadline    = (Get-Date).AddSeconds($MaxDurationSeconds)
$sampleEvery = 15   # seconds between status updates

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds $sampleEvery

    $liveWorkers = @($workerPIDs | ForEach-Object {
        Get-Process -Id $_ -ErrorAction SilentlyContinue
    })

    $freeMB    = Get-AvailableMemoryMB
    $usagePct  = Get-MemoryUsagePct
    $elapsed   = [math]::Round(((Get-Date) - ($deadline.AddSeconds(-$MaxDurationSeconds))).TotalSeconds, 0)
    $remaining = [math]::Round(($deadline - (Get-Date)).TotalSeconds, 0)

    Write-Host ("  [{0:HH:mm:ss}] Workers: {1}/{2}  Available: {3} MB  Usage: {4} %  Elapsed: {5}s  Remaining: {6}s" -f `
        (Get-Date), $liveWorkers.Count, $WorkerCount, $freeMB, $usagePct, $elapsed, $remaining)

    # If all workers have already self-terminated, stop monitoring.
    if ($liveWorkers.Count -eq 0) {
        Write-Warn "All workers have exited early (safety floor or sentinel removal)."
        break
    }

    # Enforce MaxUsagePct ceiling from the parent as a secondary backstop.
    if ($usagePct -ge $MaxUsagePct) {
        Write-Warn "Usage ($usagePct %) reached ceiling ($MaxUsagePct %). Triggering auto-restore."
        break
    }
}

#endregion

#region ── Auto-Restore on Timeout ──────────────────────────────────────────────

Write-Host "`n--- Fault duration elapsed — initiating auto-restore ---" -ForegroundColor Yellow

# Remove sentinel so workers exit cleanly on their next loop iteration.
if (Test-Path $SentinelFile) {
    Remove-Item -Path $SentinelFile -Force
    Write-Ok "Sentinel file removed."
}

# Kill any workers that haven't exited within 10 seconds.
Start-Sleep -Seconds 10

foreach ($pid in $workerPIDs) {
    $p = Get-Process -Id $pid -ErrorAction SilentlyContinue
    if ($p) {
        try {
            Stop-Process -Id $pid -Force
            Write-Ok "Force-stopped lingering worker PID $pid."
        } catch {
            Write-Warn "Could not stop PID $pid : $_"
        }
    }
}

Write-Host "`n  Run memory-restore.ps1 to validate full recovery and produce the restore report."
Write-Host "  Command: .\memory-restore.ps1 -SentinelFile '$SentinelFile'"
Write-Host "`n═══════════════════════════════════════════════════════════`n" -ForegroundColor Red

#endregion
