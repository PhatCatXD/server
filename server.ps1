# =============================
# Windows Server 2022 Deployment Script
# =============================

Write-Host "Starting Windows Server 2022 full deployment..."

$PhaseRegKey = "HKLM:\SOFTWARE\Autodeploy\ServerDeployment"
$RunKeyPath  = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$RunKeyName  = "Deployment"
$ScriptPath  = "C:\Scripts\server.ps1"


# Save next phase and reboot
function Set-PhaseCheckpoint {
    param([string]$NextPhase)
    Set-ItemProperty -Path $PhaseRegKey -Name SetupPhase -Value $NextPhase
    Restart-Computer -Force
}


# Create phase registry key on first run
if (-not (Test-Path $PhaseRegKey)) {
    New-Item -Path $PhaseRegKey -Force | Out-Null
    Set-ItemProperty -Path $PhaseRegKey -Name SetupPhase -Value "Init"
}

$Phase = Get-ItemPropertyValue -Path $PhaseRegKey -Name SetupPhase -ErrorAction SilentlyContinue


# Ensure script auto-runs at startup
if (-not (Get-ItemProperty -Path $RunKeyPath -Name $RunKeyName -ErrorAction SilentlyContinue)) {
    Set-ItemProperty -Path $RunKeyPath -Name $RunKeyName -Value "powershell.exe -ExecutionPolicy Bypass -NoProfile -File `\"$ScriptPath`\""
}


# ========= Phase Functions =========

function Install-Roles {
    Write-Host "\n========== Installing Roles =========="
    Install-WindowsFeature -Name AD-Domain-Services, DNS, DHCP -IncludeManagementTools -ErrorAction Stop
    Set-PhaseCheckpoint "Promote"
}


function Configure-AD {
    Write-Host "\n========== AD Configuration =========="

    $DomainName = Read-Host "What should the domain name be? (e.g., home.arpa.local)"
    $DomainNetbiosName = Read-Host "What should the domain NetBIOS name be? (e.g., HOME, CORP)"
    $DSRMPassword = Read-Host "What should the Directory Services Restore Mode (DSRM) password be?" -AsSecureString

    Set-ItemProperty -Path $PhaseRegKey -Name DomainName -Value $DomainName
    Set-ItemProperty -Path $PhaseRegKey -Name DomainNetbiosName -Value $DomainNetbiosName
    Set-ItemProperty -Path $PhaseRegKey -Name DSRMPassword -Value ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($DSRMPassword)))

    Install-ADDSForest -DomainName $DomainName -DomainNetbiosName $DomainNetbiosName -SafeModeAdministratorPassword $DSRMPassword -InstallDNS -Force -NoRebootOnCompletion

    Set-PhaseCheckpoint "DNSConfig"
}


function Configure-DNS {
    Write-Host "\n========== DNS Configuration =========="

    Import-Module DnsServer -ErrorAction Stop

    $DomainName = Get-ItemPropertyValue -Path $PhaseRegKey -Name DomainName
    $DomainNetbiosName = Get-ItemPropertyValue -Path $PhaseRegKey -Name DomainNetbiosName

    $ReverseLookupZoneNetworkID = Read-Host "What should the reverse lookup zone network ID be? (e.g., 192.168.1.0)"
    $ServerName = Read-Host "What should the server name be? (e.g., SRV-1)"
    $StaticIP = Read-Host "What should the static IP address for the server be?"

    Set-ItemProperty -Path $PhaseRegKey -Name ReverseLookupZoneNetworkID -Value $ReverseLookupZoneNetworkID
    Set-ItemProperty -Path $PhaseRegKey -Name ServerName -Value $ServerName
    Set-ItemProperty -Path $PhaseRegKey -Name StaticIP -Value $StaticIP

    if (-not (Get-DnsServerZone -Name $DomainName -ErrorAction SilentlyContinue)) {
        Add-DnsServerPrimaryZone -Name $DomainName -ReplicationScope Domain -DynamicUpdate Secure
    }

    Add-DnsServerResourceRecordA -Name $ServerName -ZoneName $DomainName -IPv4Address $StaticIP

    $Octets = $ReverseLookupZoneNetworkID -split '\.'
    $ReverseZoneName = "$($Octets[2]).$($Octets[1]).$($Octets[0]).in-addr.arpa"

    if (-not (Get-DnsServerZone -Name $ReverseZoneName -ErrorAction SilentlyContinue)) {
        Add-DnsServerPrimaryZone -NetworkID $ReverseLookupZoneNetworkID -ReplicationScope Domain -DynamicUpdate Secure
    }

    $LastOctet = ($StaticIP -split '\.')[3]
    Add-DnsServerResourceRecordPtr -Name $LastOctet -ZoneName $ReverseZoneName -PtrDomainName "$ServerName.$DomainName"

    Set-PhaseCheckpoint "DHCPConfig"
}


function Configure-DHCP {
    Write-Host "\n========== DHCP Configuration =========="

    $DHCPStartIP = Read-Host "What should the DHCP lease range start address be?"
    $DHCPEndIP = Read-Host "What should the DHCP lease range end address be?"
    $SubnetMask = Read-Host "What should the subnet mask be?"
    $DefaultGateway = Read-Host "What should the default gateway be?"

    if (-not (Get-DhcpServerv4Scope -ScopeId $DHCPStartIP -ErrorAction SilentlyContinue)) {
        Add-DhcpServerv4Scope -Name "DefaultScope" -StartRange $DHCPStartIP -EndRange $DHCPEndIP -SubnetMask $SubnetMask -State Active
    }

    Set-DhcpServerv4OptionValue -OptionId 3 -Value $DefaultGateway

    Write-Host "\n========== Finished =========="

    Remove-ItemProperty -Path $RunKeyPath -Name $RunKeyName -ErrorAction SilentlyContinue
    Remove-Item -Path $PhaseRegKey -Recurse -Force -ErrorAction SilentlyContinue
}


# ========= Phase Dispatcher =========

switch ($Phase) {
    "Init"        { Install-Roles }
    "Promote"     { Configure-AD }
    "DNSConfig"   { Configure-DNS }
    "DHCPConfig"  { Configure-DHCP }
    default       { Write-Host "\n❌ Unknown phase. Exiting..." -ForegroundColor Red; exit 1 }
}