# Secret environment variables via 1Password CLI
# Sourced by .bashrc and .zshrc at shell startup
# Works on: Linux (zsh/bash), WSL (NixOS, uses op.exe), Git Bash (Windows)
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

# Under WSL the Linux `op` CLI cannot bridge to the Windows 1Password app's
# CLI integration. Use `op.exe` (on PATH via winget) so secrets resolve
# without a separate Linux signin — mirrors chezmoi's [onepassword].command
# (.chezmoi.toml.tmpl).
if [ -n "$WSL_DISTRO_NAME" ]; then
  _op_cmd=op.exe
else
  _op_cmd=op
fi
command -v "$_op_cmd" >/dev/null 2>&1 || {
  unset _op_cmd
  return 0
}

_secret_tmpl='GH_TOKEN={{ op://Private/GitHubUsedUserPAT/credential }}
TAVILY_API_KEY={{ op://Private/TavilyUsedUserPAT/credential }}'

# `op inject` reads the template on stdin and emits KEY=value lines on stdout
# with secrets substituted. `set -a` exports every assignment that follows.
_resolved=$(printf '%s\n' "$_secret_tmpl" | "$_op_cmd" inject 2>/dev/null) || {
  printf '[secret/env.sh] warning: %s inject failed; GH_TOKEN/TAVILY_API_KEY not set\n' "$_op_cmd" >&2
  _resolved=''
}
# Strip Windows CR that op.exe may emit under WSL.
_resolved=$(printf '%s' "$_resolved" | tr -d '\r')
if [ -n "$_resolved" ]; then
  set -a
  eval "$_resolved"
  set +a
fi
unset _secret_tmpl _resolved _op_cmd
