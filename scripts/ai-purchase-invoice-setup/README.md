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

Modern 64-bit Ryzen laptops can run this setup if virtualization is enabled. This
installer does not configure GPU acceleration, so Ollama may run on the CPU and
invoice extraction can be slow; 8 GB RAM is not recommended.

## Get the setup package

Clone the feature branch and open the installer folder:

```powershell
git clone --branch feature/ai-purchase-invoice-draft https://github.com/Ali-Burhan/erpnext.git erpnext-ai
cd .\erpnext-ai\scripts\ai-purchase-invoice-setup
```

Alternatively, download and extract the branch ZIP from GitHub, then open
`scripts\ai-purchase-invoice-setup` in PowerShell.

## Install (no setup questions)

Keep the files in this folder together, then double-click `Install-AI-ERPNext.bat`.

The installer chooses defaults, sets up WSL2, installs ERPNext, Ollama, and
`qwen2:7b`, builds the site, then starts ERPNext and opens the browser. Windows may
request administrator approval when enabling WSL, and may require a restart. Those
operating-system steps cannot be skipped by an application script. The first install
downloads several gigabytes and can take a long time; keep the computer plugged in
and leave the installer window open.

For this demo installer, `786786` is used for the Linux account, MariaDB root, and
ERPNext Administrator. The password is saved in
`%LOCALAPPDATA%\AI-ERPNext\credentials.txt`. This password is intentionally weak:
use this only for a disposable local demo, never a production or internet-exposed
instance.

The installer also installs Tesseract for scanned invoice OCR, configures Ollama for
the site, migrates the database, and builds ERPNext assets.

## Start the application and model

After installation, keep the ERPNext terminal window open. To start the services
manually later, run:

```powershell
wsl -d Ubuntu-24.04 -u frappe -- bash -lc 'cd ~/erpnext/frappe-bench && ./start-ai-erpnext.sh'
```

Keep that terminal open. Open the site name selected during setup at
`http://<site-name>:8000`. Press Ctrl+C in the terminal to stop Bench; Ollama remains
managed by systemd inside WSL and can be started again by the same launcher.

## Setup files

- `setup-windows-ai.ps1` is the no-input Windows/WSL installer and launcher.
- `Install-AI-ERPNext.bat` starts the installer by double-click.
- `setup-frappe.sh` installs Bench, the selected app branches, Ollama, and the model.
- `start-ai-erpnext.sh` starts Ollama if needed, verifies the configured model, and
  runs `bench start`.

The ERPNext submit action posts accounting entries. Test with fictional invoices and
review all extracted values before using it on real supplier invoices.
