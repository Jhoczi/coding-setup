# install-all.ps1 -> powershell -NoProfile -ExecutionPolicy Bypass -File .\install-all.ps1
# Orchestrates full dev setup:
# 1) Admin phase: Chocolatey, core tools, Docker/WSL, optional updates
# 2) User phase: global dev tools, VS Code setup (non-admin via Scheduled Task)

param(
  [switch]$UpdateAfterInstall,
  [switch]$CloseApps
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = 'SilentlyContinue'

if ($CloseApps -and -not $UpdateAfterInstall) {
  throw "Use -CloseApps with -UpdateAfterInstall."
}

# --- Self-elevate to Administrator if needed ---
$me   = [Security.Principal.WindowsIdentity]::GetCurrent()
$prin = New-Object Security.Principal.WindowsPrincipal($me)
if (-not $prin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  # Relaunch this script elevated, then exit current (non-admin) instance
  $elevationArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  if ($UpdateAfterInstall) { $elevationArgs += ' -UpdateAfterInstall' }
  if ($CloseApps) { $elevationArgs += ' -CloseApps' }
  Start-Process -FilePath "powershell.exe" -ArgumentList $elevationArgs -Verb RunAs
  exit
}

# --- Paths ---
$ROOT              = Split-Path -Parent $PSCommandPath
$installChoco      = Join-Path $ROOT "install-choco.ps1"
$installDev        = Join-Path $ROOT "install-dev.ps1"
$installDocker     = Join-Path $ROOT "install-docker.ps1"
$updateDev         = Join-Path $ROOT "update-dev.ps1"
$userPhaseScript   = Join-Path $env:TEMP "dev-setup-user-phase.ps1"
$userPhaseDoneFlag = Join-Path $env:TEMP "dev-setup-user-phase.done"

# --- Logging for the master run ---
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$logAll = Join-Path $ROOT "install-all-$stamp.log"
Start-Transcript -Path $logAll -NoClobber | Out-Null

Write-Host "==> Admin phase starting..."

# --- 1) Chocolatey ---
if (Test-Path $installChoco) {
  Write-Host "-> Running install-choco.ps1"
  & $installChoco
} else {
  Write-Warning "install-choco.ps1 not found. Skipping."
}

# --- 2) Core dev tools (Git, VS Code, .NET, Node, Python, DBeaver, Make) ---
if (Test-Path $installDev) {
  Write-Host "-> Running install-dev.ps1"
  & $installDev
} else {
  Write-Warning "install-dev.ps1 not found. Skipping."
}

# --- 3) Docker Desktop + WSL2/Ubuntu ---
if (Test-Path $installDocker) {
  Write-Host "-> Running install-docker.ps1"
  & $installDocker
} else {
  Write-Warning "install-docker.ps1 not found. Skipping."
}

# --- 4) Optional system-level update ---
if ($UpdateAfterInstall) {
  Write-Host "-> Running update-dev.ps1"
  & $updateDev -CloseApps:$CloseApps
}

Write-Host "==> Admin phase finished."

# -------------------- USER PHASE (non-admin) --------------------
Write-Host "==> Scheduling user phase (non-admin): global tools + VS Code setup..."

# Prepare a small user-phase script that runs *without* admin privileges
@'
param([string]$Root)
Set-Location $Root
$ErrorActionPreference = "Stop"

# Run user-level scripts if present
if (Test-Path ".\install-global-tools-user.ps1") {
  Write-Host "-> install-global-tools-user.ps1"
  & ".\install-global-tools-user.ps1"
}
if (Test-Path ".\setup-vscode.ps1") {
  Write-Host "-> setup-vscode.ps1"
  & ".\setup-vscode.ps1"
}

"OK" | Out-File "$env:TEMP\dev-setup-user-phase.done" -Encoding ASCII
'@ | Out-File -FilePath $userPhaseScript -Encoding UTF8 -Force

# Remove previous done flag if exists
Remove-Item $userPhaseDoneFlag -Force -ErrorAction SilentlyContinue | Out-Null

# Create a Scheduled Task to execute as the signed-in user with Limited privileges
$taskName  = "DevSetup-UserPhase-" + [guid]::NewGuid().ToString("N")
$userId    = "$env:UserDomain\$env:UserName"
$action    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$userPhaseScript`" -Root `"$ROOT`""
$trigger   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(3)
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

# Wait for user phase to signal completion (max 20 minutes)
$deadline = (Get-Date).AddMinutes(20)
while ((Get-Date) -lt $deadline) {
  if (Test-Path $userPhaseDoneFlag) { break }
  Start-Sleep -Seconds 5
}

# Clean up task
try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false | Out-Null } catch {}

if (Test-Path $userPhaseDoneFlag) {
  Write-Host "==> User phase completed."
} else {
  Write-Warning "User phase did not signal completion. 
Open a normal (non-admin) PowerShell and run:
  .\install-global-tools-user.ps1
  .\setup-vscode.ps1"
}

Write-Host "`n✅ All done."
Write-Host "   If WSL features were enabled for the first time, a REBOOT is recommended."
Write-Host "   Full master log: $logAll"

try { Stop-Transcript | Out-Null } catch {}
