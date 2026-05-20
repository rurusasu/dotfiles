# Secret environment variables — 1Password op run pattern
# Sourced by .bashrc and .zshrc at shell startup.
#
# Preferred usage (WSL in WezTerm): launch WezTerm via wezterm-launch.cmd
#   wezterm-launch.cmd sets WSLENV=GH_TOKEN:TAVILY_API_KEY before op run,
#   so WSL child processes inherit the vars and this guard exits immediately.
#
# Fallback (standalone WSL / native Linux): op.exe inject runs once per session.

[ -n "$GH_TOKEN" ] && [ -n "$TAVILY_API_KEY" ] && return 0

# Under WSL the Linux `op` CLI cannot bridge to the Windows 1Password app.
# Use op.exe so secrets resolve without a separate Linux signin.
if [ -n "$WSL_DISTRO_NAME" ]; then
  _op_cmd=op.exe
else
  _op_cmd=op
fi
command -v "$_op_cmd" >/dev/null 2>&1 || {
  unset _op_cmd
  return 0
}

_op_acct="${OP_ACCOUNT:-EJLA3HRAVZBCXIQ7SRSFGQBTNU}"
_secret_tmpl='GH_TOKEN={{ op://Private/GitHubUsedUserPAT/credential }}
TAVILY_API_KEY={{ op://Private/TavilyUsedUserPAT/credential }}'

_resolved=$(printf '%s\n' "$_secret_tmpl" | "$_op_cmd" inject --account "$_op_acct" 2>/dev/null) || {
  printf '[secret/env.sh] warning: %s inject failed; GH_TOKEN/TAVILY_API_KEY not set\n' "$_op_cmd" >&2
  _resolved=''
}
_resolved=$(printf '%s' "$_resolved" | tr -d '\r')
if [ -n "$_resolved" ]; then
  set -a
  eval "$_resolved"
  set +a
fi
unset _secret_tmpl _resolved _op_cmd _op_acct
