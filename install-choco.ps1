# install-choco.ps1 -> powershell -NoProfile -ExecutionPolicy Bypass -File .\install-choco.ps1
$ErrorActionPreference = "Stop"

# 1) Requires `Run as Administrator`
$principal = New-Object Security.Principal.WindowsPrincipal(
  [Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Error "Uruchom ten skrypt jako Administrator (Run as administrator)."
}

# 2) If Chocolatey was already installed - show the version and exit
if (Get-Command choco -ErrorAction SilentlyContinue) {
  $ver = choco --version
  Write-Host "Chocolatey already installed. Version: $ver"
  exit 0
}

Write-Host "Installing Chocolatey..."

# 3) TLS 1.2 + ExecutionPolicy only for this session
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
Set-ExecutionPolicy Bypass -Scope Process -Force

# 4) Official installer from the community chocolatey.org
$scriptUrl = "https://community.chocolatey.org/install.ps1"
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString($scriptUrl))

# 5) Ensure Choco is in PATH for this session.
$chocoBin = "$env:ALLUSERSPROFILE\chocolatey\bin"
if (-not ($env:Path.Split(';') -contains $chocoBin)) {
  $env:Path = "$env:Path;$chocoBin"
}

# 6) Verification
choco --version | Write-Host
Write-Host "Chocolatey successfully installed."