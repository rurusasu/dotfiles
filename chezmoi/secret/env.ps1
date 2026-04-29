# Secret environment variables via 1Password CLI
# Sourced by PowerShell profile at shell startup
# Works on: Windows PowerShell 5.1, PowerShell 7 (pwsh)
#
# Set actual item paths in 1Password before using:
#   op item create --category login --title "GitHub CLI" ...
#   op item create --category login --title "Tavily" ...
#
# Each `op` invocation triggers a 1Password biometric/desktop approval, so
# we (1) skip when env is already populated by a parent process and
# (2) use a single `op inject` call to resolve all secrets at once,
# instead of one `op read` per secret.

if ($env:GH_TOKEN -and $env:TAVILY_API_KEY) { return }
if (-not (Get-Command op -ErrorAction SilentlyContinue)) { return }

$_secretTmpl = @"
GH_TOKEN={{ op://Personal/GitHubUsedUserPAT/credential }}
TAVILY_API_KEY={{ op://Personal/TavilyUsedUserPAT/credential }}
"@

try {
    $_resolved = $_secretTmpl | & op inject 2>$null
    if ($LASTEXITCODE -eq 0 -and $_resolved) {
        foreach ($_line in ($_resolved -split "`r?`n")) {
            if ($_line -match '^([A-Z_][A-Z0-9_]*)=(.*)$') {
                Set-Item -Path "env:$($Matches[1])" -Value $Matches[2]
            }
        }
    }
} catch {}
finally {
    Remove-Variable _secretTmpl, _resolved, _line -ErrorAction SilentlyContinue
}
