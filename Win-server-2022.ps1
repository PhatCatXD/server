# Write in terminal that the script is starting
Write-Host "Starting Windows Server 2022 full deployment..."

# Prompt for user input
Write-Host "What should the domain name be?"
$DomainName = Read-Host "Enter the domain name (e.g., home.arpa.local)"

Write-Host "What should the domain NetBIOS name be?"
$DomainNetbiosName = Read-Host "Enter the domain NetBIOS name (e.g., homearpa)"

Write-Host "What should the server name be?"
$ServerName = Read-Host "Enter the server name (e.g., Server1)"

Write-Host "What should the static IP address be?"
$StaticIP = Read-Host "Enter the static IP address (e.g., 192.168.1.2)"

Write-Host "What should the DHCP lease range start address be?"
$DHCPStartIP = Read-Host "Enter the DHCP lease range start address (e.g., 192.168.1.100)"

Write-Host "What should the DHCP lease range end address be?"
$DHCPEndIP = Read-Host "Enter the DHCP lease range end address (e.g., 192.168.1.200)"

Write-Host "What should the subnet mask be?"
$SubnetMask = Read-Host "Enter the subnet mask (e.g., 255.255.255.0)"

Write-Host "What should the default gateway be?"
$DefaultGateway = Read-Host "Enter the default gateway (e.g., 192.168.1.1)"

# AD Installation
Write-Host "Installing Active Directory Domain Services..."
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment

Write-Host "Promoting the server to a domain controller..."
Install-ADDSForest -DomainName "$DomainName" -DomainNetbiosName "$DomainNetbiosName" -SafeModeAdministratorPassword (ConvertTo-SecureString "P@ssw0rd!" -AsPlainText -Force) -NoRebootOnCompletion -Force

# DHCP Installation
Write-Host "Installing DHCP Server..."
Install-WindowsFeature -Name DHCP -IncludeManagementTools

Write-Host "Configuring DHCP scope..."
Add-DhcpServerv4Scope -Name "DefaultScope" -StartRange $DHCPStartIP -EndRange $DHCPEndIP -SubnetMask $SubnetMask -State Active
Set-DhcpServerv4OptionValue -OptionId 3 -Value $DefaultGateway

# DNS Configuration
Write-Host "Configuring DNS..."
Add-DnsServerPrimaryZone -Name $DomainName -ZoneFile "$DomainName.dns"
Add-DnsServerResourceRecordA -Name $ServerName -ZoneName $DomainName -IPv4Address $StaticIP

Write-Host "Deployment complete. Please reboot the server to apply changes."