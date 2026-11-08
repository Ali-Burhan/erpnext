<#
 setup-windows.ps1 - installs Ubuntu on WSL2 (if missing), creates a Linux user,
 copies the setup and startup scripts into it, and installs ERPNext + Ollama.

 Put this file in the SAME folder as setup-frappe.sh, then in PowerShell:

     powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1

 Options:
     -Distro         WSL distro name         (default Ubuntu-24.04)
     -LinuxUser      Linux username to use   (default frappe)
     -ProjectFolder  folder in the Linux home (default erpnext)
     -FrappeBranch   Frappe branch            (default version-16)
     -ErpnextBranch ERPNext branch            (default AI feature branch)
     -OllamaModel   Ollama model              (default qwen2:7b)

 Example:
     powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1 -Distro Ubuntu

 Safe to re-run: every step is skipped if it is already done.
 If Windows asks for a restart during the WSL install, restart and run it again.
#>
param(
  [string]$Distro = "Ubuntu-24.04",
  [string]$LinuxUser = "frappe",
  [string]$ProjectFolder = "erpnext",
  [string]$FrappeBranch = "version-16",
  [string]$ErpnextBranch = "feature/ai-purchase-invoice-draft",
  [string]$OllamaModel = "qwen2:7b"
)

function Step($m) { Write-Host ""; Write-Host "==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "!!  $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "xx  $m" -ForegroundColor Red; exit 1 }

function Get-WslDistros {
  $prev = [Console]::OutputEncoding
  [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
  $list = @(wsl.exe -l -q 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  [Console]::OutputEncoding = $prev
  return $list
}

function To-B64($text) {
  return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))
}

# ------------------------------------------------------------ preflight
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  Fail "wsl.exe not found. Use Windows 10 (2004+) or Windows 11, or enable WSL first."
}

foreach ($value in @($LinuxUser, $FrappeBranch, $ErpnextBranch, $OllamaModel)) {
  if ($value -notmatch '^[A-Za-z0-9._:/-]+$') {
    Fail "Invalid setup value '$value'. Use only letters, numbers, dot, underscore, colon, slash, or hyphen."
  }
}
if ($ProjectFolder -notmatch '^[A-Za-z0-9._-]+$' -or $ProjectFolder -in @(".", "..")) {
  Fail "Invalid project folder '$ProjectFolder'. Use a single folder name without path separators."
}

$setupScript = Join-Path $PSScriptRoot "setup-frappe.sh"
$startScript = Join-Path $PSScriptRoot "start-ai-erpnext.sh"
if (-not (Test-Path $setupScript) -or -not (Test-Path $startScript)) {
  Fail "setup-frappe.sh and start-ai-erpnext.sh must be in the same folder as this launcher."
}
Write-Host "Using $setupScript"

# ------------------------------------------------------------ 1. distro
Step "Checking for WSL distro '$Distro'"
$installed = Get-WslDistros
if ($installed -notcontains $Distro) {
  Step "Installing $Distro (can take several minutes)"
  wsl.exe --install -d $Distro --no-launch
  if ($LASTEXITCODE -ne 0) {
    Fail "wsl --install failed. Run PowerShell as Administrator, restart Windows if asked, then re-run this script."
  }
  $installed = Get-WslDistros
  if ($installed -notcontains $Distro) {
    Fail "The distro was downloaded but is not registered yet. Open '$Distro' once from the Start menu, create any user, close it, then re-run this script."
  }
} else {
  Write-Host "$Distro already installed"
}

Step "Ensuring '$Distro' uses WSL2"
wsl.exe --set-version $Distro 2
if ($LASTEXITCODE -ne 0) {
  Fail "Could not set '$Distro' to WSL2. Update WSL with 'wsl --update' and verify that virtualization is enabled."
}

# ------------------------------------------------------------ 2. linux user
Step "Checking Linux user '$LinuxUser'"
wsl.exe -d $Distro -u root -- id -u $LinuxUser | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Creating user '$LinuxUser'. This password is what 'sudo' will ask for inside Linux."
  while ($true) {
    $s1 = Read-Host "Choose a Linux password for '$LinuxUser'" -AsSecureString
    $s2 = Read-Host "Confirm password" -AsSecureString
    $p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s1))
    $p2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s2))
    if ($p1 -and $p1 -eq $p2) { break }
    Warn "Empty or not matching, try again."
  }
  $b64 = To-B64 "${LinuxUser}:${p1}"
  wsl.exe -d $Distro -u root -- bash -c "useradd -m -s /bin/bash -G sudo $LinuxUser && echo $b64 | base64 -d | chpasswd"
  if ($LASTEXITCODE -ne 0) { Fail "Could not create the Linux user." }
} else {
  Write-Host "User '$LinuxUser' already exists (its password is unchanged)"
}

# ------------------------------------------------------------ 3. systemd + default user
Step "Checking systemd and default user"
wsl.exe -d $Distro -u root -- grep -qs "systemd=true" /etc/wsl.conf | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Writing /etc/wsl.conf (systemd on, default user $LinuxUser)"
  $conf = "[boot]`nsystemd=true`n`n[user]`ndefault=$LinuxUser`n"
  $confB64 = To-B64 $conf
  wsl.exe -d $Distro -u root -- bash -c "echo $confB64 | base64 -d > /etc/wsl.conf"
  if ($LASTEXITCODE -ne 0) { Fail "Could not write /etc/wsl.conf." }
  wsl.exe --terminate $Distro | Out-Null
  Start-Sleep -Seconds 3
} else {
  Write-Host "systemd already enabled"
}

# ------------------------------------------------------------ 4. copy scripts in
Step "Copying setup and startup scripts into $Distro (~/$ProjectFolder)"
foreach ($script in @(
  @{ Path = $setupScript; Name = "setup-frappe.sh" },
  @{ Path = $startScript; Name = "start-ai-erpnext.sh" }
)) {
  $content = Get-Content -Raw -Path $script.Path
  $content | wsl.exe -d $Distro -u $LinuxUser -- bash -c "mkdir -p ~/$ProjectFolder && tr -d '\r' > ~/$ProjectFolder/$($script.Name) && chmod +x ~/$ProjectFolder/$($script.Name)"
  if ($LASTEXITCODE -ne 0) { Fail "Could not copy $($script.Name) into Linux." }
}

# ------------------------------------------------------------ 5. run it
Step "Running the Frappe + Ollama setup inside $Distro (it will ask for site name and passwords)"
wsl.exe -d $Distro -u $LinuxUser -- bash -lc "cd ~/$ProjectFolder && FRAPPE_BRANCH=$FrappeBranch ERPNEXT_BRANCH=$ErpnextBranch OLLAMA_MODEL=$OllamaModel ./setup-frappe.sh"
if ($LASTEXITCODE -ne 0) {
  Fail "The setup script stopped with an error. Read the message above. You can re-run this launcher safely."
}

Write-Host ""
Write-Host "Done. To start Ollama and ERPNext together, run:" -ForegroundColor Green
Write-Host "    wsl -d $Distro -u $LinuxUser -- bash -lc 'cd ~/$ProjectFolder/frappe-bench && ./start-ai-erpnext.sh'"
Write-Host "Then open http://<your-site-name>:8000 in your Windows browser."
Write-Host "Files are at \\wsl`$\$Distro\home\$LinuxUser\$ProjectFolder"