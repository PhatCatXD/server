Write-Host "Starting Windows Server 2022 full deployment..."

# Prompt for user input
$DomainName = Read-Host "What should the domain name be? (e.g., home.arpa.local)"

$DomainNetbiosName = Read-Host "What should the domain NetBIOS name be?"

$ServerName = Read-Host "What should the server name be? (e.g., SRV-1)"

$StaticIP = Read-Host "What should the static IP address for the server be?"

$DHCPStartIP = Read-Host "What should the DHCP lease range start address be?"

$DHCPEndIP = Read-Host "What should the DHCP lease range end address be?"

$SubnetMask = Read-Host "What should the subnet mask be?"

$DefaultGateway = Read-Host "What should the default gateway be?"

$RestartResponse = Read-Host "Do you want to restart after script execution? (Y/N)"






# AD Installation
Write-Host "Installing Active Directory Domain Services..."
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# Import the ADDSDeployment module for domain configuration
Import-Module ADDSDeployment

Write-Host "Promoting the server to a domain controller..."
    Install-ADDSForest -DomainName "$DomainName" -DomainNetbiosName "$DomainNetbiosName" -SafeModeAdministratorPassword (ConvertTo-SecureString "P@ssw0rd!" -AsPlainText -Force) -NoRebootOnCompletion -Force


# DHCP Installation
Write-Host "Installing DHCP Server..."
    Install-WindowsFeature -Name DHCP -IncludeManagementTools

#DHCP Configuration
Write-Host "Configuring DHCP scope..."
    Add-DhcpServerv4Scope -Name "DefaultScope" -StartRange $DHCPStartIP -EndRange $DHCPEndIP -SubnetMask $SubnetMask -State Active
    Set-DhcpServerv4OptionValue -OptionId 3 -Value $DefaultGateway
Write-Host "DHCP scope configured successfully."


# DNS Configuration
Write-Host "Setting up DNS server..."
    Add-DnsServerPrimaryZone -Name $DomainName
    Add-DnsServerResourceRecordA -Name $ServerName -ZoneName $DomainName -IPv4Address $StaticIP



if ($RestartResponse -eq "Y" -or $RestartResponse -eq "y") {
    Write-Host "Restarting the server..."
    Restart-Computer -Force
} else {
    Write-Host "Script execution completed. No restart will be performed."
}