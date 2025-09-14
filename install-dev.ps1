# install-dev.ps1
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# --- Admin check ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
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

function Winget-Install([string]$id) {
  if (-not (Winget-Available)) { throw "winget is not available." }
  # already installed?
  $exists = winget list --id $id -e --accept-source-agreements 2>$null | Select-String $id
  if (-not $exists) {
    Write-Host ("==> winget install {0}" -f $id)
    winget install --id $id -e --accept-package-agreements --accept-source-agreements --silent --disable-interactivity --force | Out-Null
  } else {
    Write-Host ("==> {0} already installed (winget) - skipping." -f $id)
  }
}

function Choco-Install([string]$id, [string]$installArgs = $null) {
  Ensure-Choco
  Write-Host ("==> choco upgrade {0}" -f $id)
  $cmd = @("upgrade",$id,"--yes","--accept-license","--no-progress","--limit-output","--execution-timeout=0")
  if ($installArgs) { $cmd += "--install-arguments=$installArgs" }
  choco @cmd | Out-Null
}

function Install-Package([string]$wingetId, [string]$chocoId, [string]$chocoArgs = $null) {
  try {
    Winget-Install $wingetId
  } catch {
    Write-Warning ("winget install failed for {0}: {1} - falling back to choco: {2}" -f $wingetId, $_.Exception.Message, $chocoId)
    Choco-Install $chocoId $chocoArgs
  }
}

# --- Core tools ---
Install-Package "Git.Git"                     "git"
Install-Package "Microsoft.VisualStudioCode"  "vscode"
Install-Package "Microsoft.DotNet.SDK.8"      "dotnet-8.0-sdk" '"/quiet /norestart"'
Install-Package "OpenJS.NodeJS.LTS"           "nodejs-lts"     '"/qn /norestart"'
Install-Package "Python.Python.3.12"          "python"         '"/quiet InstallAllUsers=1 PrependPath=1 Include_test=0"'
Install-Package "DBeaver.DBeaver"             "dbeaver"

# choco-only
Choco-Install "make"

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
Write-Host "`n✅ Dev tools installed/updated."
