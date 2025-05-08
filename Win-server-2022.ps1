Write-Host "Starting Windows Server 2022 full deployment..."


# Check for administrative privileges to ensure script has the necessary rights
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "You must run this script as Administrator." -ForegroundColor Red
    exit
}



# Prompt for user input to configure domain, network, and DHCP details
$DomainName = Read-Host "What should the domain name be? (e.g., home.arpa.local)"
$DomainNetbiosName = Read-Host "What should the domain NetBIOS name be?"
$DSRMPassword = Read-Host "What should the Directory Services Restore Mode (DSRM) password be?" -AsSecureString
$ReverseLookupZoneNetworkID = Read-Host "What should the reverse lookup zone network ID be? (e.g., 192.168.1.0)"
$ServerName = Read-Host "What should the server name be? (e.g., SRV-1)"
$StaticIP = Read-Host "What should the static IP address for the server be?"
$DHCPStartIP = Read-Host "What should the DHCP lease range start address be?"
$DHCPEndIP = Read-Host "What should the DHCP lease range end address be?"
$SubnetMask = Read-Host "What should the subnet mask be?"
$DefaultGateway = Read-Host "What should the default gateway be?"
$RestartResponse = Read-Host "Do you want to restart after script execution? (Y/N)"











Write-Host "`n========== AD Configuration =========="

try {
    # Install the Active Directory Domain Services role
    Write-Host "Installing Active Directory Domain Services..."
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop

    # Import the AD deployment module
    Import-Module ADDSDeployment -ErrorAction Stop

    # Promote this server to a domain controller and create a new forest
    Write-Host "Promoting the server to a domain controller..."
    Install-ADDSForest -DomainName "$DomainName" -DomainNetbiosName "$DomainNetbiosName" -SafeModeAdministratorPassword $DSRMPassword -NoRebootOnCompletion -Force -ErrorAction Stop
}
catch {
    # Stop script if AD setup fails
    Write-Host "❌ AD DS installation or promotion failed: $($_.Exception.Message)" -ForegroundColor Red
    exit
}










Write-Host "`n========== DNS Configuration =========="

try {
    # Create the forward DNS zone if it doesn't already exist
    Write-Host "Setting up forward DNS zone..."
    if (-not (Get-DnsServerZone -Name $DomainName -ErrorAction SilentlyContinue)) {
        Add-DnsServerPrimaryZone -Name $DomainName -ReplicationScope Domain -DynamicUpdate Secure -ErrorAction Stop
    }

    # Add an A record for the server in the forward zone
    Write-Host "Adding A record for this server..."
    Add-DnsServerResourceRecordA -Name $ServerName -ZoneName $DomainName -IPv4Address $StaticIP -ErrorAction Stop

    # Check for existing reverse DNS zone and create it if needed
    Write-Host "Setting up reverse DNS zone..."
    $ReverseZoneCheck = "$($ReverseLookupZoneNetworkID -replace '\.0$', '').in-addr.arpa"
    if (-not (Get-DnsServerZone -Name $ReverseZoneCheck -ErrorAction SilentlyContinue)) {
        Add-DnsServerPrimaryZone -NetworkID $ReverseLookupZoneNetworkID -ReplicationScope Domain -DynamicUpdate Secure -ErrorAction Stop
    }

    # Add a PTR record for the server for reverse DNS lookups
    Write-Host "Adding PTR record for this server..."
    $IPParts = $StaticIP -split '\.'
    $LastOctet = $IPParts[3]
    $ReverseZoneName = "$($IPParts[2]).$($IPParts[1]).$($IPParts[0])"
    Add-DnsServerResourceRecordPtr -Name $LastOctet -ZoneName "$ReverseZoneName.in-addr.arpa" -PtrDomainName "$ServerName.$DomainName" -ErrorAction Stop

    # Verify that the PTR record is resolvable
    Write-Host "Validating PTR record..."
    Resolve-DnsName -Name $StaticIP -Type PTR
}
catch {
    # Stop script if DNS configuration fails
    Write-Host "❌ DNS setup failed: $($_.Exception.Message)" -ForegroundColor Red
    exit
}












Write-Host "`n========== DHCP Configuration =========="

try {
    # Install the DHCP Server role
    Write-Host "Installing DHCP Server..."
    Install-WindowsFeature -Name DHCP -IncludeManagementTools -ErrorAction Stop

    # Configure a new DHCP scope if one doesn't already exist
    Write-Host "Configuring DHCP scope..."
    if (-not (Get-DhcpServerv4Scope -ScopeId $DHCPStartIP -ErrorAction SilentlyContinue)) {
        Add-DhcpServerv4Scope -Name "DefaultScope" -StartRange $DHCPStartIP -EndRange $DHCPEndIP -SubnetMask $SubnetMask -State Active -ErrorAction Stop
    }

    # Set default gateway (option 3) for DHCP clients
    Set-DhcpServerv4OptionValue -OptionId 3 -Value $DefaultGateway -ErrorAction Stop
    Write-Host "DHCP scope configured successfully."
}
catch {
    # Stop script if DHCP setup fails
    Write-Host "❌ DHCP setup failed: $($_.Exception.Message)" -ForegroundColor Red
    exit
}













# Write a timestamped completion log entry
"Deployment completed at $(Get-Date)" | Out-File -FilePath C:\DeploymentLog.txt -Append







Write-Host "`n========== Finished =========="







# Restart if the user chose to
if ($RestartResponse -eq "Y" -or $RestartResponse -eq "y") {
    Write-Host "Restarting the server..."
    Restart-Computer -Force
} else {
    Write-Host "Script execution completed. No restart will be performed."
}
