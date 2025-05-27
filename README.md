# 🛠️ Windows Server 2022 Auto-Deployment Script

This repository contains a PowerShell automation script for deploying a fully functional Windows Server 2022 environment. It configures and installs:

- ✅ Active Directory Domain Services (AD DS)
- ✅ Domain promotion
- ✅ DNS Server
- ✅ DHCP Server
- ✅ Post-installation auditing

The script is designed to run in phases across reboots using a registry checkpoint system.

---

## 📦 Features

- Automatic installation of required Windows Server roles and features
- Domain creation and promotion to Domain Controller
- DNS zone and reverse zone configuration
- DHCP scope setup with automatic lease and option setup
- Auto-resume after reboot using PowerShell and registry tracking
- Post-deployment audit script to verify services

---

## ⚙️ Prerequisites

- Windows Server 2022 (GUI or Core)
- Administrator privileges
- Internet access (to download script remotely if using `iex`)
- Execution policy set to allow script execution

---

## 🚀 Quick Start

You can run the full script using this one-liner:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process -Force
iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/PhatCatXD/server/main/Win-server-2022.ps1'))
