# =============================
# Windows Server 2022 Deployment Script (Full Auto Mode)
# =============================

Write-Host "Starting Windows Server 2022 full deployment..." -ForegroundColor Cyan




# =============================
# Path + Elevation Check
# =============================

# Relaunch as admin if not already elevated
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole("Administrator")) {
    Start-Process powershell.exe "-ExecutionPolicy Bypass -NoProfile -File `\"$PSCommandPath`\"" -Verb RunAs
    exit
}

$ScriptPath  = $MyInvocation.MyCommand.Path
$PhaseRegKey = "HKLM:\SOFTWARE\Autodeploy\ServerDeployment"
$RunKeyPath  = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$RunKeyName  = "Deployment"




# =============================
# Phase Checkpoint System
# =============================

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

# Ensure script auto-runs after reboot
if (-not (Get-ItemProperty -Path $RunKeyPath -Name $RunKeyName -ErrorAction SilentlyContinue)) {
    $escapedScriptPath = "`"$ScriptPath`""
    $command = "powershell -ExecutionPolicy Bypass -File $escapedScriptPath"
    Set-ItemProperty -Path $RunKeyPath -Name $RunKeyName -Value $command
}





# =============================
# Collect User Input (One-Time)
# =============================

function Collect-UserInput {
    Write-Host "`n========== Collecting User Input ==========" -ForegroundColor Yellow

    $DomainName        = Read-Host "Domain name (e.g., home.arpa.local)"
    $DomainNetbiosName = Read-Host "NetBIOS name (e.g., HOME)"
    $DSRMPassword      = Read-Host "DSRM password" -AsSecureString
    $ReverseLookup     = Read-Host "Reverse lookup zone (e.g., 192.168.1.0)"
    $ServerName        = Read-Host "Server name (e.g., SRV-1)"
    $StaticIP          = Read-Host "Static IP address for this server"
    $DHCPStartIP       = Read-Host "DHCP range start"
    $DHCPEndIP         = Read-Host "DHCP range end"
    $SubnetMask        = Read-Host "Subnet mask"
    $DefaultGateway    = Read-Host "Default gateway"

    # Optional auto-login setup
    $AutoLoginPassword = Read-Host "To enable auto-login after reboot, enter current user's password" -AsSecureString
    $AutoLoginPlain    = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AutoLoginPassword)
    )

    # Save all values
    Set-ItemProperty -Path $PhaseRegKey -Name DomainName        -Value $DomainName
    Set-ItemProperty -Path $PhaseRegKey -Name DomainNetbiosName -Value $DomainNetbiosName
    Set-ItemProperty -Path $PhaseRegKey -Name DSRMPassword      -Value ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($DSRMPassword)))
    Set-ItemProperty -Path $PhaseRegKey -Name ReverseLookupZoneNetworkID -Value $ReverseLookup
    Set-ItemProperty -Path $PhaseRegKey -Name ServerName        -Value $ServerName
    Set-ItemProperty -Path $PhaseRegKey -Name StaticIP          -Value $StaticIP
    Set-ItemProperty -Path $PhaseRegKey -Name DHCPStartIP       -Value $DHCPStartIP
    Set-ItemProperty -Path $PhaseRegKey -Name DHCPEndIP         -Value $DHCPEndIP
    Set-ItemProperty -Path $PhaseRegKey -Name SubnetMask        -Value $SubnetMask
    Set-ItemProperty -Path $PhaseRegKey -Name DefaultGateway    -Value $DefaultGateway

    # Enable auto-login
    Write-Host "`nEnabling temporary auto-login for '$env:USERNAME'..." -ForegroundColor DarkCyan
    $WinlogonKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty -Path $WinlogonKey -Name "AutoAdminLogon"    -Value "1"
    Set-ItemProperty -Path $WinlogonKey -Name "DefaultUsername"   -Value $env:USERNAME
    Set-ItemProperty -Path $WinlogonKey -Name "DefaultDomainName" -Value $env:USERDOMAIN
    Set-ItemProperty -Path $WinlogonKey -Name "DefaultPassword"   -Value $AutoLoginPlain

    Set-PhaseCheckpoint "InstallRoles"
}




# =============================
# Role Installation
# =============================

function Install-Roles {
    Write-Host "`n========== Installing Roles ==========" -ForegroundColor Yellow
    Install-WindowsFeature -Name AD-Domain-Services, DNS, DHCP -IncludeManagementTools -ErrorAction Stop
    Set-PhaseCheckpoint "Promote"
}




# =============================
# AD Configuration
# =============================

