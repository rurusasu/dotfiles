# Render the left prompt asynchronously after the standard Starship Zsh init.
# Usage: source async.zsh STARSHIP ASYNC_LIBRARY TIMEOUT [SECONDS]
(( $# == 3 || $# == 4 )) || return 1
[[ -o interactive && -n ${functions[prompt_starship_precmd]:-} ]] || return 1
(( ${_dsal_enabled:-0} )) && return 0
typeset -g _dsal_binary=$1 _dsal_library=$2 _dsal_timeout_binary=$3
typeset -g _dsal_timeout_seconds=${4:-10}
[[ -x $_dsal_binary && -r $_dsal_library && -x $_dsal_timeout_binary &&
   $_dsal_timeout_seconds == <1-> ]] || return 1
if (( ! ${+functions[async_start_worker]} )); then
  source "$_dsal_library" || return 1
fi
zmodload zsh/parameter zsh/system || return 1
autoload -Uz add-zsh-hook add-zle-hook-widget

typeset -g _dsal_original_prompt=$PROMPT
typeset -g _dsal_owner_pid=$sysparams[pid]
typeset -g _dsal_worker=dotfiles_starship_$_dsal_owner_pid
typeset -g _dsal_placeholder='%F{8}[updating]%f %~ %# '
typeset -g _dsal_visible=$_dsal_placeholder
typeset -g _dsal_key='' _dsal_cache_key='' _dsal_cache='' _dsal_error=''
typeset -g _dsal_pwd='' _dsal_keymap=''
typeset -g _dsal_edit_keymap='' _dsal_edit_context=''
typeset -g _dsal_status='' _dsal_pipe='' _dsal_duration='' _dsal_jobs=0
typeset -g _dsal_active_key=''
typeset -g _dsal_env_key='' _dsal_worker_env_key=''
typeset -ga _dsal_args
typeset -gi _dsal_enabled=0 _dsal_active=0 _dsal_pending=0
typeset -gi _dsal_epoch=0 _dsal_generation=0 _dsal_width=0 _dsal_request_id=0
typeset -gi _dsal_active_generation=0 _dsal_active_id=0
typeset -gi _dsal_worker_running=0 _dsal_retries=0

# Define worker functions BEFORE starting the forked worker. A lazy worker
# inherits the current parent environment and is replaced when it changes.
_dsal_render() (
  emulate -L zsh
  local __dsal_w_token=$1 __dsal_w_pwd=$2 __dsal_w_timeout=$3
  local __dsal_w_seconds=$4 __dsal_w_binary=$5
  shift 5
  builtin cd -q -- "$__dsal_w_pwd" || return 1
  print -rn -- "$__dsal_w_token"$'\x1f'
  # Keep the timeout/renderer in the worker's process group so the library's
  # worker shutdown also reaches active render children.
  "$__dsal_w_timeout" --foreground --signal=TERM --kill-after=1s "${__dsal_w_seconds}s" \
    "$__dsal_w_binary" "$@"
)

_dsal_context() {
  local parameter_name parameter_type
  local -a identity_env
  # POSIX environments contain exported scalars, not Zsh arrays/associations.
  for parameter_name in ${(ok)parameters}; do
    parameter_type=${parameters[$parameter_name]}
    if [[ $parameter_type == *export* && $parameter_type != *array* &&
          $parameter_type != *association* ]]; then
      # Zsh changes exported _ after commands. It must not invalidate work.
      [[ $parameter_name == _ ]] || identity_env+=("$parameter_name=${(P)parameter_name}")
    fi
  done
  _dsal_env_key="${(qqq)identity_env}"
  _dsal_args=(prompt --terminal-width="$COLUMNS" --keymap="$1"
    --status="$_dsal_status" --pipestatus="$_dsal_pipe"
    --cmd-duration="$_dsal_duration" --jobs="$_dsal_jobs")
  local -a context=("$PWD" "$_dsal_epoch" "${_dsal_args[@]}" "$_dsal_env_key")
  local next_key="${(qqq)context}"
  if [[ $next_key != $_dsal_key ]]; then
    (( ++_dsal_generation ))
    _dsal_key=$next_key
    _dsal_retries=0
  fi
  _dsal_pwd=$PWD _dsal_width=$COLUMNS _dsal_keymap=$1
  if [[ $_dsal_cache_key == $_dsal_key ]]; then
    _dsal_visible=$_dsal_cache
  else
    _dsal_visible=$_dsal_placeholder
  fi
  if (( _dsal_active && _dsal_active_generation == _dsal_generation )) &&
      [[ $_dsal_active_key == $_dsal_key ]]; then
    _dsal_pending=0
  else
    _dsal_pending=1
  fi
}

_dsal_recover_worker() {
  (( _dsal_enabled )) || return 1
  if (( _dsal_retries >= 1 )); then
    _dsal_error='async worker recovery limit reached'
    dsal_restore
    return 1
  fi
  (( ++_dsal_retries ))
  async_stop_worker "$_dsal_worker" 2>/dev/null
  _dsal_worker_running=0 _dsal_active=0 _dsal_pending=1
  return 0
}

_dsal_start() {
  (( _dsal_enabled )) || return 0
  # Zsh's zpty exit hook can delete inherited PTYs when a user explicitly exits
  # a subshell. Detect actual liveness, not merely our parent-side state flag.
  if (( _dsal_worker_running )) && ! zpty -t "$_dsal_worker" 2>/dev/null; then
    _dsal_recover_worker || return 1
  fi
  (( _dsal_pending && ! _dsal_active )) || return 0
  local -a request=(_dsal_render "$(( _dsal_request_id + 1 ))" "$PWD"
    "$_dsal_timeout_binary" "$_dsal_timeout_seconds" "$_dsal_binary"
    "${_dsal_args[@]}")
  local -a quoted_request=("${(@q)request}")
  local serialized_request="${(j: :)quoted_request}"
  local -i request_bytes
  () {
    local LC_ALL=C
    request_bytes=$(( ${#1} + 2 ))  # NUL delimiter plus zpty's newline.
  } "$serialized_request"
  # Nonblocking zpty writes can truncate and still return success. Keep every
  # request well below the PTY buffer limit; no environment values are sent.
  if (( request_bytes > 2048 )); then
    _dsal_error='Starship request exceeds safe transport size'
    dsal_restore
    return 1
  fi
  if (( ! _dsal_worker_running )) || [[ $_dsal_worker_env_key != $_dsal_env_key ]]; then
    if (( _dsal_worker_running )); then
      async_stop_worker "$_dsal_worker" 2>/dev/null
      _dsal_worker_running=0
    fi
    if ! async_start_worker "$_dsal_worker"; then
      _dsal_error='could not start async worker'
      dsal_restore
      return 1
    fi
    async_register_callback "$_dsal_worker" _dsal_receive
    _dsal_worker_running=1 _dsal_worker_env_key=$_dsal_env_key
  fi
  _dsal_active=1 _dsal_pending=0
  _dsal_active_key=$_dsal_key _dsal_active_generation=$_dsal_generation
  (( ++_dsal_request_id ))
  _dsal_active_id=$_dsal_request_id
  local -i dispatch_id=$_dsal_active_id
  if ! async_job "$_dsal_worker" "${request[@]}"; then
    (( _dsal_enabled )) || return 1
    # A missing-worker callback can already have scheduled the one retry.
    (( _dsal_active && _dsal_active_id != dispatch_id )) && return 0
    if _dsal_recover_worker; then
      _dsal_start
      return $?
    fi
    return 1
  fi
}

_dsal_reset_prompt() {
  if zle && [[ $_dsal_edit_context != cont ]]; then
    # Prompt substitutions can read KEYMAP outside a user widget.
    if (( ! ${+KEYMAP} )); then
      local KEYMAP=$_dsal_edit_keymap
    fi
    # This builtin is ZLE_NOTCOMMAND/ZLE_NOLAST: no edit or kill/yank changes.
    zle .reset-prompt
    zle -R
  fi
  return 0
}

# Stay in the library's ordinary callback, preserving all editing widget flags.
# Rendered output is data, including strings resembling command substitutions.
_dsal_receive() {
  local job=$1 result_code=$2 output=$3
  local token body separator=$'\x1f'
  (( _dsal_enabled )) || return 0
  if [[ $job == '[async]' ]]; then
    if (( result_code == 2 || result_code == 3 || result_code == 130 )); then
      _dsal_context "$_dsal_edit_keymap"
      if _dsal_recover_worker; then
        _dsal_start
      fi
      return 0
    fi
    _dsal_error="async transport failure ($result_code)"
    dsal_restore
    _dsal_reset_prompt
    return 0
  fi
  [[ $job == _dsal_render ]] || return 0
  token=${output%%$separator*}
  [[ $token == $_dsal_active_id && $output == *$separator* ]] || {
    _dsal_error='invalid Starship result token'
    dsal_restore
    _dsal_reset_prompt
    return 0
  }
  body=${output#*$separator}
  # Recheck current environment/width/keymap even if a widget changed them
  # before line-pre-redraw ran. No old result may cross a context boundary.
  _dsal_context "$_dsal_edit_keymap"
  _dsal_active=0
  if (( _dsal_active_generation == _dsal_generation )) &&
      [[ $_dsal_active_key == $_dsal_key ]]; then
    if (( result_code )); then
      _dsal_error="Starship failed or timed out ($result_code)"
      dsal_restore
    else
      _dsal_cache=$body _dsal_cache_key=$_dsal_key _dsal_visible=$body
      _dsal_error=''
      _dsal_retries=0
    fi
    _dsal_reset_prompt
  fi
  _dsal_start
  return 0
}

_dsal_precmd() {
  # Standard Starship precmd and direnv run first; keep their snapshots intact.
  _dsal_status=${STARSHIP_CMD_STATUS:-} _dsal_pipe="${STARSHIP_PIPE_STATUS[*]:-}"
  _dsal_duration=${STARSHIP_DURATION:-} _dsal_jobs=$STARSHIP_JOBS_COUNT
  _dsal_context "$_dsal_keymap"
  return 0
}

_dsal_invalidate() {
  (( ++_dsal_epoch, ++_dsal_generation ))
  _dsal_key='' _dsal_cache_key='' _dsal_pwd='' _dsal_pending=0
  _dsal_visible=$_dsal_placeholder
  return 0
}

_dsal_line_init() {
  _dsal_edit_keymap=${KEYMAP:-} _dsal_edit_context=${CONTEXT:-}
  _dsal_context "$_dsal_edit_keymap"
  _dsal_start
  # Hook dispatch stops on nonzero. Command status is in STARSHIP_CMD_STATUS;
  # the incidental status passed into this widget must not stop later hooks.
  return 0
}

_dsal_before_redraw() {
  _dsal_edit_keymap=${KEYMAP:-} _dsal_edit_context=${CONTEXT:-}
  # Ordinary keystrokes only perform builtin comparisons.
  if [[ $PWD != $_dsal_pwd || $_dsal_edit_keymap != $_dsal_keymap ]] ||
      (( COLUMNS != _dsal_width )); then
    _dsal_context "$_dsal_edit_keymap"
    _dsal_start
  fi
  return 0
}

dsal_restore() {
  # $$ is unchanged in (subshells). Their inherited zshexit hook must never
  # delete the interactive parent's worker through an inherited PTY handle.
  (( ZSH_SUBSHELL == 0 && sysparams[pid] == _dsal_owner_pid )) || return 0
  _dsal_enabled=0 _dsal_pending=0
  PROMPT=$_dsal_original_prompt
  add-zsh-hook -d precmd _dsal_precmd
  add-zsh-hook -d preexec _dsal_invalidate
  add-zsh-hook -d chpwd _dsal_invalidate
  add-zsh-hook -d zshexit dsal_restore
  add-zle-hook-widget -d line-init _dsal_line_init
  add-zle-hook-widget -d line-pre-redraw _dsal_before_redraw
  # This worker belongs exclusively to this shell.
  if (( _dsal_worker_running )); then
    async_stop_worker "$_dsal_worker" 2>/dev/null
  fi
  _dsal_worker_running=0 _dsal_worker_env_key=''
  _dsal_active=0
  return 0
}

_dsal_enabled=1
# Only one parameter-expansion pass; rendered output is NEVER eval'd.
PROMPT='${_dsal_visible}'
add-zsh-hook precmd _dsal_precmd
add-zsh-hook preexec _dsal_invalidate
add-zsh-hook chpwd _dsal_invalidate
add-zsh-hook zshexit dsal_restore
add-zle-hook-widget line-init _dsal_line_init
add-zle-hook-widget line-pre-redraw _dsal_before_redraw
