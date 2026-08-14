#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export DOTFILES_ROOT="$ROOT"
export DOTFILES_LOG_PREFIX="macos-install"
# shellcheck source=/dev/null
. "$ROOT/scripts/sh/install-common.sh"
# shellcheck source=/dev/null
. "$ROOT/scripts/sh/hermes-agent.sh"

COMPOSE_FILE="$DOTFILES_ROOT/docker/hermes-agent/compose.yml"
DOCKER_APP="${DOTFILES_DOCKER_APP_PATH:-/Applications/Docker.app}"
DOCKER_SETUP_MARKER="${DOTFILES_DOCKER_SETUP_MARKER:-$HOME/.config/dotfiles/docker-desktop-installed}"
DOCKER_WAIT_ATTEMPTS="${DOTFILES_DOCKER_WAIT_ATTEMPTS:-120}"
VERIFY_ENVIRONMENT="${DOTFILES_VERIFY_ENVIRONMENT:-$ROOT/scripts/sh/verify-environment.sh}"
HOMEBREW_CASK_UPDATER="${DOTFILES_HOMEBREW_CASK_UPDATER:-$ROOT/scripts/sh/update-homebrew-casks.sh}"
readonly HOMEBREW_CASK_PARENT_DIR=/usr/local
readonly HOMEBREW_CASK_BIN_DIR=/usr/local/bin
readonly HOMEBREW_CASK_CLI_PLUGIN_DIR=/usr/local/cli-plugins
BASHRC_PATH="${DOTFILES_BASHRC_PATH:-/etc/bashrc}"
ZSHRC_PATH="${DOTFILES_ZSHRC_PATH:-/etc/zshrc}"
USER_PROFILE_ROOT="${DOTFILES_USER_PROFILE_ROOT:-/etc/profiles/per-user}"
HOMEBREW_BIN_DIR="${DOTFILES_HOMEBREW_BIN_DIR:-/usr/local/bin}"
HOMEBREW_CLI_PLUGINS_DIR="${DOTFILES_HOMEBREW_CLI_PLUGINS_DIR:-/usr/local/cli-plugins}"

preflight() {
  local os arch version major required
  os="$(uname -s)"
  arch="$(uname -m)"
  [[ $os == "Darwin" ]] || dotfiles_die "macOS is required (detected $os)."
  [[ $arch == "arm64" ]] || dotfiles_die "Apple Silicon is required (detected $arch)."

  version="$(sw_vers -productVersion)"
  major="${version%%.*}"
  [[ $major =~ ^[0-9]+$ ]] || dotfiles_die "Unable to parse macOS version: $version"
  ((major >= 26)) || dotfiles_die "macOS 26 or later is required (detected $version)."

  for required in \
    "$ROOT/flake.nix" \
    "$ROOT/chezmoi" \
    "$COMPOSE_FILE" \
    "$HOMEBREW_CASK_UPDATER" \
    "$VERIFY_ENVIRONMENT"; do
    [[ -e $required ]] || dotfiles_die "Required repository path is missing: $required"
  done
}

ensure_command_line_tools() {
  if xcode-select -p >/dev/null 2>&1; then
    return
  fi

  xcode-select --install || true
  dotfiles_die "Command Line Tools installation was requested. Complete it, then rerun ./install.sh."
}

ensure_nix() {
  dotfiles_load_nix
  if ! dotfiles_have nix; then
    dotfiles_log "Installing Nix in multi-user daemon mode..."
    curl -fsSL https://nixos.org/nix/install | sh -s -- --daemon
    dotfiles_load_nix
  fi

  dotfiles_have nix || dotfiles_die "Nix installation completed but nix is unavailable."
  mkdir -p "$HOME/.config/nix"
  local feature_line="extra-experimental-features = nix-command flakes"
  touch "$HOME/.config/nix/nix.conf"
  grep -Fxq "$feature_line" "$HOME/.config/nix/nix.conf" ||
    printf '%s\n' "$feature_line" >>"$HOME/.config/nix/nix.conf"
}

preserve_shell_rc_for_nix_darwin() {
  local rc backup
  for rc in "$BASHRC_PATH" "$ZSHRC_PATH"; do
    [[ -e $rc || -L $rc ]] || continue
    [[ -L $rc ]] && continue

    backup="$rc.before-nix-darwin"
    [[ ! -e $backup && ! -L $backup ]] ||
      dotfiles_die "Refusing to overwrite existing nix-darwin backup: $backup"

    dotfiles_log "Preserving existing $rc as $backup..."
    sudo mv "$rc" "$backup"
  done
}

stop_existing_docker_desktop() {
  local docker_cli="$DOCKER_APP/Contents/Resources/bin/docker"
  [[ -x $docker_cli ]] || return 0
  if ! pgrep -x com.docker.backend >/dev/null 2>&1 &&
    ! pgrep -x "Docker Desktop" >/dev/null 2>&1; then
    return 0
  fi

  dotfiles_log "Stopping Docker Desktop before declarative cask activation..."
  "$docker_cli" desktop stop --timeout 120
}

