$LogFile = "C:\SetupLogs\Post-Execution-Audit.log"
New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null
Start-Transcript -Path $LogFile -Append

Write-Host "`n--- Running Post-Deployment Checks ---" -ForegroundColor Cyan

# Check if AD DS is installed
if (Get-WindowsFeature -Name AD-Domain-Services | Where-Object {$_.InstallState -eq "Installed"}) {
    Write-Host "✔ AD-Domain-Services is installed." -ForegroundColor Green
} else {
    Write-Host "✘ AD-Domain-Services is NOT installed." -ForegroundColor Red
}

# Check if this machine is a Domain Controller
try {
    $isDC = ([System.DirectoryServices.ActiveDirectory.DomainController]::GetCurrentDomain()).Name
    Write-Host "✔ Server is a domain controller for: $isDC" -ForegroundColor Green
} catch {
    Write-Host "✘ Server is NOT a domain controller." -ForegroundColor Red
}

# Check DNS Server Role
if (Get-WindowsFeature -Name DNS | Where-Object {$_.InstallState -eq "Installed"}) {
    Write-Host "✔ DNS Server role is installed." -ForegroundColor Green
} else {
    Write-Host "✘ DNS Server role is NOT installed." -ForegroundColor Red
}

# Check DHCP Role (optional)
if (Get-WindowsFeature -Name DHCP | Where-Object {$_.InstallState -eq "Installed"}) {
    Write-Host "✔ DHCP Server role is installed." -ForegroundColor Green
} else {
    Write-Host "✘ DHCP Server role is NOT installed." -ForegroundColor Yellow
}

# Show current IP configuration
Write-Host "`n--- IP Configuration ---" -ForegroundColor Cyan
Get-NetIPAddress | Where-Object {$_.AddressFamily -eq "IPv4"} | Format-Table InterfaceAlias, IPAddress, PrefixLength

# Show current DNS settings
Write-Host "`n--- DNS Client Settings ---" -ForegroundColor Cyan
Get-DnsClientServerAddress | Format-Table InterfaceAlias, ServerAddresses

# Check if joined to a domain
$domain = (Get-WmiObject Win32_ComputerSystem).Domain
$role = (Get-WmiObject Win32_ComputerSystem).DomainRole

if ($role -ge 4) {
    Write-Host "✔ Server is joined to domain: $domain (Role: $role)" -ForegroundColor Green
} else {
    Write-Host "✘ Server is NOT joined to a domain (Current domain: $domain)" -ForegroundColor Red
}

Stop-Transcript
