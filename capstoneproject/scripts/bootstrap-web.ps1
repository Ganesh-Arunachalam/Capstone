<#
.SYNOPSIS
    Bootstraps IIS on VM01 (Web Server).
.DESCRIPTION
    Installs IIS with common Web Server features and configures Windows Firewall
    to allow inbound HTTP and HTTPS traffic. Run once after VM provisioning.
.NOTES
    Run as Administrator. Tested on Windows Server 2022 Datacenter.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "=== Bootstrap: Web Server (IIS) ===" -ForegroundColor Cyan

# --- Install IIS features -------------------------------------------------
$features = @(
    'Web-Server',          # IIS core
    'Web-Common-Http',     # Default doc, dir browsing, HTTP errors, static content
    'Web-Default-Doc',
    'Web-Dir-Browsing',
    'Web-Http-Errors',
    'Web-Static-Content',
    'Web-Http-Logging',    # Request logging
    'Web-Stat-Compression',# Static content compression
    'Web-Filtering',       # Request filtering
    'Web-Mgmt-Console',    # IIS Manager GUI
    'Web-Mgmt-Tools'
)

foreach ($feature in $features) {
    Write-Host "  Installing feature: $feature"
    Install-WindowsFeature -Name $feature -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
}

# --- Ensure W3SVC is running and set to auto-start ------------------------
Set-Service  -Name W3SVC -StartupType Automatic
Start-Service -Name W3SVC
Write-Host "  IIS (W3SVC) service started."

# --- Configure Windows Firewall -------------------------------------------
Write-Host "=== Configuring Windows Firewall ===" -ForegroundColor Cyan

$firewallRules = @(
    @{ DisplayName = 'Allow HTTP Inbound';  LocalPort = 80  },
    @{ DisplayName = 'Allow HTTPS Inbound'; LocalPort = 443 }
)

foreach ($rule in $firewallRules) {
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

Write-Host "=== Web Server Bootstrap Complete ===" -ForegroundColor Green
