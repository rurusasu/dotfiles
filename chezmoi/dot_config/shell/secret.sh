# Secret environment variables - lazy 1Password loader.
# Sourced by .bashrc and .zshrc at shell startup.
#
# Plain shell startup must not prompt for 1Password. This file only reads
# secrets when DOTFILES_FORCE_SECRET_LOAD is set by an explicit command wrapper
# such as codex().
#
# Under WSL, op.exe is used so Windows 1Password app integration can satisfy
# the request without a separate Linux signin.

if [ -z "${GITHUB_PAT_TOKEN:-}" ] && [ -n "${GH_TOKEN:-}" ]; then
  export GITHUB_PAT_TOKEN="$GH_TOKEN"
fi
if [ -z "${GH_TOKEN:-}" ] && [ -n "${GITHUB_PAT_TOKEN:-}" ]; then
  export GH_TOKEN="$GITHUB_PAT_TOKEN"
fi

[ -n "${DOTFILES_FORCE_SECRET_LOAD:-}" ] || return 0

# Under WSL the Linux `op` CLI cannot bridge to the Windows 1Password app.
# Use op.exe so secrets resolve without a separate Linux signin.
if [ -n "$WSL_DISTRO_NAME" ]; then
  _op_cmd=op.exe
  _op_cache_arg='--cache=false'
else
  _op_cmd=op
  _op_cache_arg=''
fi
command -v "$_op_cmd" >/dev/null 2>&1 || {
  unset _op_cmd
  unset _op_cache_arg
  return 0
}

_personal_acct="${OP_ACCOUNT:-EJLA3HRAVZBCXIQ7SRSFGQBTNU}"
_work_acct="aimatecoltd.1password.com"
_op_service_account_token_ref="${DOTFILES_OP_SERVICE_ACCOUNT_TOKEN_REF:-op://Employee/1password Service Account/password}"
_secret_timeout="${DOTFILES_SECRET_LOAD_TIMEOUT_SECONDS:-60}"
case "$_secret_timeout" in
'' | *[!0-9]* | 0) _secret_timeout=60 ;;
esac

if command -v timeout >/dev/null 2>&1; then
  _timeout_cmd=timeout
elif command -v gtimeout >/dev/null 2>&1; then
  _timeout_cmd=gtimeout
else
  _timeout_cmd=''
fi

_dotfiles_op_read() {
  local _ref="$1"
  local _acct="$2"
  local _output

  if [ -n "$_timeout_cmd" ]; then
    if [ -n "$_op_cache_arg" ]; then
      _output=$("$_timeout_cmd" "${_secret_timeout}s" "$_op_cmd" "$_op_cache_arg" --account "$_acct" read "$_ref" 2>/dev/null) || return $?
    else
      _output=$("$_timeout_cmd" "${_secret_timeout}s" "$_op_cmd" --account "$_acct" read "$_ref" 2>/dev/null) || return $?
    fi
  else
    if [ -n "$_op_cache_arg" ]; then
      _output=$("$_op_cmd" "$_op_cache_arg" --account "$_acct" read "$_ref" 2>/dev/null) || return $?
    else
      _output=$("$_op_cmd" --account "$_acct" read "$_ref" 2>/dev/null) || return $?
    fi
  fi

  printf '%s' "$_output" | tr -d '\r'
}

_dotfiles_should_load_secret() {
  local _name="$1"
  local _only
  [ -n "${DOTFILES_SECRET_LOAD_ONLY:-}" ] || return 0
  _only=" $(printf '%s' "$DOTFILES_SECRET_LOAD_ONLY" | tr ',[:space:]' '   ') "
  case "$_only" in
  *" $_name "*) return 0 ;;
  *) return 1 ;;
  esac
}

_dotfiles_set_secret() {
  local _name="$1"
  local _ref="$2"
  local _acct="$3"
  local _current
  local _value

  eval "_current=\${${_name}:-}"
  [ -n "$_current" ] && return 0
  _dotfiles_should_load_secret "$_name" || return 0

  _value=$(_dotfiles_op_read "$_ref" "$_acct") || {
    printf '[secret/env.sh] warning: %s read failed for %s\n' "$_op_cmd" "$_name" >&2
    return 0
  }
  [ -n "$_value" ] || return 0

  case "$_name" in
  GITHUB_PAT_TOKEN | TAVILY_API_KEY | GITHUB_WORK_TOKEN | OP_SERVICE_ACCOUNT_TOKEN)
    export "$_name=$_value"
    ;;
  esac
}

_dotfiles_set_secret GITHUB_PAT_TOKEN 'op://Private/GitHubUsedUserPAT/credential' "$_personal_acct"
_dotfiles_set_secret TAVILY_API_KEY 'op://Private/TavilyUsedUserPAT/credential' "$_personal_acct"

if [ -z "${GITHUB_PAT_TOKEN:-}" ] && [ -n "${GH_TOKEN:-}" ]; then
  export GITHUB_PAT_TOKEN="$GH_TOKEN"
fi
if [ -z "${GH_TOKEN:-}" ] && [ -n "${GITHUB_PAT_TOKEN:-}" ]; then
  export GH_TOKEN="$GITHUB_PAT_TOKEN"
fi

_dotfiles_set_secret GITHUB_WORK_TOKEN 'op://devcontainer/GITHUB_PERSONAL_ACCESS_TOKEN_KOHEI-MIKI-IM8/credential' "$_work_acct"
_dotfiles_set_secret OP_SERVICE_ACCOUNT_TOKEN "$_op_service_account_token_ref" "$_work_acct"

unset -f _dotfiles_op_read _dotfiles_should_load_secret _dotfiles_set_secret
unset _op_cmd _op_cache_arg _personal_acct _work_acct _op_service_account_token_ref _secret_timeout _timeout_cmd
