Write-Host "Starting Windows Server 2022 full deployment..."


# Registry key to track deployment phase
$PhaseRegKey = "HKLM:\SOFTWARE\Autodeploy\ServerDeployment"
# Path for auto-run on startup
$RunKeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
# Name of the registry key for auto-run
$RunKeyName = "Deployment"
# Path to this script for auto-run
$ScriptPath = "C:\Scripts\server.ps1"

# Create key if not there
if (-not (Test-Path $PhaseRegKey)) {
    New-Item -Path $PhaseRegKey -Force | Out-Null
    Set-ItemProperty -Path $PhaseRegKey -Name SetupPhase -Value "Init"
}

# Get phase
$Phase = Get-ItemPropertyValue -Path $PhaseRegKey -Name SetupPhase -ErrorAction SilentlyContinue

# Save next phase and reboot
function Next-Phase($Next) {
    Set-ItemProperty -Path $PhaseRegKey -Name SetupPhase -Value $Next
    Restart-Computer -Force
}

# Set script to run at startup
if (-not (Get-ItemProperty -Path $RunKeyPath -Name $RunKeyName -ErrorAction SilentlyContinue)) {
    Set-ItemProperty -Path $RunKeyPath -Name $RunKeyName -Value "powershell.exe -ExecutionPolicy Bypass -NoProfile -File `\"$ScriptPath`\""
}


switch ($Phase) {





    "Init" {
        Write-Host "\n========== Installing Roles =========="

        # Install needed roles
        Install-WindowsFeature -Name AD-Domain-Services, DNS, DHCP -IncludeManagementTools -ErrorAction Stop

        Next-Phase "Promote"
    }





    "Promote" {
        Write-Host "\n========== AD Configuration =========="

        # Ask for domain info
        $DomainName = Read-Host "What should the domain name be? (e.g., home.arpa.local)"
        $DomainNetbiosName = Read-Host "What should the domain NetBIOS name be? (e.g., HOME, CORP)"
        $DSRMPassword = Read-Host "What should the Directory Services Restore Mode (DSRM) password be?" -AsSecureString

        # Save values for next steps
        Set-ItemProperty -Path $PhaseRegKey -Name DomainName -Value $DomainName
        Set-ItemProperty -Path $PhaseRegKey -Name DomainNetbiosName -Value $DomainNetbiosName
        Set-ItemProperty -Path $PhaseRegKey -Name DSRMPassword -Value ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($DSRMPassword)))

        # Promote to domain controller
        Install-ADDSForest -DomainName $DomainName -DomainNetbiosName $DomainNetbiosName -SafeModeAdministratorPassword $DSRMPassword -InstallDNS -Force -NoRebootOnCompletion

        Next-Phase "DNSConfig"
    }





    "DNSConfig" {
        Write-Host "\n========== DNS Configuration =========="

        # Load DNS module
        Import-Module DnsServer -ErrorAction Stop

        # Get saved info
        $DomainName = Get-ItemPropertyValue -Path $PhaseRegKey -Name DomainName
        $DomainNetbiosName = Get-ItemPropertyValue -Path $PhaseRegKey -Name DomainNetbiosName

        # Ask for DNS info
        $ReverseLookupZoneNetworkID = Read-Host "What should the reverse lookup zone network ID be? (e.g., 192.168.1.0)"
        $ServerName = Read-Host "What should the server name be? (e.g., SRV-1)"
        $StaticIP = Read-Host "What should the static IP address for the server be?"

        # Save info for DHCP
        Set-ItemProperty -Path $PhaseRegKey -Name ReverseLookupZoneNetworkID -Value $ReverseLookupZoneNetworkID
        Set-ItemProperty -Path $PhaseRegKey -Name ServerName -Value $ServerName
        Set-ItemProperty -Path $PhaseRegKey -Name StaticIP -Value $StaticIP

        # Forward zone
        Write-Host "Setting up forward DNS zone..."
        if (-not (Get-DnsServerZone -Name $DomainName -ErrorAction SilentlyContinue)) {
            Add-DnsServerPrimaryZone -Name $DomainName -ReplicationScope Domain -DynamicUpdate Secure
        }

        # A record
        Write-Host "Adding A record for this server..."
        Add-DnsServerResourceRecordA -Name $ServerName -ZoneName $DomainName -IPv4Address $StaticIP

        # Reverse zone
        Write-Host "Setting up reverse DNS zone..."
        $Octets = $ReverseLookupZoneNetworkID -split '\.'
        $ReverseZoneName = "$($Octets[2]).$($Octets[1]).$($Octets[0]).in-addr.arpa"

        if (-not (Get-DnsServerZone -Name $ReverseZoneName -ErrorAction SilentlyContinue)) {
            Add-DnsServerPrimaryZone -NetworkID $ReverseLookupZoneNetworkID -ReplicationScope Domain -DynamicUpdate Secure
        }

        # PTR record
        Write-Host "Adding PTR record for this server..."
        $LastOctet = ($StaticIP -split '\.')[3]
        Add-DnsServerResourceRecordPtr -Name $LastOctet -ZoneName $ReverseZoneName -PtrDomainName "$ServerName.$DomainName"

        Next-Phase "DHCPConfig"
    }





    "DHCPConfig" {
        Write-Host "\n========== DHCP Configuration =========="

        # Ask for DHCP info
        $DHCPStartIP = Read-Host "What should the DHCP lease range start address be?"
        $DHCPEndIP = Read-Host "What should the DHCP lease range end address be?"
        $SubnetMask = Read-Host "What should the subnet mask be?"
        $DefaultGateway = Read-Host "What should the default gateway be?"

        # Add scope
        Write-Host "Configuring DHCP scope..."
        if (-not (Get-DhcpServerv4Scope -ScopeId $DHCPStartIP -ErrorAction SilentlyContinue)) {
            Add-DhcpServerv4Scope -Name "DefaultScope" -StartRange $DHCPStartIP -EndRange $DHCPEndIP -SubnetMask $SubnetMask -State Active
        }

        # Set gateway option
        Set-DhcpServerv4OptionValue -OptionId 3 -Value $DefaultGateway

        Write-Host "\n========== Finished =========="

        # Clean up registry
        Remove-ItemProperty -Path $RunKeyPath -Name $RunKeyName -ErrorAction SilentlyContinue
        Remove-Item -Path $PhaseRegKey -Recurse -Force -ErrorAction SilentlyContinue
    }





    default {
        Write-Host "❌ Unknown phase. Exiting..." -ForegroundColor Red
        exit 1
    }
}