function Configure-AD {
    Write-Host "`n========== AD Configuration ==========" -ForegroundColor Yellow

    $DomainName        = Get-ItemPropertyValue -Path $PhaseRegKey -Name DomainName
    $DomainNetbiosName = Get-ItemPropertyValue -Path $PhaseRegKey -Name DomainNetbiosName
    $DSRMPasswordPlain = Get-ItemPropertyValue -Path $PhaseRegKey -Name DSRMPassword
    $DSRMPassword      = ConvertTo-SecureString $DSRMPasswordPlain -AsPlainText -Force

    Install-ADDSForest -DomainName $DomainName -DomainNetbiosName $DomainNetbiosName -SafeModeAdministratorPassword $DSRMPassword -InstallDNS -Force -NoRebootOnCompletion

    Set-PhaseCheckpoint "DNSConfig"
}




# =============================
# DNS Configuration
# =============================

function Configure-DNS {
    Write-Host "`n========== DNS Configuration ==========" -ForegroundColor Yellow

    Import-Module DnsServer -ErrorAction Stop

    $DomainName   = Get-ItemPropertyValue -Path $PhaseRegKey -Name DomainName
    $ReverseNetID = Get-ItemPropertyValue -Path $PhaseRegKey -Name ReverseLookupZoneNetworkID
    $ServerName   = Get-ItemPropertyValue -Path $PhaseRegKey -Name ServerName
    $StaticIP     = Get-ItemPropertyValue -Path $PhaseRegKey -Name StaticIP

    if (-not (Get-DnsServerZone -Name $DomainName -ErrorAction SilentlyContinue)) {
        Add-DnsServerPrimaryZone -Name $DomainName -ReplicationScope Domain -DynamicUpdate Secure
    }

    Add-DnsServerResourceRecordA -Name $ServerName -ZoneName $DomainName -IPv4Address $StaticIP

    $Octets = $ReverseNetID -split '\.'
    $ReverseZoneName = "$($Octets[2]).$($Octets[1]).$($Octets[0]).in-addr.arpa"

    if (-not (Get-DnsServerZone -Name $ReverseZoneName -ErrorAction SilentlyContinue)) {
        Add-DnsServerPrimaryZone -NetworkID $ReverseNetID -ReplicationScope Domain -DynamicUpdate Secure
    }

    $LastOctet = ($StaticIP -split '\.')[3]
    Add-DnsServerResourceRecordPtr -Name $LastOctet -ZoneName $ReverseZoneName -PtrDomainName "$ServerName.$DomainName"

    Set-PhaseCheckpoint "DHCPConfig"
}




# =============================
# DHCP Configuration + Cleanup
# =============================

function Configure-DHCP {
    Write-Host "`n========== DHCP Configuration ==========" -ForegroundColor Yellow

    $DHCPStartIP    = Get-ItemPropertyValue -Path $PhaseRegKey -Name DHCPStartIP
    $DHCPEndIP      = Get-ItemPropertyValue -Path $PhaseRegKey -Name DHCPEndIP
    $SubnetMask     = Get-ItemPropertyValue -Path $PhaseRegKey -Name SubnetMask
    $DefaultGateway = Get-ItemPropertyValue -Path $PhaseRegKey -Name DefaultGateway

    if (-not (Get-DhcpServerv4Scope -ScopeId $DHCPStartIP -ErrorAction SilentlyContinue)) {
        Add-DhcpServerv4Scope -Name "DefaultScope" -StartRange $DHCPStartIP -EndRange $DHCPEndIP -SubnetMask $SubnetMask -State Active
    }

    Set-DhcpServerv4OptionValue -OptionId 3 -Value $DefaultGateway

    Write-Host "`n========== Finished ==========" -ForegroundColor Green

    # Cleanup Run key + deployment data
    Remove-ItemProperty -Path $RunKeyPath -Name $RunKeyName -ErrorAction SilentlyContinue
    Remove-Item -Path $PhaseRegKey -Recurse -Force -ErrorAction SilentlyContinue

    # Disable auto-login
    Write-Host "`nDisabling temporary auto-login for security..." -ForegroundColor DarkCyan
    $WinlogonKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Remove-ItemProperty -Path $WinlogonKey -Name "DefaultPassword" -ErrorAction SilentlyContinue
    Set-ItemProperty    -Path $WinlogonKey -Name "AutoAdminLogon" -Value "0"
}




# =============================
# Phase Dispatcher
# =============================

switch ($Phase) {
    "Init"          { Collect-UserInput }
    "InstallRoles"  { Install-Roles }
    "Promote"       { Configure-AD }
    "DNSConfig"     { Configure-DNS }
    "DHCPConfig"    { Configure-DHCP }
    default         { Write-Host "`n❌ Unknown phase. Exiting..." -ForegroundColor Red; exit 1 }
}
