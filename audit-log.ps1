# =============================
# Post Execution Audit Log
# =============================

# Relaunch as admin if not elevated
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole("Administrator")) {
    Start-Process powershell.exe "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Setup output log path
$TimeStamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$UserDownloads = [Environment]::GetFolderPath("Downloads")
$UserDesktop   = [Environment]::GetFolderPath("Desktop")

$LogPath = if (Test-Path $UserDownloads) {
    Join-Path $UserDownloads "ServerAudit_$TimeStamp.txt"
} else {
    Join-Path $UserDesktop "ServerAudit_$TimeStamp.txt"
}

# Start logging
Start-Transcript -Path $LogPath -Append -NoClobber

Write-Host "Starting post-deployment audit..." -ForegroundColor Cyan
$PhaseRegKey = "HKLM:\SOFTWARE\Autodeploy\ServerDeployment"

function Check($Condition, $Success, $Fail) {
    if ($Condition) {
        Write-Host "✔ $Success" -ForegroundColor Green
    } else {
        Write-Host "✖ $Fail" -ForegroundColor Red
    }
}

# Retrieve saved values
try {
    $DomainName        = Get-ItemPropertyValue -Path $PhaseRegKey -Name DomainName
    $DomainNetbiosName = Get-ItemPropertyValue -Path $PhaseRegKey -Name DomainNetbiosName
    $ReverseLookup     = Get-ItemPropertyValue -Path $PhaseRegKey -Name ReverseLookupZoneNetworkID
    $ServerName        = Get-ItemPropertyValue -Path $PhaseRegKey -Name ServerName
    $StaticIP          = Get-ItemPropertyValue -Path $PhaseRegKey -Name StaticIP
} catch {
    Write-Host "⚠ Could not load all registry values. Audit may be incomplete." -ForegroundColor Yellow
}

Write-Host "`n===== ROLES ====="

Check (Get-WindowsFeature AD-Domain-Services | Where-Object {$_.InstallState -eq 'Installed'}) "AD-Domain-Services installed" "AD-Domain-Services missing"
Check (Get-WindowsFeature DNS | Where-Object {$_.InstallState -eq 'Installed'}) "DNS Server installed" "DNS Server missing"
Check (Get-WindowsFeature DHCP | Where-Object {$_.InstallState -eq 'Installed'}) "DHCP Server installed" "DHCP Server missing"

Write-Host "`n===== DOMAIN ====="

Check (([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain() -ne $null)) "Domain joined and promoted" "Not joined to domain or promotion failed"

Write-Host "`n===== DNS ====="

Import-Module DnsServer -ErrorAction SilentlyContinue

Check (Get-DnsServerZone -Name $DomainName -ErrorAction SilentlyContinue) "Forward zone '$DomainName' exists" "Forward zone '$DomainName' missing"

if ($ReverseLookup) {
    $Octets = $ReverseLookup -split '\.'
    $ReverseZone = "$($Octets[2]).$($Octets[1]).$($Octets[0]).in-addr.arpa"
    Check (Get-DnsServerZone -Name $ReverseZone -ErrorAction SilentlyContinue) "Reverse zone '$ReverseZone' exists" "Reverse zone '$ReverseZone' missing"
}

Check (
    Get-DnsServerResourceRecord -ZoneName $DomainName -Name $ServerName -RRType A -ErrorAction SilentlyContinue
) "A record for '$ServerName.$DomainName' exists" "Missing A record"

if ($StaticIP -and $ReverseZone) {
    $LastOctet = ($StaticIP -split '\.')[3]
    Check (
        Get-DnsServerResourceRecord -ZoneName $ReverseZone -Name $LastOctet -RRType PTR -ErrorAction SilentlyContinue
    ) "PTR record for $StaticIP exists" "Missing PTR record"
}

Write-Host "`n===== DHCP ====="

Import-Module DhcpServer -ErrorAction SilentlyContinue

$scope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
Check ($scope) "At least one DHCP scope exists" "No DHCP scope found"

if ($scope) {
    Check ($scope.State -eq "Active") "DHCP scope is active" "DHCP scope is inactive"

    $gateway = (Get-DhcpServerv4OptionValue -OptionId 3 -ErrorAction SilentlyContinue).Value
    Check ($gateway) "Default gateway option set: $gateway" "Default gateway option missing"
}

Write-Host "`n===== AUDIT COMPLETE =====" -ForegroundColor Cyan
Write-Host "`nLog saved to: $LogPath" -ForegroundColor Gray

Stop-Transcript
