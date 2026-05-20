# Secret environment variables — 1Password op run pattern
# Sourced by PowerShell profile at shell startup.
#
# Preferred usage: launch WezTerm via ~/.local/bin/wezterm-launch.cmd
#   op run --env-file injects GH_TOKEN/TAVILY_API_KEY once at WezTerm startup;
#   all tabs inherit them and this guard exits immediately.
#
# For standalone pwsh outside WezTerm:
#   op run --env-file="$env:USERPROFILE\.config\shell\secrets.env" -- pwsh

if ($env:GH_TOKEN -and $env:TAVILY_API_KEY) { return }