repair_homebrew_cask_link_directories() {
  local directory user="${DOTFILES_USER:-${SUDO_USER:-$USER}}"
  local directories=("$HOMEBREW_BIN_DIR" "$HOMEBREW_CLI_PLUGINS_DIR")
  [[ -n $user ]] || dotfiles_die "Unable to determine the Homebrew cask link directory owner."

  for directory in "${directories[@]}"; do
    if [[ -L $directory || (-e $directory && ! -d $directory) ]]; then
      dotfiles_die "Homebrew cask link directory must be a real directory: $directory"
    fi
  done

  for directory in "${directories[@]}"; do
    if [[ ! -e $directory ]]; then
      sudo /bin/mkdir -- "$directory"
    fi
    sudo /usr/sbin/chown "${user}:admin" "$directory"
    sudo /bin/chmod 0775 "$directory"
  done
}

apply_darwin_system() {
  export DOTFILES_USER="${SUDO_USER:-$USER}"
  export DOTFILES_HOME="$HOME"
  local nix_bin
  nix_bin="$(command -v nix)"

  dotfiles_log "Applying nix-darwin, nix-homebrew, and Home Manager..."
  (
    cd "$ROOT"
    sudo /usr/bin/env \
      "NIX_CONFIG=extra-experimental-features = nix-command flakes" \
      "DOTFILES_USER=$DOTFILES_USER" \
      "DOTFILES_HOME=$DOTFILES_HOME" \
      "DOTFILES_ROOT=$DOTFILES_ROOT" \
      "$nix_bin" run .#darwin-rebuild -- switch --flake .#macos --impure
  )

  export PATH="/run/current-system/sw/bin:$USER_PROFILE_ROOT/$DOTFILES_USER/bin:$HOME/.nix-profile/bin:$HOME/.local/state/nix/profile/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$DOCKER_APP/Contents/Resources/bin:$PATH"
  hash -r
}

homebrew_cask_link_parent_metadata() {
  /usr/bin/stat -f '%u %Lp' "$1"
}

homebrew_cask_link_parent_acl_state() {
  local parent="$1" matches

  matches="$(/usr/bin/find "$parent" -maxdepth 0 -acl -print)" || return
  if [[ -n $matches ]]; then
    printf 'present\n'
  else
    printf 'absent\n'
  fi
}

homebrew_cask_link_parent_is_immutable_to_caller() {
  local parent="$1"

  [[ ! -w $parent ]]
}

validate_homebrew_cask_link_parent_directory() {
  local parent="$1" metadata owner mode acl_state

  [[ ! -L $parent ]] ||
    dotfiles_die "Refusing symbolic Homebrew cask link parent: $parent"
  [[ -d $parent ]] ||
    dotfiles_die "Homebrew cask link parent is not a directory: $parent"

  metadata="$(homebrew_cask_link_parent_metadata "$parent")" ||
    dotfiles_die "Unable to inspect Homebrew cask link parent: $parent"
  read -r owner mode <<<"$metadata"
  [[ $owner == 0 ]] ||
    dotfiles_die "Homebrew cask link parent must be owned by root: $parent"
  [[ $mode =~ ^[0-7]{3,4}$ ]] ||
    dotfiles_die "Unable to parse Homebrew cask link parent mode: $parent ($mode)"
  (((8#$mode & 0022) == 0)) ||
    dotfiles_die "Homebrew cask link parent must not be group/other writable: $parent"

  acl_state="$(homebrew_cask_link_parent_acl_state "$parent")" ||
    dotfiles_die "Unable to inspect Homebrew cask link parent ACL: $parent"
  case "$acl_state" in
  absent) ;;
  present) dotfiles_die "Homebrew cask link parent must not have an extended ACL: $parent" ;;
  *) dotfiles_die "Unable to determine Homebrew cask link parent ACL state: $parent" ;;
  esac

  homebrew_cask_link_parent_is_immutable_to_caller "$parent" ||
    dotfiles_die "Homebrew cask link parent must not be writable by the current caller: $parent"
}

