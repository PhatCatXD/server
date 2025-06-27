# =============================
# Post Execution Audit Log
# =============================

# Diagnostics: Let user know we're alive
Write-Host "Launching audit-log.ps1..." -ForegroundColor Yellow

# Relaunch as admin if not elevated
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole("Administrator")) {
    Write-Host "Not running as administrator. Attempting to relaunch..." -ForegroundColor DarkYellow
    Start-Process powershell.exe "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`"" -Verb RunAs
    Start-Sleep -Seconds 2
    exit
}

# Confirm elevation
Write-Host "Running with administrator privileges." -ForegroundColor Green

# Setup output log path
$TimeStamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$UserDownloads = [Environment]::GetFolderPath("Downloads")
$UserDesktop   = [Environment]::GetFolderPath("Desktop")

$LogPath = if (Test-Path $UserDownloads) {
    Join-Path $UserDownloads "ServerAudit_$TimeStamp.txt"
} else {
    Join-Path $UserDesktop "ServerAudit_$TimeStamp.txt"
}

Write-Host "Logging output to: $LogPath"

# Start logging
Start-Transcript -Path $LogPath -Append -NoClobber
Write-Host "Starting post-deployment audit..." -ForegroundColor Cyan

# Helper function for checking results
function Check($Condition, $Success, $Fail) {
    if ($Condition) {
        Write-Host "✔ $Success" -ForegroundColor Green
    } else {
        Write-Host "✖ $Fail" -ForegroundColor Red
    }
}

# Check SetupPhase registry key
$PhaseRegKey = "HKLM:\SOFTWARE\Autodeploy\ServerDeployment"
$SetupPhase = (Get-ItemProperty -Path $PhaseRegKey -ErrorAction SilentlyContinue).SetupPhase
Check ($SetupPhase -ne $null) "SetupPhase key exists." "Missing SetupPhase key."
Check ($SetupPhase -eq 'Done') "Deployment phase is 'Done'." "Deployment phase not complete. Current: $SetupPhase"

# Check static IP
$adapter = Get-NetIPConfiguration | Where-Object { $_.IPv4Address.IPAddress -and $_.IPv4DefaultGateway }
Check ($adapter.IPv4Address.IPAddress -ne $null) "Static IP is set: $($adapter.IPv4Address.IPAddress)" "No static IP found."

# Check DNS and DHCP role installation
$roles = Get-WindowsFeature
Check ($roles | Where-Object { $_.Name -eq "DNS" -and $_.InstallState -eq "Installed" }) "DNS role installed." "DNS role not installed."
Check ($roles | Where-Object { $_.Name -eq "DHCP" -and $_.InstallState -eq "Installed" }) "DHCP role installed." "DHCP role not installed."

# Check domain join status
$domain = (Get-WmiObject Win32_ComputerSystem).Domain
$partOfDomain = (Get-WmiObject Win32_ComputerSystem).PartOfDomain
Check ($partOfDomain -and $domain -ne $null) "Computer is joined to domain: $domain" "Computer is not domain joined."

# End logging
Write-Host "Audit complete. Log saved to: $LogPath"
Stop-Transcript

# Pause before exiting
Write-Host ""
Read-Host -Prompt "Press Enter to close this window"


