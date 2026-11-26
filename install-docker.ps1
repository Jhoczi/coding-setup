# install-docker.ps1  (ASCII-safe)
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
. (Join-Path $PSScriptRoot "external-tools.ps1")

# --- 0) Admin check ---
$principal = New-Object Security.Principal.WindowsPrincipal(
  [Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run this script as Administrator.'
}

Write-Host '==> STEP 1/5: Enabling required features: WSL + VirtualMachinePlatform...'
$restartNeeded = $false
foreach ($feature in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
  Invoke-ExternalTool dism.exe @('/online', '/enable-feature', "/featurename:$feature", '/all', '/norestart') -SuccessExitCodes @(0, 3010) | Out-Null
  if ($LASTEXITCODE -eq 3010) { $restartNeeded = $true }
}

if ($restartNeeded) {
  Write-Warning 'Restart Windows and rerun install-docker.ps1 to finish WSL and Ubuntu setup.'
} else {
  Write-Host '==> STEP 2/5: Setting WSL default version to 2...'
  Invoke-ExternalTool wsl.exe @('--set-default-version', '2')

  Write-Host '==> STEP 3/5: Checking if Ubuntu (WSL) is installed...'
  $distros = Invoke-ExternalTool wsl.exe @('-l', '-q') | ForEach-Object { ($_ -replace '\x00', '').Trim() }
  if ($distros -notcontains 'Ubuntu') {
    Write-Host '   Ubuntu not found - installing...'
    Invoke-ExternalTool wsl.exe @('--install', '-d', 'Ubuntu')
  } else {
    Write-Host '   Ubuntu already installed.'
  }
}

Write-Host '==> STEP 4/5: Installing Docker Desktop via Chocolatey (if missing)...'
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
  throw 'Chocolatey is not installed. Run install-choco.ps1 first.'
}
# Chocolatey skips installation when the package is already installed.
Invoke-ExternalTool choco @('install', '-y', 'docker-desktop', '--no-progress', '--limit-output', '--execution-timeout=0') -SuccessExitCodes @(0, 1641, 3010)

Write-Host '==> STEP 5/5: Adding current user to docker-users group...'
try {
  Invoke-ExternalTool net.exe @('localgroup', 'docker-users', $env:UserName, '/add') | Out-Null
} catch {
  Write-Warning ("Could not add user to docker-users (the user may already be a member): {0}" -f $_.Exception.Message)
}

Write-Host ''
Write-Host 'NOTE:'
Write-Host ' - If this is the first time enabling WSL/VM Platform, perform a system RESTART.'
Write-Host ' - After reboot, launch Docker Desktop and enable: Settings -> General -> "Use the WSL 2 based engine".'
Write-Host ' - In Settings -> Resources -> WSL Integration, enable integration for "Ubuntu".'
Write-Host ''
Write-Host '✅ Script completed.'
