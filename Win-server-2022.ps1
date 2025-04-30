# Write in terminal that the script is starting
Write-Host "Starting Windows Server 2022 full deployment..."

# Prompt for user input
$DomainName = Read-Host "What should the domain name be? (e.g., home.arpa.local)"

$DomainNetbiosName = Read-Host "What should the domain NetBIOS name be? (e.g., HOMEARPA)"

$ServerName = Read-Host "What should the server name be? (e.g., SRV-1)"

$StaticIP = Read-Host "What should the static IP address be? (e.g., 192.168.1.2)"

$DHCPStartIP = Read-Host "What should the DHCP lease range start address be? (e.g., 192.168.1.100)"

$DHCPEndIP = Read-Host "What should the DHCP lease range end address be? (e.g., 192.168.1.200)"

$SubnetMask = Read-Host "What should the subnet mask be? (e.g., 255.255.255.0)"

$DefaultGateway = Read-Host "What should the default gateway be? (e.g., 192.168.1.1)"

$RestartResponse = Read-Host "Do you want to restart after script execution? (Y/N)"

# Validate IP address format
function Validate-IP {
    param ([string]$IPAddress)
    # This function checks if the provided IP address matches the standard IPv4 format.
    # If the format is invalid, it displays an error message and terminates the script.
    if ($IPAddress -notmatch '^(\d{1,3}\.){3}\d{1,3}$') {
        Write-Host "Invalid IP address format: $IPAddress" -ForegroundColor Red
        exit
    }
}

# Validate user inputs
# Ensure the provided static IP, DHCP range, and default gateway follow the correct IPv4 format.
Validate-IP $StaticIP
Validate-IP $DHCPStartIP
Validate-IP $DHCPEndIP
Validate-IP $DefaultGateway

# Check if the subnet mask is in the correct IPv4 format.
# Subnet masks must also follow the same dotted-decimal notation as IP addresses.
if ($SubnetMask -notmatch '^(\d{1,3}\.){3}\d{1,3}$') {
    Write-Host "Invalid subnet mask format: $SubnetMask" -ForegroundColor Red
    exit
}

# AD Installation
Write-Host "Installing Active Directory Domain Services..."
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# Import the ADDSDeployment module for domain configuration
Import-Module ADDSDeployment

Write-Host "Promoting the server to a domain controller..."
try {
    Install-ADDSForest -DomainName "$DomainName" -DomainNetbiosName "$DomainNetbiosName" -SafeModeAdministratorPassword (ConvertTo-SecureString "P@ssw0rd!" -AsPlainText -Force) -NoRebootOnCompletion -Force
    Write-Host "Domain controller promotion completed successfully."
} catch {
    Write-Host "Error during domain controller promotion: $_" -ForegroundColor Red
    exit
}

# DHCP Installation
Write-Host "Installing DHCP Server..."
$dhcpInstallResult = Install-WindowsFeature -Name DHCP -IncludeManagementTools
if ($dhcpInstallResult.Success -eq $false) {
    Write-Host "Failed to install DHCP Server. Exiting script." -ForegroundColor Red
    exit
}

Write-Host "Configuring DHCP scope..."
try {
    Add-DhcpServerv4Scope -Name "DefaultScope" -StartRange $DHCPStartIP -EndRange $DHCPEndIP -SubnetMask $SubnetMask -State Active
    Set-DhcpServerv4OptionValue -OptionId 3 -Value $DefaultGateway
    Write-Host "DHCP scope configured successfully."
} catch {
    Write-Host "Error configuring DHCP scope: $_" -ForegroundColor Red
    exit
}

# DNS Configuration
Write-Host "Setting up DNS server..."
# Create a forward lookup zone for the domain
Add-DnsServerPrimaryZone -Name $DomainName
# Add an A record for the server in the forward lookup zone
Add-DnsServerResourceRecordA -Name $ServerName -ZoneName $DomainName -IPv4Address $StaticIP

# Reverse Lookup Zone Configuration
Write-Host "Setting up reverse lookup zone..."
try {
    # Calculate the reverse network ID from the static IP address
    $ReverseNetworkId = ($StaticIP -split '\.')[0..2] -join '.'
    # Create a reverse lookup zone for the calculated network ID
    Add-DnsServerPrimaryZone -NetworkId "$ReverseNetworkId"
    Write-Host "Reverse lookup zone configured successfully."
} catch {
    Write-Host "Error setting up reverse lookup zone: $_" -ForegroundColor Red
    exit
}

if ($RestartResponse -eq "Y" -or $RestartResponse -eq "y") {
    Write-Host "Restarting the server..."
    Restart-Computer -Force
} else {
    Write-Host "Script execution completed. No restart will be performed."
}