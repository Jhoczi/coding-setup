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

function Resolve-ChocoDotnetId([int]$major) {
  # Potential choco names for dotnet sdk:
  $candidates = @(
    "dotnet-$($major).0-sdk",
    "dotnet-$($major)-sdk",
    "dotnet-sdk-$major",
    "dotnet-sdk"           # universal "latest” (final fallback)
  )

  foreach ($id in $candidates) {
    try {
      $exists = choco search $id --exact --id-only --limit-output 2>$null
      if ($LASTEXITCODE -eq 0 -and $exists -match "^\Q$id\E$") {
        return $id
      }
    } catch {
      # ignore single attempt errors
    }
  }
  return $null
}

function Install-Package([string]$wingetId, [string]$chocoId, [string]$chocoArgs = $null) {
  try {
    Winget-Install $wingetId
  } catch {
    Write-Warning ("winget install failed for {0}: {1} - falling back to choco: {2}" -f $wingetId, $_.Exception.Message, $chocoId)
    Choco-Install $chocoId $chocoArgs
  }
}

# --- Versions source (from versions.json) ---
$versionsPath = Join-Path $PSScriptRoot "versions.json"
if (-not (Test-Path $versionsPath))
{
  throw "Missing versions.json next to install-dev.ps1. Create it first."
}
$versions = Get-Content $versionsPath | ConvertFrom-Json

# Compose winget IDs from versions.json
$DotnetLtsMajor = $versions.dotnetLtsMajor
$PythonMinorCycle = $versions.pythonSupportedMinor

$DotnetWingetId = "Microsoft.Dotnet.SDK.$DotnetLtsMajor"
$PythonWingetId = "Python.Python.$PythonMinorCycle"

# --- detect dynamic choco fallback for .NET ---
$ChocoDotnetId = $null
try {
  Ensure-Choco
  $ChocoDotnetId = Resolve-ChocoDotnetId -major $DotnetLtsMajor
  if (-not $ChocoDotnetId) {
    Write-Warning ("Cannot find the package for choco .NET {0} - winget should be enough." -f $DotnetLtsMajor)
  } else {
    Write-Host   ("Choco fallback for .NET {0}: {1}" -f $DotnetLtsMajor, $ChocoDotnetId)
  }
}
catch {
  Write-Warning "Cannot detect choco fallback (repo offline?). Will try winget."
}

# --- Core tools ---
Install-Package "Git.Git"                     "git"
Install-Package "Microsoft.VisualStudioCode"  "vscode"
Install-Package $DotnetWingetId               $ChocoDotnetId '"/quiet /norestart"'
Install-Package "OpenJS.NodeJS.LTS"           "nodejs-lts"     '"/qn /norestart"'
Install-Package $PythonWingetId          "python"         '"/quiet InstallAllUsers=1 PrependPath=1 Include_test=0"'
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
Write-Host "`n Dev tools installed/updated."
