# Secret environment variables via 1Password CLI
# Sourced by .bashrc and .zshrc at shell startup
# Works on: Linux (zsh/bash), WSL (NixOS), Git Bash (Windows)
#
# Set actual item paths in 1Password before using:
#   op item create --category login --title "GitHub CLI" ...
#   op item create --category login --title "Tavily" ...

if command -v op &>/dev/null 2>&1; then
  export GH_TOKEN=$(op read "op://Personal/GitHubUsedUserPAT/credential" 2>/dev/null)
  export TAVILY_API_KEY=$(op read "op://Personal/Tavily/credential" 2>/dev/null)
fi
