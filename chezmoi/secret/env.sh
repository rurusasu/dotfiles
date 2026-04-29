# Secret environment variables via 1Password CLI
# Sourced by .bashrc and .zshrc at shell startup
# Works on: Linux (zsh/bash), WSL (NixOS), Git Bash (Windows)
#
# Set actual item paths in 1Password before using:
#   op item create --category login --title "GitHub CLI" ...
#   op item create --category login --title "Tavily" ...
#
# Each `op` invocation triggers a 1Password biometric/desktop approval, so
# we (1) skip when env is already populated by a parent process and
# (2) use a single `op inject` call to resolve all secrets at once,
# instead of one `op read` per secret.

[ -n "$GH_TOKEN" ] && [ -n "$TAVILY_API_KEY" ] && return 0
command -v op >/dev/null 2>&1 || return 0

_secret_tmpl='GH_TOKEN={{ op://Personal/GitHubUsedUserPAT/credential }}
TAVILY_API_KEY={{ op://Personal/TavilyUsedUserPAT/credential }}'

# `op inject` reads the template on stdin and emits KEY=value lines on stdout
# with secrets substituted. `set -a` exports every assignment that follows.
_resolved=$(printf '%s\n' "$_secret_tmpl" | op inject 2>/dev/null) || _resolved=''
if [ -n "$_resolved" ]; then
  set -a
  eval "$_resolved"
  set +a
fi
unset _secret_tmpl _resolved
