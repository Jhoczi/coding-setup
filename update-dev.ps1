# update-dev-v3.ps1
param(
  [switch]$UpgradeAllWinget,   # optional: winget upgrade --all
  [switch]$SkipCloseApps       # don't close apps/services before upgrade
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

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
function Ensure-Choco {
  if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Set-ExecutionPolicy Bypass -Scope Process -Force
    iex ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
  }
  choco feature enable -n allowGlobalConfirmation | Out-Null
  choco feature enable -n useEnhancedExitCodes  | Out-Null
}

function Stop-Proc([string[]]$names){
  foreach($n in $names){
    Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  }
}
function Stop-Docker {
  try { Stop-Service -Name com.docker.service -Force -ErrorAction SilentlyContinue } catch {}
  Stop-Proc @("Docker Desktop")
}

# --- Pre-close running apps to avoid prompts ---
if (-not $SkipCloseApps) {
  Write-Host "==> Closing apps (VS Code, DBeaver, Docker Desktop) to avoid prompts..."
  # VS Code process is "Code"; insiders is "Code - Insiders"
  Stop-Proc @("Code","Code - Insiders","dbeaver")
  Stop-Docker
}

# --- Winget upgrade helper (non-interactive) ---
function Winget-Upgrade([string]$id) {
  if (-not (Winget-Available)) { throw "winget not available." }
  Write-Host "==> winget upgrade $id"
  winget upgrade --id $id -e `
    --accept-package-agreements --accept-source-agreements `
    --silent --disable-interactivity --force | Out-Null
}

# --- Chocolatey upgrade helper ---
function Choco-Upgrade([string]$id, [string]$installArgs = $null) {
  Ensure-Choco
  Write-Host "==> choco upgrade $id"
  $cmd = @("upgrade",$id,"--yes","--accept-license","--no-progress","--limit-output","--execution-timeout=0")
  if ($installArgs) { $cmd += "--install-arguments=$installArgs" }
  choco @cmd | Out-Null
}

# --- Targets (prefer winget; fallback to choco) ---
$targets = @(
  @{ win="Git.Git";                    choco="git";             args=$null },
  @{ win="Microsoft.VisualStudioCode"; choco="vscode";          args=$null },
  @{ win="Microsoft.DotNet.SDK.8";     choco="dotnet-8.0-sdk";  args='"/quiet /norestart"' },
  @{ win="OpenJS.NodeJS.LTS";          choco="nodejs-lts";      args='"/qn /norestart"' },
  @{ win="Python.Python.3.12";         choco="python";          args='"/quiet InstallAllUsers=1 PrependPath=1 Include_test=0"' },
  @{ win="DBeaver.DBeaver";            choco="dbeaver";         args=$null }
)

foreach ($t in $targets) {
  try   { Winget-Upgrade $t.win }
  catch { Write-Warning ("Falling back to Chocolatey for {0}" -f $t.win); Choco-Upgrade $t.choco $t.args }
}

# choco-managed only
Choco-Upgrade "make"
# Docker Desktop requires service stop to avoid prompts
if (-not $SkipCloseApps) { Stop-Docker }
Choco-Upgrade "docker-desktop"

# optional: upgrade everything else via winget
if ($UpgradeAllWinget -and (Winget-Available)) {
  Write-Host "==> winget upgrade --all ..."
  winget upgrade --all --accept-package-agreements --accept-source-agreements --silent --disable-interactivity --force | Out-Null
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
