# Write in terminal that the script is starting
Write-Host "Starting Windows Server 2022 full deployment..."

# Prompt for user input
$DomainName = Read-Host "What should the domain name be? (e.g., homearpa.local)"

$DomainNetbiosName = Read-Host "What should the domain NetBIOS name be? (e.g., HOMEARPA)"

$ServerName = Read-Host "What should the server name be? (e.g., SRV-1)"

$StaticIP = Read-Host "What should the static IP address be? (e.g., 192.168.1.2)"

$DHCPStartIP = Read-Host "What should the DHCP lease range start address be? (e.g., 192.168.1.100)"

$DHCPEndIP = Read-Host "What should the DHCP lease range end address be? (e.g., 192.168.1.200)"

$SubnetMask = Read-Host "What should the subnet mask be? (e.g., 255.255.255.0)"

$DefaultGateway = Read-Host "What should the default gateway be? (e.g., 192.168.1.1)"


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
