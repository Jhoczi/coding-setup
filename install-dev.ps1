# install-dev.ps1
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# --- Admin check ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw "Run this script as Administrator."
}

. (Join-Path $PSScriptRoot "external-tools.ps1")
. (Join-Path $PSScriptRoot "dev-packages.ps1")

function Winget-Install([string]$id) {
  # 0x8A150014 means no matching installed package.
  $exists = Invoke-ExternalTool winget @('list', '--id', $id, '-e', '--accept-source-agreements') -SuccessExitCodes @(0, -1978335212) |
    Select-String -SimpleMatch $id
  if (-not $exists) {
    Write-Host ("==> winget install {0}" -f $id)
    Invoke-ExternalTool winget @('install', '--id', $id, '-e', '--accept-package-agreements', '--accept-source-agreements', '--silent', '--disable-interactivity', '--force') | Out-Null
  } else {
    Write-Host ("==> {0} already installed (winget) - skipping." -f $id)
  }
}

function Choco-Install([string]$id, [string]$installArgs = $null) {
  Ensure-Choco
  Write-Host ("==> choco install {0}" -f $id)
  $cmd = @("install",$id,"--yes","--accept-license","--no-progress","--limit-output","--execution-timeout=0")
  if ($installArgs) { $cmd += "--install-arguments=$installArgs" }
  Invoke-ExternalTool choco $cmd -SuccessExitCodes @(0, 1641, 3010) | Out-Null
}

foreach ($package in Get-DevPackages) {
  Invoke-DevPackage $package { param($id) Winget-Install $id } { param($id, $installArgs) Choco-Install $id $installArgs }
}

# --- PATH refresh for current session ---
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
            [Environment]::GetEnvironmentVariable("Path","User")

# --- Versions ---
Write-Host "`n==> Versions:"
try { git --version } catch {}
try { code --version } catch {}
try { dotnet --info | Select-String -Pattern "Version:|OS Version" } catch {}
try { node -v } catch {}
try { npm -v } catch {}
try { python --version } catch {}
try { make --version | Select-String -Pattern "GNU Make" } catch {}
Write-Host "`n Dev tools installation complete."
