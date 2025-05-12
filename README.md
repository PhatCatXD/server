# Win-server-2022

This PowerShell script sets up **DHCP**, **DNS**, and an **Active Directory Forest** on a clean install of **Windows Server 2022**.

## ⚠️ Requirements
- Must be run in an **elevated PowerShell window (Run as Administrator)**
- Designed for a **fresh Windows Server 2022 installation**
- Script is **interactive** and will prompt for domain, IP, and network configuration
- Some post-configuration (like joining clients to the domain) must be done manually

## 🚀 Run the Script

You can run this script directly from PowerShell without downloading it manually:

# "the script"
```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process -Force
iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/FatCat112/Win-server-2022/main/Win-server-2022.ps1'))
```


post execution audit log
```powershell
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/FatCat112/Win-server-2022/refs/heads/main/Post-execution-audit-log.ps1' -OutFile Desktop\'))
```
