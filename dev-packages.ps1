function Get-DevPackages {
  $versionsPath = Join-Path $PSScriptRoot 'versions.json'
  $versions = Get-Content -LiteralPath $versionsPath -Raw -ErrorAction Stop | ConvertFrom-Json
  $dotnetMajor = $versions.dotnetLtsMajor
  $pythonMinor = $versions.pythonSupportedMinor

  if ($dotnetMajor -notmatch '^[1-9][0-9]*$' -or $pythonMinor -notmatch '^3\.[0-9]+$') {
    throw "Invalid dotnetLtsMajor or pythonSupportedMinor in $versionsPath."
  }

  @{ win='Git.Git'; choco=@('git'); args=$null }
  @{ win='Microsoft.VisualStudioCode'; choco=@('vscode'); args=$null }
  @{
    win="Microsoft.DotNet.SDK.$dotnetMajor"
    choco=@("dotnet-${dotnetMajor}.0-sdk", "dotnet-$dotnetMajor-sdk", "dotnet-sdk-$dotnetMajor")
    args='"/quiet /norestart"'
  }
  @{ win='OpenJS.NodeJS.LTS'; choco=@('nodejs-lts'); args='"/qn /norestart"' }
  @{
    win="Python.Python.$pythonMinor"
    choco=@("python$($pythonMinor.Replace('.', ''))")
    args='"/quiet InstallAllUsers=1 PrependPath=1 Include_test=0"'
  }
  @{ win='DBeaver.DBeaver'; choco=@('dbeaver'); args=$null }
  @{ win=$null; choco=@('make'); args=$null }
}

function Ensure-Choco {
  if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Set-ExecutionPolicy Bypass -Scope Process -Force
    iex ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
  }
  Invoke-ExternalTool choco @('feature', 'enable', '-n', 'allowGlobalConfirmation') | Out-Null
  Invoke-ExternalTool choco @('feature', 'enable', '-n', 'useEnhancedExitCodes') | Out-Null
}

function Resolve-DevChocoPackage([string[]]$Candidates) {
  if ($Candidates.Count -eq 1) { return $Candidates[0] }

  Ensure-Choco
  foreach ($id in $Candidates) {
    $ids = Invoke-ExternalTool choco @('search', $id, '--exact', '--id-only', '--limit-output') -SuccessExitCodes @(0, 2)
    if ($ids -contains $id) { return $id }
  }

  throw ("No matching Chocolatey package found. Tried: {0}" -f ($Candidates -join ', '))
}

function Invoke-DevPackage([hashtable]$Package, [scriptblock]$WinGet, [scriptblock]$Chocolatey) {
  if (-not $Package.win) {
    & $Chocolatey $Package.choco[0] $Package.args
    return
  }

  try {
    & $WinGet $Package.win
  } catch {
    $wingetError = $_.Exception.Message
    Write-Warning ("WinGet failed for {0}: {1} Trying Chocolatey." -f $Package.win, $wingetError)
    try {
      $chocoId = Resolve-DevChocoPackage -Candidates $Package.choco
      & $Chocolatey $chocoId $Package.args
    } catch {
      throw ("Package {0} failed. WinGet: {1} Chocolatey: {2}" -f $Package.win, $wingetError, $_.Exception.Message)
    }
  }
}
