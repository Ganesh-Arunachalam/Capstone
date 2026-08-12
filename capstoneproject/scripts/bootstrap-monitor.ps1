<#
.SYNOPSIS
    Bootstraps VM02 (Monitor Server).
.DESCRIPTION
    Enables WinRM for remote management, configures Windows Event Collector
    for centralised log aggregation, and installs RSAT management tools.
    Run once after VM provisioning.
.NOTES
    Run as Administrator. Tested on Windows Server 2022 Datacenter.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "=== Bootstrap: Monitor Server ===" -ForegroundColor Cyan

# --- Enable PowerShell Remoting (WinRM) -----------------------------------
Write-Host "  Enabling WinRM..."
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# Allow connections from any host — restrict in production to known CIDRs
Set-Item -Path 'WSMan:\localhost\Client\TrustedHosts' -Value '*' -Force
Write-Host "  WinRM enabled."

# --- Windows Event Collector (centralised log collection) -----------------
Write-Host "  Enabling Windows Event Collector service..."
Set-Service  -Name Wecsvc -StartupType Automatic
Start-Service -Name Wecsvc
Write-Host "  Wecsvc service started."

# --- RSAT tools (remote server management from this VM) -------------------
Write-Host "  Installing RSAT management tools (this may take a few minutes)..."
Get-WindowsCapability -Online |
    Where-Object { $_.Name -like 'Rsat.ServerManager*' -or $_.Name -like 'Rsat.ActiveDirectory*' } |
    ForEach-Object {
        Write-Host "    Adding: $($_.Name)"
        Add-WindowsCapability -Online -Name $_.Name -ErrorAction SilentlyContinue | Out-Null
    }

# --- Windows Firewall: allow WinRM (5985 HTTP, 5986 HTTPS) ---------------
Write-Host "  Configuring Windows Firewall for WinRM..."
$winrmRules = @(
    @{ DisplayName = 'Allow WinRM HTTP';  LocalPort = 5985 },
    @{ DisplayName = 'Allow WinRM HTTPS'; LocalPort = 5986 }
)
foreach ($rule in $winrmRules) {
    $existing = Get-NetFirewallRule -DisplayName $rule.DisplayName -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule `
            -DisplayName $rule.DisplayName `
            -Direction   Inbound `
            -Protocol    TCP `
            -LocalPort   $rule.LocalPort `
            -Action      Allow | Out-Null
        Write-Host "  Created rule: $($rule.DisplayName)"
    } else {
        Write-Host "  Rule already exists: $($rule.DisplayName)"
    }
}

Write-Host "=== Monitor Server Bootstrap Complete ===" -ForegroundColor Green
