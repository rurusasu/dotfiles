$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/ChezmoiOnePasswordPrefetch.ps1')

$chezmoiCommand = Get-Command chezmoi.exe -ErrorAction SilentlyContinue
if (-not $chezmoiCommand) {
    $chezmoiCommand = Get-Command chezmoi -ErrorAction SilentlyContinue
}
if (-not $chezmoiCommand) {
    Write-Error 'chezmoi was not found.'
    exit 1
}

$opCommand = Get-Command op.exe -ErrorAction SilentlyContinue
if (-not $opCommand) {
    $opCommand = Get-Command op -ErrorAction SilentlyContinue
}

$prefetch = Get-ChezmoiPrefetchResult `
    -ChezmoiExe $chezmoiCommand.Source `
    -OpExe $(if ($opCommand) { $opCommand.Source } else { '' })

$inheritedPrefetchNames = @(
    [Environment]::GetEnvironmentVariables('Process').Keys |
        ForEach-Object { [string] $_ } |
        Where-Object { $_.StartsWith('DOTFILES_OP_PREFETCHED_', [StringComparison]::OrdinalIgnoreCase) }
)
$environmentNames = @('DOTFILES_OP_PREFETCH_ENABLED') + $inheritedPrefetchNames + @($prefetch.Secrets.Keys)
$environmentNames = @($environmentNames | Select-Object -Unique)
$previousEnvironment = @{}
foreach ($name in $environmentNames) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

try {
    foreach ($name in $inheritedPrefetchNames) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    [Environment]::SetEnvironmentVariable('DOTFILES_OP_PREFETCH_ENABLED', '1', 'Process')
    foreach ($name in $prefetch.Secrets.Keys) {
        [Environment]::SetEnvironmentVariable($name, [string] $prefetch.Secrets[$name], 'Process')
    }

    & $chezmoiCommand.Source apply --force
    $applyExitCode = $LASTEXITCODE
}
finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
}

exit $applyExitCode
