# AI Purchase Invoice development setup (Windows + WSL2)

This package installs a local development environment, not a production ERPNext
deployment. It uses Ubuntu in WSL2, Frappe `version-16`, the
`feature/ai-purchase-invoice-draft` ERPNext branch, and Ollama with `qwen2:7b`.
Ollama and its model are installed inside WSL so the Bench can reach them at
`127.0.0.1` without exposing the Ollama API on the Windows network.

## Requirements

- 64-bit Windows 10/11 with WSL2 support and virtualization enabled.
- Internet access and administrator permission when Windows requests it.
- Git for Windows, if cloning the branch with the commands below.
- Several GB of free disk space for the Bench and the approximately 4.4 GB model.
- Enough available memory to run a 7B model; 16 GB system RAM is recommended.
- Allow time for Ubuntu, dependencies, ERPNext assets, and the model to download.

## Get the setup package

Clone the feature branch and open the installer folder:

```powershell
git clone --branch feature/ai-purchase-invoice-draft https://github.com/Ali-Burhan/erpnext.git erpnext-ai
cd .\erpnext-ai\scripts\ai-purchase-invoice-setup
```

Alternatively, download and extract the branch ZIP from GitHub, then open
`scripts\ai-purchase-invoice-setup` in PowerShell.

## Install

From PowerShell in this folder, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1
```

The script asks for a Linux-user password, site name, MariaDB root password, and
ERPNext Administrator password. Keep those credentials private. The setup installs
Tesseract for scanned invoice OCR, configures Ollama for the site, migrates it, and
builds ERPNext assets.

For options such as a different WSL distro or model:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1 -Distro Ubuntu-24.04 -OllamaModel qwen2:7b
```

## Start the application and model

The installer prints a command using the selected distro and Linux user. The default
command is:

```powershell
wsl -d Ubuntu-24.04 -u frappe -- bash -lc 'cd ~/erpnext/frappe-bench && ./start-ai-erpnext.sh'
```

Keep that terminal open. Open the site name selected during setup at
`http://<site-name>:8000`. Press Ctrl+C in the terminal to stop Bench; Ollama remains
managed by systemd inside WSL and can be started again by the same launcher.

## Setup files

- `setup-windows.ps1` provisions WSL and launches the Linux installer.
- `setup-frappe.sh` installs Bench, the selected app branches, Ollama, and the model.
- `start-ai-erpnext.sh` starts Ollama if needed, verifies the configured model, and
  runs `bench start`.

The ERPNext submit action posts accounting entries. Test with fictional invoices and
review all extracted values before using it on real supplier invoices.
