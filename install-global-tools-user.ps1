# install-global-tools-user.ps1 (python-safe)
$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

# --- 0) Must NOT run as Admin ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw "Run this script as a NORMAL user (not Administrator)."
}

# --- helpers ---
function Ensure-Cmd($cmd, $hint) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "Missing '$cmd'. $hint" }
}
function Ensure-UserPathEntry([string]$entry) {
  $curr = [Environment]::GetEnvironmentVariable("Path","User")
  if (-not ($curr -split ';' | Where-Object { $_ -eq $entry })) {
    [Environment]::SetEnvironmentVariable("Path", ($curr.TrimEnd(';') + ';' + $entry), "User")
    Write-Host "=> Added to User PATH: $entry"
  }
}

# --- pick Python runner robustly: prefer 'py -3', then 'python' ---
$PY_EXE = $null; $PY_ARGS = @()
if (Get-Command py -ErrorAction SilentlyContinue) { $PY_EXE = "py"; $PY_ARGS = @("-3") }
elseif (Get-Command python -ErrorAction SilentlyContinue) { $PY_EXE = "python"; $PY_ARGS = @() }
else { throw "Python not found on PATH. Run install-dev-v2.ps1 (Admin) first, then open a NEW terminal." }

function RunPy([string[]]$more) {
  & $PY_EXE @($PY_ARGS + $more)
}

# --- guards for dotnet/node ---
Ensure-Cmd "dotnet" "Run install-dev-v2.ps1 (Admin) first."
Ensure-Cmd "node"   "Run install-dev-v2.ps1 (Admin) first."

# --- ensure user PATH entries ---
$npmUserBin     = Join-Path $env:APPDATA "npm"
$dotnetToolPath = Join-Path $env:USERPROFILE ".dotnet\tools"
$pipxBin1       = Join-Path $env:USERPROFILE ".local\bin"
$pipxBin2       = Join-Path $env:APPDATA "Python\Scripts"
Ensure-UserPathEntry $npmUserBin
Ensure-UserPathEntry $dotnetToolPath
Ensure-UserPathEntry $pipxBin1
Ensure-UserPathEntry $pipxBin2
$env:Path = [Environment]::GetEnvironmentVariable("Path","User") + ";" +
            [Environment]::GetEnvironmentVariable("Path","Machine")

# ---------- .NET global tools ----------
$dotnetTools = @("dotnet-format","csharpier","dotnet-ef","dotnet-outdated-tool")
Write-Host "==> Installing/updating .NET global tools..."
foreach ($t in $dotnetTools) {
  try { dotnet tool update -g $t | Out-Null; Write-Host "   = $t (updated)" }
  catch { dotnet tool install -g $t | Out-Null; Write-Host "   + $t (installed)" }
}

# ---------- Node: Corepack with verification + fallback ----------
Write-Host "==> Enabling Corepack (pnpm/yarn) with verification..."
$pnpmOk = $false; $yarnOk = $false
try {
  corepack enable 2>$null
  corepack prepare pnpm@latest --activate 2>$null
  corepack prepare yarn@stable  --activate 2>$null
  $pnpmOk = [bool](Get-Command pnpm -ErrorAction SilentlyContinue)
  $yarnOk = [bool](Get-Command yarn -ErrorAction SilentlyContinue)
} catch { }

if (-not $pnpmOk -or -not $yarnOk) {
  Write-Warning "Corepack shims not available (Program Files is locked). Falling back to npm -g in user dir."
  npm config set prefix "$npmUserBin" | Out-Null
  if (-not $pnpmOk) { npm -g install pnpm | Out-Null }
  if (-not $yarnOk) { npm -g install yarn | Out-Null }
}

Write-Host "==> Installing Angular/Nest CLIs globally..."
npm -g install @angular/cli @nestjs/cli | Out-Null

# ---------- Python: pipx via launcher (no 'python' alias issues) ----------
Write-Host "==> Ensuring pipx + Python dev tools (black, isort, ruff)..."
RunPy @("-m","ensurepip","--upgrade")         | Out-Null
RunPy @("-m","pip","install","--user","--upgrade","pip","pipx") | Out-Null
RunPy @("-m","pipx","ensurepath")             | Out-Null
# refresh PATH for this session again
$env:Path = [Environment]::GetEnvironmentVariable("Path","User") + ";" +
            [Environment]::GetEnvironmentVariable("Path","Machine")

foreach ($pkg in @("black","isort","ruff")) {
  RunPy @("-m","pipx","install",$pkg,"--force") | Out-Null
  Write-Host "   * $pkg ready"
}

# ---------- Versions ----------
Write-Host "`n==> Versions:"
try { dotnet tool list -g } catch {}
try { node -v } catch {}
try { npm -v } catch {}
try { pnpm -v } catch {}
try { yarn -v } catch {}
try { ng version | Select-String -Pattern "Angular CLI" } catch {}
try { nest --version } catch {}
try { RunPy @("--version") } catch {}
try { RunPy @("-m","pipx","--version") } catch {}
try { black --version } catch {}
try { isort --version } catch {}
try { ruff --version } catch {}

Write-Host "`n✅ Global developer tools installed for USER profile."
Write-Host "   If pnpm/yarn/pipx aren't visible yet, open a NEW terminal."
Write-Host "   (Optional) Update npm: npm -g i npm@latest"
