param(
  [Parameter(Mandatory = $true)]
  [string]$Path
)

if (-not (Get-Command -Name Invoke-Formatter -ErrorAction SilentlyContinue)) {
  Write-Error "Invoke-Formatter not found. Install-Module PSScriptAnalyzer -Scope CurrentUser"
  exit 1
}

$source = Get-Content -Raw -LiteralPath $Path
$formatted = Invoke-Formatter -ScriptDefinition $source
Set-Content -LiteralPath $Path -Value $formatted -Encoding utf8
