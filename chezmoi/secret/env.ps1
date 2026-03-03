# Secret environment variables via 1Password CLI
# Sourced by PowerShell profile at shell startup
# Works on: Windows PowerShell 5.1, PowerShell 7 (pwsh)
#
# Set actual item paths in 1Password before using:
#   op item create --category login --title "GitHub CLI" ...
#   op item create --category login --title "Tavily" ...

if (Get-Command op -ErrorAction SilentlyContinue) {
  try { $env:GH_TOKEN       = & op read "op://Personal/GitHub CLI/token" 2>$null } catch {}
  try { $env:TAVILY_API_KEY = & op read "op://Personal/Tavily/credential" 2>$null } catch {}
}
