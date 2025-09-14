# install-docker.ps1  (ASCII-safe)
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# --- 0) Admin check ---
$principal = New-Object Security.Principal.WindowsPrincipal(
  [Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run this script as Administrator.'
}

Write-Host '==> STEP 1/5: Enabling required features: WSL + VirtualMachinePlatform...'
& dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
& dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null

Write-Host '==> STEP 2/5: Setting WSL default version to 2...'
wsl --set-default-version 2 2>$null

Write-Host '==> STEP 3/5: Checking if Ubuntu (WSL) is installed...'
$distros = (wsl -l -q) 2>$null
if ($null -eq $distros -or ($distros -notcontains 'Ubuntu')) {
  Write-Host '   Ubuntu not found - installing (this may require a restart)...'
  try {
    wsl --install -d Ubuntu
  } catch {
    Write-Warning 'Could not automatically install Ubuntu. After reboot you can run: wsl --install -d Ubuntu'
  }
} else {
  Write-Host '   Ubuntu already installed.'
}

Write-Host '==> STEP 4/5: Installing Docker Desktop via Chocolatey (if missing)...'
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
  throw 'Chocolatey is not installed. Run install-choco.ps1 first.'
}
# check local install
$dockerInstalled = choco list --local-only docker-desktop | Select-String -Pattern '^docker-desktop '
if (-not $dockerInstalled) {
  choco install -y docker-desktop --no-progress --limit-output --execution-timeout=0
} else {
  Write-Host '   Docker Desktop already installed - skipping.'
}

Write-Host '==> STEP 5/5: Adding current user to docker-users group...'
try {
  & net localgroup docker-users $env:UserName /add | Out-Null
} catch {
  Write-Warning 'Could not add to docker-users group (maybe already a member).'
}

Write-Host ''
Write-Host 'NOTE:'
Write-Host ' - If this is the first time enabling WSL/VM Platform, perform a system RESTART.'
Write-Host ' - After reboot, launch Docker Desktop and enable: Settings -> General -> "Use the WSL 2 based engine".'
Write-Host ' - In Settings -> Resources -> WSL Integration, enable integration for "Ubuntu".'
Write-Host ''
Write-Host '✅ Script completed.'
