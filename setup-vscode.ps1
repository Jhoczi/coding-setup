# setup-vscode.ps1 -> powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-vscode.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "external-tools.ps1")

# 0) Ensure VS Code CLI
$codeCmd = Get-Command code -ErrorAction SilentlyContinue
if (-not $codeCmd) { throw "VS Code CLI ('code') not found. Restart terminal or add VS Code to PATH." }

# 1) User dir
$codeUserDir = Join-Path $env:APPDATA "Code\User"
New-Item -ItemType Directory -Force -Path $codeUserDir | Out-Null

# 2) Copy settings / keybindings if present
$settingsSrc    = Join-Path $PSScriptRoot "vscode-settings.json"
$keybindingsSrc = Join-Path $PSScriptRoot "vscode-keybindings.json"
if (Test-Path $settingsSrc)    { Copy-Item $settingsSrc (Join-Path $codeUserDir "settings.json") -Force; Write-Host "=> settings.json applied" }
if (Test-Path $keybindingsSrc) { Copy-Item $keybindingsSrc (Join-Path $codeUserDir "keybindings.json") -Force; Write-Host "=> keybindings.json applied" }

# 3) Extensions
$extListPath = Join-Path $PSScriptRoot "vscode-extensions.txt"
if (-not (Test-Path $extListPath)) { throw "Missing vscode-extensions.txt next to this script." }
$extensions = Get-Content $extListPath | Where-Object { $_ -and $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") }

Write-Host "=> Installing extensions..."
$installed = Invoke-ExternalTool code @('--list-extensions')
foreach ($ext in $extensions) {
  if ($installed -notcontains $ext) {
    Invoke-ExternalTool code @('--install-extension', $ext, '--force') | Out-Null
    Write-Host "   + $ext"
  }
  else                              { Write-Host "   = $ext (already)" }
}

Invoke-ExternalTool code @('--version')
Write-Host "`n==> VS Code setup complete."

