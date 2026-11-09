<#
  One-click local ERPNext + Ollama installer for Windows/WSL2.
  Keep this script beside setup-frappe.sh and start-ai-erpnext.sh.
#>
param(
  [string]$Distro = "Ubuntu-24.04",
  [string]$LinuxUser = "frappe",
  [string]$ProjectFolder = "erpnext",
  [string]$FrappeBranch = "version-16",
  [string]$ErpnextBranch = "feature/ai-purchase-invoice-draft",
  [string]$OllamaModel = "qwen2:7b",
  [string]$SiteName = "ai-erpnext.localhost"
)

$ErrorActionPreference = "Stop"

function Step($Message) {
  Write-Host ""
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Fail($Message) {
  Write-Host ""
  Write-Host "Setup could not continue: $Message" -ForegroundColor Red
  Write-Host "Fix the issue above and run setup-windows-ai.ps1 again. Your progress is retained." -ForegroundColor Yellow
  exit 1
}

function Get-WslDistros {
  $previous = [Console]::OutputEncoding
  try {
    [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    return @(wsl.exe -l -q 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  } finally {
    [Console]::OutputEncoding = $previous
  }
}

function Get-WslDistroVersion([string]$DistroName) {
  $previous = [Console]::OutputEncoding
  try {
    [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    $rows = @(wsl.exe --list --verbose 2>$null)
    if ($LASTEXITCODE -ne 0) {
      return $null
    }

    foreach ($row in $rows) {
      $line = ($row -replace "`0", "").Trim()
      if ($line -match "^\*?\s*$([regex]::Escape($DistroName))\s+\S+\s+([12])$") {
        return [int]$Matches[1]
      }
    }
    return $null
  } finally {
    [Console]::OutputEncoding = $previous
  }
}

function ConvertTo-Base64([string]$Value) {
  return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

function Get-OrCreatePassword {
  $credentialDirectory = Join-Path $env:LOCALAPPDATA "AI-ERPNext"
  $credentialFile = Join-Path $credentialDirectory "credentials.txt"
  $password = "786786"

  $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  $acl = New-Object Security.AccessControl.DirectorySecurity
  $acl.SetAccessRuleProtection($true, $false)
  foreach ($account in @($identity, "SYSTEM", "BUILTIN\Administrators")) {
    $rule = [Security.AccessControl.FileSystemAccessRule]::new(
      $account,
      [Security.AccessControl.FileSystemRights]::FullControl,
      ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),
      [Security.AccessControl.PropagationFlags]::None,
      [Security.AccessControl.AccessControlType]::Allow
    )
    $acl.AddAccessRule($rule)
  }
  New-Item -ItemType Directory -Path $credentialDirectory -Force | Out-Null
  Set-Acl -LiteralPath $credentialDirectory -AclObject $acl

  @(
    "ERPNext demo credentials - do not use outside a disposable demo environment"
    "Site: http://$SiteName`:8000"
    "Linux user: $LinuxUser"
    "Password: $password"
    ""
    "The same fixed demo password is used for the Linux user, MariaDB root, and ERPNext Administrator."
  ) | Set-Content -LiteralPath $credentialFile -Encoding UTF8

  $fileAcl = New-Object Security.AccessControl.FileSecurity
  $fileAcl.SetAccessRuleProtection($true, $false)
  foreach ($account in @($identity, "SYSTEM", "BUILTIN\Administrators")) {
    $rule = [Security.AccessControl.FileSystemAccessRule]::new(
      $account,
      [Security.AccessControl.FileSystemRights]::FullControl,
      [Security.AccessControl.AccessControlType]::Allow
    )
    $fileAcl.AddAccessRule($rule)
  }
  Set-Acl -LiteralPath $credentialFile -AclObject $fileAcl

  return @{ Password = $password; Path = $credentialFile }
}

foreach ($value in @($Distro, $LinuxUser, $ProjectFolder, $FrappeBranch, $ErpnextBranch, $OllamaModel, $SiteName)) {
  if ($value -notmatch '^[A-Za-z0-9._:/-]+$') {
    Fail "An installer setting contains unsupported characters: $value"
  }
}
if ($ProjectFolder -in @(".", "..")) {
  Fail "ProjectFolder must be a single folder name."
}
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  Fail "Windows Subsystem for Linux (WSL) is unavailable. Enable WSL2, restart Windows if requested, then retry."
}

$setupScript = Join-Path $PSScriptRoot "setup-frappe.sh"
$startScript = Join-Path $PSScriptRoot "start-ai-erpnext.sh"
if (-not (Test-Path -LiteralPath $setupScript) -or -not (Test-Path -LiteralPath $startScript)) {
  Fail "Keep setup-frappe.sh and start-ai-erpnext.sh in the same folder as this installer."
}

$credentials = Get-OrCreatePassword
$password = $credentials.Password
$passwordBase64 = ConvertTo-Base64 $password
$usernamePasswordBase64 = ConvertTo-Base64 "$LinuxUser`:$password"
$distroList = Get-WslDistros
if ($distroList -notcontains $Distro) {
  $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Step "Requesting Windows approval to install WSL"
    $elevatedArguments = @(
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"",
      "-Distro", $Distro, "-LinuxUser", $LinuxUser, "-ProjectFolder", $ProjectFolder,
      "-FrappeBranch", $FrappeBranch, "-ErpnextBranch", $ErpnextBranch,
      "-OllamaModel", $OllamaModel, "-SiteName", $SiteName
    ) -join " "
    $elevated = Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $elevatedArguments -Wait -PassThru
    exit $elevated.ExitCode
  }

  Step "Installing Ubuntu in WSL2 (this can take a while)"
  wsl.exe --install -d $Distro --no-launch
  if ($LASTEXITCODE -ne 0) {
    Fail "Windows could not install Ubuntu. If it asks for a restart, restart and run this installer again."
  }
}

Step "Checking the WSL version for $Distro"
$distroVersion = Get-WslDistroVersion $Distro
if ($null -eq $distroVersion) {
  Fail "Could not find $Distro in WSL. If Ubuntu installation requires a restart, restart Windows and run this installer again."
}
if ($distroVersion -eq 1) {
  wsl.exe --set-version $Distro 2
  if ($LASTEXITCODE -ne 0) {
    Fail "Could not convert $Distro to WSL2. Run 'wsl --update', check that virtualization is enabled, and retry."
  }
} else {
  Write-Host "$Distro is already running on WSL2; skipping conversion."
}

Step "Creating the installer-managed Linux account"
# Starting the distro as root avoids Ubuntu's interactive first-user wizard.
wsl.exe -d $Distro -u root -- true
if ($LASTEXITCODE -ne 0) {
  Fail "Ubuntu did not start. If Windows requests a restart or first-time WSL setup, complete it and retry."
}

$userSetup = "if ! id -u $LinuxUser >/dev/null 2>&1; then useradd -m -s /bin/bash -G sudo $LinuxUser; else usermod -aG sudo $LinuxUser; fi; echo $usernamePasswordBase64 | base64 -d | chpasswd"
wsl.exe -d $Distro -u root -- bash -c $userSetup
if ($LASTEXITCODE -ne 0) {
  Fail "Could not prepare the Linux account."
}

$wslConfig = "[boot]`nsystemd=true`n`n[user]`ndefault=$LinuxUser`n"
$wslConfigBase64 = ConvertTo-Base64 $wslConfig
wsl.exe -d $Distro -u root -- bash -c "printf '%s' '$wslConfigBase64' | base64 -d > /etc/wsl.conf"
if ($LASTEXITCODE -ne 0) {
  Fail "Could not configure systemd for WSL."
}
wsl.exe --terminate $Distro | Out-Null
Start-Sleep -Seconds 3

Step "Copying the installer files into Ubuntu"
foreach ($file in @(
  @{ Path = $setupScript; Name = "setup-frappe.sh" },
  @{ Path = $startScript; Name = "start-ai-erpnext.sh" }
)) {
  Get-Content -Raw -LiteralPath $file.Path |
    wsl.exe -d $Distro -u root -- bash -c "mkdir -p /home/$LinuxUser/$ProjectFolder && tr -d '\r' > /home/$LinuxUser/$ProjectFolder/$($file.Name) && chown $LinuxUser`:$LinuxUser /home/$LinuxUser/$ProjectFolder/$($file.Name) && chmod 755 /home/$LinuxUser/$ProjectFolder/$($file.Name)"
  if ($LASTEXITCODE -ne 0) {
    Fail "Could not copy $($file.Name) into Ubuntu."
  }
}
wsl.exe -d $Distro -u root -- bash -c "chown -R $LinuxUser`:$LinuxUser /home/$LinuxUser/$ProjectFolder"
if ($LASTEXITCODE -ne 0) {
  Fail "Could not set up the Ubuntu project folder."
}

Step "Installing ERPNext, Ollama, and $OllamaModel (downloads may take a long time)"
$sudoSetup = "$LinuxUser ALL=(ALL) NOPASSWD: ALL"
$sudoStart = "$LinuxUser ALL=(root) NOPASSWD: /usr/bin/systemctl start ollama"
$sudoersBase64 = ConvertTo-Base64 $sudoSetup
$startSudoersBase64 = ConvertTo-Base64 $sudoStart
wsl.exe -d $Distro -u root -- bash -c "printf '%s' '$sudoersBase64' | base64 -d > /etc/sudoers.d/99-ai-erpnext-setup && chmod 440 /etc/sudoers.d/99-ai-erpnext-setup && visudo -cf /etc/sudoers.d/99-ai-erpnext-setup && printf '%s' '$startSudoersBase64' | base64 -d > /etc/sudoers.d/90-ai-erpnext-ollama && chmod 440 /etc/sudoers.d/90-ai-erpnext-ollama && visudo -cf /etc/sudoers.d/90-ai-erpnext-ollama"
if ($LASTEXITCODE -ne 0) {
  Fail "Could not configure unattended setup permissions."
}

$encodedPassword = ConvertTo-Base64 $password
$setupCommand = "trap 'sudo rm -f /etc/sudoers.d/99-ai-erpnext-setup' EXIT; cd /home/$LinuxUser/$ProjectFolder; export FRAPPE_BRANCH='$FrappeBranch' ERPNEXT_BRANCH='$ErpnextBranch' OLLAMA_MODEL='$OllamaModel' SITE_NAME='$SiteName'; export DB_ROOT_PW=`$(printf '%s' '$encodedPassword' | base64 -d) ADMIN_PW=`$(printf '%s' '$encodedPassword' | base64 -d); ./setup-frappe.sh"
wsl.exe -d $Distro -u $LinuxUser -- bash -lc $setupCommand
if ($LASTEXITCODE -ne 0) {
  Fail "ERPNext/Ollama setup reported an error. Re-run this installer; the demo password is 786786."
}

Step "Starting ERPNext and opening the website"
$startCommand = "`"cd /home/$LinuxUser/$ProjectFolder/frappe-bench && ./start-ai-erpnext.sh`""
$startArguments = "-d $Distro -u $LinuxUser -- bash -lc $startCommand"
Start-Process -FilePath "wsl.exe" -ArgumentList $startArguments
Start-Sleep -Seconds 12
Start-Process "http://$SiteName`:8000"

Write-Host ""
Write-Host "Setup finished. ERPNext is starting in its own terminal window." -ForegroundColor Green
Write-Host "Website: http://$SiteName`:8000"
Write-Host "Login: Administrator"
Write-Host "Demo password for Linux, MariaDB root, and ERPNext Administrator: 786786" -ForegroundColor Yellow
Write-Host "Credentials are saved here: $($credentials.Path)"
Write-Host "This password is for disposable demos only. The first model load can take a few minutes."