validate_homebrew_cask_link_directory() {
  local parent="$1" directory="$2"

  [[ ${directory%/*} == "$parent" ]] ||
    dotfiles_die "Homebrew cask link directory is outside its fixed parent: $directory"
  [[ ! -L $directory ]] ||
    dotfiles_die "Refusing symbolic Homebrew cask link directory: $directory"
  [[ ! -e $directory || -d $directory ]] ||
    dotfiles_die "Homebrew cask link path is not a directory: $directory"
}

ensure_homebrew_cask_link_directory() {
  local parent="$1" directory="$2"

  validate_homebrew_cask_link_parent_directory "$parent"
  validate_homebrew_cask_link_directory "$parent" "$directory"

  if [[ ! -e $directory ]]; then
    sudo /bin/mkdir -- "$directory"
  fi
  sudo /usr/sbin/chown "$DOTFILES_USER:admin" "$directory"
  sudo /bin/chmod 0775 "$directory"
}

ensure_homebrew_cask_link_directories_under_parent() {
  local parent="$1" bin_directory="$2" cli_plugin_directory="$3"

  [[ $bin_directory == "$parent/bin" && $cli_plugin_directory == "$parent/cli-plugins" ]] ||
    dotfiles_die "Unexpected Homebrew cask link directory allowlist."

  dotfiles_log "Converging Homebrew cask link directory permissions..."
  validate_homebrew_cask_link_parent_directory "$parent"
  validate_homebrew_cask_link_directory "$parent" "$bin_directory"
  validate_homebrew_cask_link_directory "$parent" "$cli_plugin_directory"
  ensure_homebrew_cask_link_directory "$parent" "$bin_directory"
  ensure_homebrew_cask_link_directory "$parent" "$cli_plugin_directory"
}

ensure_homebrew_cask_link_directories() {
  ensure_homebrew_cask_link_directories_under_parent \
    "$HOMEBREW_CASK_PARENT_DIR" \
    "$HOMEBREW_CASK_BIN_DIR" \
    "$HOMEBREW_CASK_CLI_PLUGIN_DIR"
}

docker_desktop_md5_link_state() {
  local md5_binary="$1" md5_link="$2"
  if [[ -L $md5_link && $(/usr/bin/readlink "$md5_link") == "$md5_binary" ]]; then
    printf 'expected-link\n'
  elif [[ -e $md5_link || -L $md5_link ]]; then
    printf 'conflict\n'
  else
    printf 'missing\n'
  fi
}

docker_desktop_md5_binary_is_executable() {
  [[ -x /sbin/md5 ]]
}

ensure_docker_desktop_md5_compatibility() {
  local md5_binary=/sbin/md5 md5_link=/usr/local/bin/md5 state
  docker_desktop_md5_binary_is_executable || dotfiles_die "macOS md5 executable is unavailable: $md5_binary"
  state="$(docker_desktop_md5_link_state "$md5_binary" "$md5_link")"
  case "$state" in
  expected-link) return 0 ;;
  missing) sudo /bin/ln -s /sbin/md5 /usr/local/bin/md5 ;;
  conflict) dotfiles_die "Docker Desktop md5 compatibility path conflicts with existing entry: $md5_link" ;;
  *) dotfiles_die "Unable to determine Docker Desktop md5 compatibility path state: $md5_link" ;;
  esac
}

setup_docker_runtime() {
  [[ -d $DOCKER_APP ]] ||
    dotfiles_die "Docker Desktop was not installed by nix-darwin: $DOCKER_APP"

  local installer="$DOCKER_APP/Contents/MacOS/install"
  [[ -x $installer ]] || dotfiles_die "Docker Desktop installer not found: $installer"

  ensure_docker_desktop_md5_compatibility

  if [[ ! -f $DOCKER_SETUP_MARKER ]]; then
    dotfiles_log "Accepting the Docker Desktop license for personal use..."
    sudo "$installer" --accept-license --user="${SUDO_USER:-$USER}"
    mkdir -p "$(dirname "$DOCKER_SETUP_MARKER")"
    touch "$DOCKER_SETUP_MARKER"
  fi

  dotfiles_have docker || dotfiles_die "Docker CLI is unavailable after nix-darwin activation."
  if ! docker info >/dev/null 2>&1; then
    docker desktop start --timeout 120
    dotfiles_wait_for "$DOCKER_WAIT_ATTEMPTS" "Docker Desktop engine" docker info
  fi
  docker compose version >/dev/null
}

apply_chezmoi() {
  dotfiles_have chezmoi || dotfiles_die "chezmoi is unavailable after nix-darwin activation."
  chezmoi init --source "$ROOT/chezmoi"
  chezmoi apply --force
}

main() {
  preflight
  ensure_command_line_tools
  ensure_nix
  dotfiles_link_checkout "$ROOT"
  dotfiles_update_flake "$ROOT"
  preserve_shell_rc_for_nix_darwin
  stop_existing_docker_desktop
  repair_homebrew_cask_link_directories
  apply_darwin_system
  dotfiles_install_herdr
  ensure_homebrew_cask_link_directories
  "$HOMEBREW_CASK_UPDATER"
  setup_docker_runtime
  apply_chezmoi
  dotfiles_hermes_start_stack docker "$DOTFILES_ROOT/docker/hermes-agent/compose.yml"
  "$VERIFY_ENVIRONMENT" --runtime
  dotfiles_log "macOS setup complete."
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
