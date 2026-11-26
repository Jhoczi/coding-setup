# update-dev.ps1
param(
  [switch]$UpgradeAllWinget,
  [switch]$SkipCloseApps,
  [switch]$CloseApps
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot "external-tools.ps1")
. (Join-Path $PSScriptRoot "dev-packages.ps1")

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $PSScriptRoot "update-dev-$stamp.log"
Start-Transcript -Path $logPath -NoClobber | Out-Null

# --- Admin check ---
$principal = New-Object Security.Principal.WindowsPrincipal(
  [Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Stop-Transcript | Out-Null
  throw "Run this script as Administrator."
}

function Winget-Available { [bool](Get-Command winget -ErrorAction SilentlyContinue) }

function Stop-Proc([string[]]$names){
  foreach($n in $names){
    Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  }
}
function Stop-Docker {
  try { Stop-Service -Name com.docker.service -Force -ErrorAction SilentlyContinue } catch {}
  Stop-Proc @("Docker Desktop")
}

$targets = @(Get-DevPackages)

# Close running apps only when explicitly requested.
if ($CloseApps -and -not $SkipCloseApps) {
  Write-Host "==> Closing apps (VS Code, DBeaver, Docker Desktop) to avoid prompts..."
  # VS Code process is "Code"; insiders is "Code - Insiders"
  Stop-Proc @("Code","Code - Insiders","dbeaver")
  Stop-Docker
}

# --- Winget upgrade helper (non-interactive) ---
function Winget-Upgrade([string]$id) {
  if (-not (Winget-Available)) { throw "winget not available." }
  Write-Host "==> winget upgrade $id"
  # 0x8A15002B means no applicable update is available.
  Invoke-ExternalTool winget @('upgrade', '--id', $id, '-e', '--accept-package-agreements', '--accept-source-agreements', '--silent', '--disable-interactivity', '--force') -SuccessExitCodes @(0, -1978335189) | Out-Null
}

# --- Chocolatey upgrade helper ---
function Choco-Upgrade([string]$id, [string]$installArgs = $null) {
  Ensure-Choco
  Write-Host "==> choco upgrade $id"
  $cmd = @("upgrade",$id,"--yes","--accept-license","--no-progress","--limit-output","--execution-timeout=0")
  if ($installArgs) { $cmd += "--install-arguments=$installArgs" }
  Invoke-ExternalTool choco $cmd -SuccessExitCodes @(0, 2, 1641, 3010) | Out-Null
}

foreach ($package in $targets) {
  Invoke-DevPackage $package { param($id) Winget-Upgrade $id } { param($id, $installArgs) Choco-Upgrade $id $installArgs }
}

Choco-Upgrade "docker-desktop"

# optional: upgrade everything else via winget
if ($UpgradeAllWinget -and (Winget-Available)) {
  Write-Host "==> winget upgrade --all ..."
  Invoke-ExternalTool winget @('upgrade', '--all', '--accept-package-agreements', '--accept-source-agreements', '--silent', '--disable-interactivity', '--force') -SuccessExitCodes @(0, -1978335189) | Out-Null
}

# refresh PATH for current session
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
            [Environment]::GetEnvironmentVariable("Path","User")

Write-Host "`n==> Versions after update:"
try { git --version } catch {}
try { code --version } catch {}
try { dotnet --info | Select-String -Pattern "Version:|OS Version" } catch {}
try { node -v } catch {}
try { npm -v } catch {}
try { python --version } catch {}
try { dbeaver -help | Select-String -Pattern "DBeaver" } catch {}
try { make --version | Select-String -Pattern "GNU Make" } catch {}

Write-Host "`n System-level dev tools updated. Log: $logPath"
try { Stop-Transcript | Out-Null } catch {}
