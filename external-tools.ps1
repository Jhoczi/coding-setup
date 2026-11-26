function Invoke-ExternalTool {
  param(
    [Parameter(Mandatory)][string]$Command,
    [string[]]$Arguments = @(),
    [int[]]$SuccessExitCodes = @(0)
  )

  $tool = Get-Command $Command -CommandType Application -ErrorAction Stop | Select-Object -First 1
  # Handle exit codes explicitly in both Windows PowerShell and PowerShell 7.
  $PSNativeCommandUseErrorActionPreference = $false
  & $tool.Path @Arguments
  $exitCode = $LASTEXITCODE
  if ($exitCode -notin $SuccessExitCodes) {
    throw ("{0} {1} failed with exit code {2}." -f $Command, ($Arguments | Select-Object -First 1), $exitCode)
  }
}
