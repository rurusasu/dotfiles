#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export DOTFILES_ROOT="$ROOT"
export DOTFILES_LOG_PREFIX="macos-install"
# The native macOS CLI uses the desktop app integration for biometric sign-in.
# Keep an explicit opt-out for troubleshooting, but make the integration
# available to chezmoi deploy scripts by default.
if [[ -z ${OP_BIOMETRIC_UNLOCK_ENABLED+x} ]]; then
  OP_BIOMETRIC_UNLOCK_ENABLED="${DOTFILES_OP_BIOMETRIC_UNLOCK_ENABLED:-true}"
fi
export OP_BIOMETRIC_UNLOCK_ENABLED
# shellcheck source=/dev/null
. "$ROOT/scripts/sh/install-common.sh"

COMPOSE_FILE="$DOTFILES_ROOT/docker/hermes-service/compose.yml"
HINDSIGHT_COMPOSE_FILE="$DOTFILES_ROOT/docker/local-ai-services/compose.yml"
DOCKER_APP="${DOTFILES_DOCKER_APP_PATH:-/Applications/Docker.app}"
LEGACY_DOCKER_APP="${DOTFILES_LEGACY_DOCKER_APP_PATH:-/Applications/Nix Apps/Docker.app}"
DOCKER_SETUP_MARKER="${DOTFILES_DOCKER_SETUP_MARKER:-$HOME/.config/dotfiles/docker-desktop-installed}"
DOCKER_WAIT_ATTEMPTS="${DOTFILES_DOCKER_WAIT_ATTEMPTS:-120}"
DOCKER_PROBE_TIMEOUT_SECONDS="${DOTFILES_DOCKER_PROBE_TIMEOUT_SECONDS:-5}"
DOTFILES_ACCEPT_DOCKER_LICENSE="${DOTFILES_ACCEPT_DOCKER_LICENSE:-0}"
DOCKER_CASK_TOKEN="${DOTFILES_DOCKER_CASK_TOKEN:-docker-desktop}"
OLLAMA_COMMAND="${DOTFILES_OLLAMA_COMMAND:-ollama}"
LAUNCHCTL_COMMAND="${DOTFILES_LAUNCHCTL_COMMAND:-/bin/launchctl}"
OPEN_COMMAND="${DOTFILES_OPEN_COMMAND:-/usr/bin/open}"
OLLAMA_API_URL="${DOTFILES_OLLAMA_API_URL:-http://127.0.0.1:11434/api/tags}"
OLLAMA_WAIT_ATTEMPTS="${DOTFILES_OLLAMA_WAIT_ATTEMPTS:-60}"
VERIFY_ENVIRONMENT="${DOTFILES_VERIFY_ENVIRONMENT:-$ROOT/scripts/sh/verify-environment.sh}"
DARWIN_MIGRATION="${DOTFILES_DARWIN_MIGRATION:-$ROOT/scripts/sh/migrate-darwin-provider.sh}"
readonly HOMEBREW_CASK_PARENT_DIR=/usr/local
readonly HOMEBREW_CASK_BIN_DIR=/usr/local/bin
readonly HOMEBREW_CASK_CLI_PLUGIN_DIR=/usr/local/cli-plugins
WEZTERM_CASK_TOKEN="${DOTFILES_WEZTERM_CASK_TOKEN:-wezterm@nightly}"
WEZTERM_APP_PATH="${DOTFILES_WEZTERM_APP_PATH:-/Applications/WezTerm.app}"
WEZTERM_BIN_DIR="${DOTFILES_WEZTERM_BIN_DIR:-/opt/homebrew/bin}"
WEZTERM_BASH_COMPLETION_PATH="${DOTFILES_WEZTERM_BASH_COMPLETION_PATH:-/opt/homebrew/etc/bash_completion.d/wezterm}"
WEZTERM_FISH_COMPLETION_PATH="${DOTFILES_WEZTERM_FISH_COMPLETION_PATH:-/opt/homebrew/share/fish/vendor_completions.d/wezterm.fish}"
WEZTERM_ZSH_COMPLETION_PATH="${DOTFILES_WEZTERM_ZSH_COMPLETION_PATH:-/opt/homebrew/share/zsh/site-functions/_wezterm}"
WEZTERM_MIGRATION_BACKUP_DIR="${DOTFILES_WEZTERM_MIGRATION_BACKUP_DIR:-$HOME/Library/Application Support/dotfiles/migrations}"
BASHRC_PATH="${DOTFILES_BASHRC_PATH:-/etc/bashrc}"
ZSHRC_PATH="${DOTFILES_ZSHRC_PATH:-/etc/zshrc}"
USER_PROFILE_ROOT="${DOTFILES_USER_PROFILE_ROOT:-/etc/profiles/per-user}"
HOMEBREW_BIN_DIR="${DOTFILES_HOMEBREW_BIN_DIR:-/usr/local/bin}"
HOMEBREW_CLI_PLUGINS_DIR="${DOTFILES_HOMEBREW_CLI_PLUGINS_DIR:-/usr/local/cli-plugins}"
DOTFILES_WITH_OLLAMA=0
DOTFILES_WITH_DOCKER=0
DOTFILES_WITH_HERMES=0
DOCKER_CASK_REPAIR_REQUIRED=0
DOCKER_CASK_LINK_TRANSACTION_ACTIVE=0
DOCKER_CASK_LINK_TRANSACTION_COUNT=0
readonly DOCKER_CASK_LINK_BACKUP_SUFFIX=.dotfiles-cask-migration-backup
DOCKER_CASK_LINK_PATHS=()
DOCKER_CASK_LINK_BACKUP_PATHS=()
DOCKER_CASK_LINK_ORIGINAL_STATES=()
DOCKER_CASK_LINK_ORIGINAL_TARGETS=()
DOCKER_CASK_LINK_CURRENT_TARGETS=()
DOCKER_CASK_LINK_LEGACY_TARGETS=()

usage() {
  cat <<'EOF'
Usage: ./install.sh [--with-ollama | --with-docker | --with-hermes]

  --with-ollama  Install and update Ollama.
  --with-docker  Include Ollama, Docker Desktop, and independent Hindsight.
  --with-hermes  Include native Hermes Desktop, the Docker Agent/Dashboard,
                  Chrome, and Discord (Dashboard: http://127.0.0.1:9119).
EOF
}

resolve_install_profile() {
  while (($# > 0)); do
    case "$1" in
    --with-ollama) DOTFILES_WITH_OLLAMA=1 ;;
    --with-docker) DOTFILES_WITH_DOCKER=1 ;;
    --with-hermes) DOTFILES_WITH_HERMES=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) dotfiles_die "Unknown argument: $1" ;;
    esac
    shift
  done

  if ((DOTFILES_WITH_HERMES == 1)); then
    DOTFILES_WITH_DOCKER=1
  fi
  if ((DOTFILES_WITH_DOCKER == 1)); then
    DOTFILES_WITH_OLLAMA=1
  fi
  export DOTFILES_WITH_OLLAMA DOTFILES_WITH_DOCKER DOTFILES_WITH_HERMES
}

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

  local -a required_paths=(
    "$ROOT/flake.nix"
    "$ROOT/chezmoi"
    "$VERIFY_ENVIRONMENT"
    "$DARWIN_MIGRATION"
  )
  if ((DOTFILES_WITH_DOCKER == 1)); then
    required_paths+=("$HINDSIGHT_COMPOSE_FILE")
  fi
  if ((DOTFILES_WITH_HERMES == 1)); then
    required_paths+=("$COMPOSE_FILE")
  fi

  for required in "${required_paths[@]}"; do
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
  local app docker_cli
  for app in "$LEGACY_DOCKER_APP" "$DOCKER_APP"; do
    docker_cli="$app/Contents/Resources/bin/docker"
    [[ -x $docker_cli ]] || continue
    if ! pgrep -x com.docker.backend >/dev/null 2>&1 &&
      ! pgrep -x "Docker Desktop" >/dev/null 2>&1; then
      return 0
    fi

    dotfiles_log "Stopping Docker Desktop before declarative cask activation..."
    "$docker_cli" desktop stop --timeout 120
    return 0
  done
}

docker_desktop_link_state() {
  local link_path="$1" current_target="$2" legacy_target="$3" link_target

  if [[ -L $link_path ]]; then
    link_target="$(/usr/bin/readlink "$link_path")"
    if [[ $link_target == "$current_target" ]]; then
      printf 'current-cask\n'
    elif [[ $link_target == "$legacy_target" ]]; then
      printf 'legacy\n'
    else
      printf 'conflicting\n'
    fi
  elif [[ -e $link_path ]]; then
    printf 'conflicting\n'
  else
    printf 'missing\n'
  fi
}

rollback_docker_desktop_cask_links() {
  local exit_status="${1:-1}" index link_path backup_path original_state original_target
  local current_target legacy_target state replacement_target rollback_failed=0

  trap - EXIT
  ((DOCKER_CASK_LINK_TRANSACTION_ACTIVE == 1)) || exit "$exit_status"
  set +e
  dotfiles_log "Restoring Docker Desktop links after failed cask activation..."

  for ((index = DOCKER_CASK_LINK_TRANSACTION_COUNT - 1; index >= 0; index--)); do
    link_path="${DOCKER_CASK_LINK_PATHS[$index]}"
    backup_path="${DOCKER_CASK_LINK_BACKUP_PATHS[$index]}"
    original_state="${DOCKER_CASK_LINK_ORIGINAL_STATES[$index]}"
    original_target="${DOCKER_CASK_LINK_ORIGINAL_TARGETS[$index]}"
    current_target="${DOCKER_CASK_LINK_CURRENT_TARGETS[$index]}"
    legacy_target="${DOCKER_CASK_LINK_LEGACY_TARGETS[$index]}"

    if [[ $original_state == missing ]]; then
      state="$(docker_desktop_link_state "$link_path" "$current_target" "$legacy_target")"
      case "$state" in
      missing) ;;
      current-cask | legacy)
        replacement_target="$(/usr/bin/readlink "$link_path" 2>/dev/null)"
        if [[ $replacement_target != "$current_target" && $replacement_target != "$legacy_target" ]]; then
          printf 'Refusing to remove unexpected Docker Desktop rollback target: %s\n' "$link_path" >&2
          rollback_failed=1
          continue
        fi
        if ! sudo /bin/rm -f -- "$link_path"; then
          rollback_failed=1
        fi
        ;;
      conflicting | *)
        printf 'Refusing to remove Docker Desktop rollback conflict: %s\n' "$link_path" >&2
        rollback_failed=1
        ;;
      esac
      continue
    fi

    if [[ $original_state != staged ]]; then
      printf 'Unable to determine original Docker Desktop link state: %s\n' "$link_path" >&2
      rollback_failed=1
      continue
    fi

    if [[ ! -L $backup_path ]] ||
      [[ $(/usr/bin/readlink "$backup_path" 2>/dev/null) != "$original_target" ]]; then
      printf 'Unable to safely restore Docker Desktop link backup: %s\n' "$backup_path" >&2
      rollback_failed=1
      continue
    fi

    if [[ -L $link_path ]] &&
      [[ $(/usr/bin/readlink "$link_path" 2>/dev/null) == "$original_target" ]]; then
      if ! sudo /bin/rm -f -- "$backup_path"; then
        rollback_failed=1
      fi
      continue
    fi

    state="$(docker_desktop_link_state "$link_path" "$current_target" "$legacy_target")"
    case "$state" in
    missing) ;;
    current-cask | legacy)
      replacement_target="$(/usr/bin/readlink "$link_path" 2>/dev/null)"
      if [[ $replacement_target != "$current_target" && $replacement_target != "$legacy_target" ]]; then
        printf 'Refusing to remove unexpected Docker Desktop rollback target: %s\n' "$link_path" >&2
        rollback_failed=1
        continue
      fi
      if ! sudo /bin/rm -f -- "$link_path"; then
        rollback_failed=1
        continue
      fi
      ;;
    conflicting | *)
      printf 'Refusing to overwrite Docker Desktop rollback conflict: %s\n' "$link_path" >&2
      rollback_failed=1
      continue
      ;;
    esac

    if ! sudo /bin/mv -n -- "$backup_path" "$link_path" ||
      [[ ! -L $link_path ]] ||
      [[ $(/usr/bin/readlink "$link_path" 2>/dev/null) != "$original_target" ]]; then
      printf 'Unable to restore Docker Desktop link: %s\n' "$link_path" >&2
      rollback_failed=1
    fi
  done

  DOCKER_CASK_LINK_TRANSACTION_ACTIVE=0
  if ((rollback_failed == 1)); then
    dotfiles_log "Docker Desktop link rollback was incomplete; preserved safe backups for recovery."
  fi
  exit "$exit_status"
}

commit_docker_desktop_cask_links() {
  local index backup_path original_state original_target

  trap - EXIT
  DOCKER_CASK_LINK_TRANSACTION_ACTIVE=0
  for ((index = 0; index < DOCKER_CASK_LINK_TRANSACTION_COUNT; index++)); do
    backup_path="${DOCKER_CASK_LINK_BACKUP_PATHS[$index]}"
    original_state="${DOCKER_CASK_LINK_ORIGINAL_STATES[$index]}"
    original_target="${DOCKER_CASK_LINK_ORIGINAL_TARGETS[$index]}"
    [[ $original_state == missing ]] && continue
    [[ $original_state == staged ]] ||
      dotfiles_die "Unable to determine original Docker Desktop link state during commit."
    [[ -L $backup_path ]] &&
      [[ $(/usr/bin/readlink "$backup_path") == "$original_target" ]] ||
      dotfiles_die "Refusing to remove unexpected Docker Desktop link backup: $backup_path"
    sudo /bin/rm -f -- "$backup_path"
  done
  DOCKER_CASK_LINK_TRANSACTION_COUNT=0
  DOCKER_CASK_LINK_PATHS=()
  DOCKER_CASK_LINK_BACKUP_PATHS=()
  DOCKER_CASK_LINK_ORIGINAL_STATES=()
  DOCKER_CASK_LINK_ORIGINAL_TARGETS=()
  DOCKER_CASK_LINK_CURRENT_TARGETS=()
  DOCKER_CASK_LINK_LEGACY_TARGETS=()
}

prepare_docker_desktop_cask_links() {
  local backup_path cask_state current_target legacy_target link_path original_state original_target
  local state suffix index links_to_remove_count=0 missing_links_count=0 transaction_count=0
  local -a links_to_remove missing_links
  local -a required_paths=(
    "$HOMEBREW_BIN_DIR/docker"
    "$HOMEBREW_BIN_DIR/docker-credential-desktop"
    "$HOMEBREW_BIN_DIR/docker-credential-ecr-login"
    "$HOMEBREW_BIN_DIR/docker-credential-osxkeychain"
    "$HOMEBREW_BIN_DIR/kubectl.docker"
    "$HOMEBREW_CLI_PLUGINS_DIR/docker-compose"
  )
  local -a required_suffixes=(
    "/bin/docker"
    "/bin/docker-credential-desktop"
    "/bin/docker-credential-ecr-login"
    "/bin/docker-credential-osxkeychain"
    "/bin/kubectl"
    "/cli-plugins/docker-compose"
  )
  local optional_kubectl="$HOMEBREW_BIN_DIR/kubectl"
  local obsolete_compose="$HOMEBREW_BIN_DIR/docker-compose"

  cask_state="$(homebrew_cask_install_state_before_activation "$DOCKER_CASK_TOKEN")" ||
    dotfiles_die "Unable to inspect Homebrew cask state for $DOCKER_CASK_TOKEN."
  DOCKER_CASK_REPAIR_REQUIRED=0

  for index in "${!required_paths[@]}"; do
    link_path="${required_paths[$index]}"
    suffix="${required_suffixes[$index]}"
    state="$(docker_desktop_link_state \
      "$link_path" \
      "$DOCKER_APP/Contents/Resources$suffix" \
      "$LEGACY_DOCKER_APP/Contents/Resources$suffix")"
    case "$state" in
    current-cask)
      if [[ $cask_state == absent ]]; then
        links_to_remove[links_to_remove_count]="$link_path"
        ((links_to_remove_count += 1))
      fi
      ;;
    legacy)
      links_to_remove[links_to_remove_count]="$link_path"
      ((links_to_remove_count += 1))
      [[ $cask_state == absent ]] || DOCKER_CASK_REPAIR_REQUIRED=1
      ;;
    missing)
      [[ $cask_state == absent ]] || DOCKER_CASK_REPAIR_REQUIRED=1
      missing_links[missing_links_count]="$link_path"
      ((missing_links_count += 1))
      ;;
    conflicting) dotfiles_die "Refusing to replace Docker Desktop link conflict: $link_path" ;;
    *) dotfiles_die "Unable to classify Docker Desktop link: $link_path" ;;
    esac
  done

  state="$(docker_desktop_link_state \
    "$optional_kubectl" \
    "$DOCKER_APP/Contents/Resources/bin/kubectl" \
    "$LEGACY_DOCKER_APP/Contents/Resources/bin/kubectl")"
  case "$state" in
  current-cask)
    if [[ $cask_state == absent ]]; then
      links_to_remove[links_to_remove_count]="$optional_kubectl"
      ((links_to_remove_count += 1))
    fi
    ;;
  legacy)
    links_to_remove[links_to_remove_count]="$optional_kubectl"
    ((links_to_remove_count += 1))
    [[ $cask_state == absent ]] || DOCKER_CASK_REPAIR_REQUIRED=1
    ;;
  missing)
    missing_links[missing_links_count]="$optional_kubectl"
    ((missing_links_count += 1))
    ;;
  conflicting) dotfiles_die "Refusing to replace Docker Desktop link conflict: $optional_kubectl" ;;
  *) dotfiles_die "Unable to classify Docker Desktop link: $optional_kubectl" ;;
  esac

  state="$(docker_desktop_link_state \
    "$obsolete_compose" \
    "$DOCKER_APP/Contents/Resources/cli-plugins/docker-compose" \
    "$LEGACY_DOCKER_APP/Contents/Resources/cli-plugins/docker-compose")"
  case "$state" in
  current-cask | legacy)
    links_to_remove[links_to_remove_count]="$obsolete_compose"
    ((links_to_remove_count += 1))
    ;;
  missing)
    missing_links[missing_links_count]="$obsolete_compose"
    ((missing_links_count += 1))
    ;;
  conflicting) dotfiles_die "Refusing to replace Docker Desktop link conflict: $obsolete_compose" ;;
  *) dotfiles_die "Unable to classify Docker Desktop link: $obsolete_compose" ;;
  esac

  for ((index = 0; index < links_to_remove_count; index++)); do
    DOCKER_CASK_LINK_PATHS[transaction_count]="${links_to_remove[$index]}"
    DOCKER_CASK_LINK_ORIGINAL_STATES[transaction_count]=staged
    ((transaction_count += 1))
  done
  for ((index = 0; index < missing_links_count; index++)); do
    DOCKER_CASK_LINK_PATHS[transaction_count]="${missing_links[$index]}"
    DOCKER_CASK_LINK_ORIGINAL_STATES[transaction_count]=missing
    ((transaction_count += 1))
  done

  DOCKER_CASK_LINK_TRANSACTION_COUNT="$transaction_count"
  for ((index = 0; index < transaction_count; index++)); do
    link_path="${DOCKER_CASK_LINK_PATHS[$index]}"
    original_state="${DOCKER_CASK_LINK_ORIGINAL_STATES[$index]}"
    backup_path="$link_path$DOCKER_CASK_LINK_BACKUP_SUFFIX"
    [[ ! -e $backup_path && ! -L $backup_path ]] ||
      dotfiles_die "Refusing to overwrite Docker Desktop link backup: $backup_path"
    if [[ $original_state == staged ]]; then
      original_target="$(/usr/bin/readlink "$link_path")"
    else
      original_target=
    fi
    suffix="${link_path#"$HOMEBREW_BIN_DIR"}"
    case "$link_path" in
    "$HOMEBREW_CLI_PLUGINS_DIR/docker-compose")
      current_target="$DOCKER_APP/Contents/Resources/cli-plugins/docker-compose"
      legacy_target="$LEGACY_DOCKER_APP/Contents/Resources/cli-plugins/docker-compose"
      ;;
    "$HOMEBREW_BIN_DIR/docker-compose")
      current_target="$DOCKER_APP/Contents/Resources/cli-plugins/docker-compose"
      legacy_target="$LEGACY_DOCKER_APP/Contents/Resources/cli-plugins/docker-compose"
      ;;
    "$HOMEBREW_BIN_DIR/kubectl" | "$HOMEBREW_BIN_DIR/kubectl.docker")
      current_target="$DOCKER_APP/Contents/Resources/bin/kubectl"
      legacy_target="$LEGACY_DOCKER_APP/Contents/Resources/bin/kubectl"
      ;;
    *)
      current_target="$DOCKER_APP/Contents/Resources/bin$suffix"
      legacy_target="$LEGACY_DOCKER_APP/Contents/Resources/bin$suffix"
      ;;
    esac
    DOCKER_CASK_LINK_PATHS[index]="$link_path"
    DOCKER_CASK_LINK_BACKUP_PATHS[index]="$backup_path"
    DOCKER_CASK_LINK_ORIGINAL_STATES[index]="$original_state"
    DOCKER_CASK_LINK_ORIGINAL_TARGETS[index]="$original_target"
    DOCKER_CASK_LINK_CURRENT_TARGETS[index]="$current_target"
    DOCKER_CASK_LINK_LEGACY_TARGETS[index]="$legacy_target"
  done

  ((transaction_count > 0)) || return 0
  DOCKER_CASK_LINK_TRANSACTION_ACTIVE=1
  trap 'rollback_docker_desktop_cask_links "$?"' EXIT
  for ((index = 0; index < transaction_count; index++)); do
    [[ ${DOCKER_CASK_LINK_ORIGINAL_STATES[$index]} == staged ]] || continue
    link_path="${DOCKER_CASK_LINK_PATHS[$index]}"
    backup_path="${DOCKER_CASK_LINK_BACKUP_PATHS[$index]}"
    original_target="${DOCKER_CASK_LINK_ORIGINAL_TARGETS[$index]}"
    sudo /bin/mv -n -- "$link_path" "$backup_path"
    [[ ! -e $link_path && ! -L $link_path && -L $backup_path ]] &&
      [[ $(/usr/bin/readlink "$backup_path") == "$original_target" ]] ||
      dotfiles_die "Unable to safely stage Docker Desktop link: $link_path"
  done
}

verify_docker_desktop_cask_links() {
  local cask_state link_path state suffix index
  local -a required_paths=(
    "$HOMEBREW_BIN_DIR/docker"
    "$HOMEBREW_BIN_DIR/docker-credential-desktop"
    "$HOMEBREW_BIN_DIR/docker-credential-ecr-login"
    "$HOMEBREW_BIN_DIR/docker-credential-osxkeychain"
    "$HOMEBREW_BIN_DIR/kubectl.docker"
    "$HOMEBREW_CLI_PLUGINS_DIR/docker-compose"
  )
  local -a required_suffixes=(
    "/bin/docker"
    "/bin/docker-credential-desktop"
    "/bin/docker-credential-ecr-login"
    "/bin/docker-credential-osxkeychain"
    "/bin/kubectl"
    "/cli-plugins/docker-compose"
  )

  cask_state="$(homebrew_cask_install_state "$DOCKER_CASK_TOKEN")" ||
    dotfiles_die "Unable to inspect Homebrew cask state for $DOCKER_CASK_TOKEN after activation."
  [[ $cask_state == installed ]] ||
    dotfiles_die "Homebrew cask was not installed after activation: $DOCKER_CASK_TOKEN"

  for index in "${!required_paths[@]}"; do
    link_path="${required_paths[$index]}"
    suffix="${required_suffixes[$index]}"
    state="$(docker_desktop_link_state \
      "$link_path" \
      "$DOCKER_APP/Contents/Resources$suffix" \
      "$LEGACY_DOCKER_APP/Contents/Resources$suffix")"
    [[ $state == current-cask ]] ||
      dotfiles_die "Docker Desktop cask link did not converge: $link_path ($state)"
  done

  link_path="$HOMEBREW_BIN_DIR/docker-compose"
  state="$(docker_desktop_link_state \
    "$link_path" \
    "$DOCKER_APP/Contents/Resources/cli-plugins/docker-compose" \
    "$LEGACY_DOCKER_APP/Contents/Resources/cli-plugins/docker-compose")"
  [[ $state == missing ]] ||
    dotfiles_die "Obsolete Docker Desktop link remains after activation: $link_path ($state)"

  link_path="$HOMEBREW_BIN_DIR/kubectl"
  state="$(docker_desktop_link_state \
    "$link_path" \
    "$DOCKER_APP/Contents/Resources/bin/kubectl" \
    "$LEGACY_DOCKER_APP/Contents/Resources/bin/kubectl")"
  case "$state" in
  current-cask | missing) ;;
  legacy | conflicting) dotfiles_die "Docker Desktop optional cask link did not converge: $link_path ($state)" ;;
  *) dotfiles_die "Unable to classify Docker Desktop link: $link_path" ;;
  esac
}

repair_and_verify_docker_desktop_cask() {
  local brew_command

  if ((DOCKER_CASK_REPAIR_REQUIRED == 1)); then
    brew_command="$(homebrew_command)" ||
      dotfiles_die "Homebrew is unavailable for Docker Desktop cask repair."
    dotfiles_log "Repairing Docker Desktop Homebrew cask artifacts..."
    "$brew_command" reinstall --cask "$DOCKER_CASK_TOKEN"
  fi

  verify_docker_desktop_cask_links
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
      "DOTFILES_WITH_OLLAMA=$DOTFILES_WITH_OLLAMA" \
      "DOTFILES_WITH_DOCKER=$DOTFILES_WITH_DOCKER" \
      "DOTFILES_WITH_HERMES=$DOTFILES_WITH_HERMES" \
      "$nix_bin" run .#darwin-rebuild -- switch --flake .#macos --impure
  )

  export PATH="$DOCKER_APP/Contents/Resources/bin:/run/current-system/sw/bin:$USER_PROFILE_ROOT/$DOTFILES_USER/bin:$HOME/.nix-profile/bin:$HOME/.local/state/nix/profile/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
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

homebrew_command() {
  if [[ -n ${DOTFILES_BREW_COMMAND:-} ]]; then
    printf '%s\n' "$DOTFILES_BREW_COMMAND"
  elif command -v brew >/dev/null 2>&1; then
    command -v brew
  elif [[ -x /opt/homebrew/bin/brew ]]; then
    printf '%s\n' /opt/homebrew/bin/brew
  elif [[ -x /usr/local/bin/brew ]]; then
    printf '%s\n' /usr/local/bin/brew
  else
    return 1
  fi
}

homebrew_cask_install_state() {
  local token="$1" brew_command output status
  brew_command="$(homebrew_command)" || {
    printf 'Homebrew command is unavailable.\n' >&2
    return 2
  }

  if output="$("$brew_command" list --cask --versions "$token" 2>&1)"; then
    status=0
  else
    status=$?
  fi

  case "$status" in
  0)
    [[ -n $output ]] || {
      printf 'Homebrew returned an empty installed-cask result for %s.\n' "$token" >&2
      return 2
    }
    printf 'installed\n'
    ;;
  1)
    [[ -z $output ]] || {
      printf 'Homebrew cask inspection failed for %s: %s\n' "$token" "$output" >&2
      return 2
    }
    printf 'absent\n'
    ;;
  *)
    printf 'Homebrew cask inspection failed for %s with status %s: %s\n' \
      "$token" "$status" "$output" >&2
    return 2
    ;;
  esac
}

homebrew_cask_install_state_before_activation() {
  local token="$1"

  # nix-darwin provisions nix-homebrew below, so a fresh host may not have a
  # Homebrew command yet. Treat that pre-activation state as an absent cask,
  # while preserving strict inspection errors once Homebrew is available.
  if ! homebrew_command >/dev/null 2>&1; then
    printf 'absent\n'
    return 0
  fi

  homebrew_cask_install_state "$token"
}

remove_unmanaged_wezterm_link() {
  local link_path="$1" link_target
  [[ -L $link_path ]] || return 0
  link_target="$(/usr/bin/readlink "$link_path")"
  [[ $link_target == "$WEZTERM_APP_PATH/"* ]] || return 0
  sudo /bin/rm -f -- "$link_path"
}

migrate_unmanaged_wezterm_install() {
  local backup_path cask_state link_path link_target
  local has_unmanaged_install=0
  local -a legacy_link_paths=(
    "$WEZTERM_BIN_DIR/wezterm"
    "$WEZTERM_BIN_DIR/wezterm-gui"
    "$WEZTERM_BIN_DIR/wezterm-mux-server"
    "$WEZTERM_BIN_DIR/strip-ansi-escapes"
    "$WEZTERM_BASH_COMPLETION_PATH"
    "$WEZTERM_FISH_COMPLETION_PATH"
    "$WEZTERM_ZSH_COMPLETION_PATH"
  )

  if [[ -e $WEZTERM_APP_PATH || -L $WEZTERM_APP_PATH ]]; then
    has_unmanaged_install=1
  else
    for link_path in "${legacy_link_paths[@]}"; do
      [[ -L $link_path ]] || continue
      link_target="$(/usr/bin/readlink "$link_path")"
      if [[ $link_target == "$WEZTERM_APP_PATH/"* ]]; then
        has_unmanaged_install=1
        break
      fi
    done
  fi

  ((has_unmanaged_install == 1)) || return 0
  cask_state="$(homebrew_cask_install_state_before_activation "$WEZTERM_CASK_TOKEN")" ||
    dotfiles_die "Unable to inspect Homebrew cask state for $WEZTERM_CASK_TOKEN."
  [[ $cask_state == absent ]] || return 0

  if [[ -e $WEZTERM_APP_PATH || -L $WEZTERM_APP_PATH ]]; then
    backup_path="$WEZTERM_MIGRATION_BACKUP_DIR/WezTerm.app.$(date +%Y%m%d%H%M%S)"
    [[ ! -e $backup_path && ! -L $backup_path ]] ||
      dotfiles_die "Refusing to overwrite an existing WezTerm migration backup: $backup_path"
    /bin/mkdir -p -- "$WEZTERM_MIGRATION_BACKUP_DIR"
    dotfiles_log "Moving unmanaged WezTerm.app aside before Homebrew cask activation..."
    sudo /bin/mv -- "$WEZTERM_APP_PATH" "$backup_path"
  fi

  for link_path in "${legacy_link_paths[@]}"; do
    remove_unmanaged_wezterm_link "$link_path"
  done
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
    dotfiles_die "Docker Desktop was not installed by Homebrew cask: $DOCKER_APP"

  local installer="$DOCKER_APP/Contents/MacOS/install"
  [[ -x $installer ]] || dotfiles_die "Docker Desktop installer not found: $installer"

  ensure_docker_desktop_md5_compatibility

  if [[ ! -f $DOCKER_SETUP_MARKER ]]; then
    [[ $DOTFILES_ACCEPT_DOCKER_LICENSE == 1 ]] ||
      dotfiles_die "Docker Desktop license acceptance requires DOTFILES_ACCEPT_DOCKER_LICENSE=1."
    dotfiles_log "Accepting the Docker Desktop license for personal use..."
    sudo "$installer" --accept-license --user="${SUDO_USER:-$USER}"
    mkdir -p "$(dirname "$DOCKER_SETUP_MARKER")"
    touch "$DOCKER_SETUP_MARKER"
  fi

  dotfiles_have docker || dotfiles_die "Docker CLI is unavailable after nix-darwin activation."
  dotfiles_have python3 || dotfiles_die "python3 is required for bounded Docker readiness probes."
  if ! docker_engine_is_ready; then
    [[ -x $OPEN_COMMAND ]] || dotfiles_die "macOS open command is unavailable: $OPEN_COMMAND"
    "$OPEN_COMMAND" "$DOCKER_APP"
    dotfiles_wait_for "$DOCKER_WAIT_ATTEMPTS" "Docker Desktop engine" docker_engine_is_ready
  fi
  docker_cli_probe compose version ||
    dotfiles_die "Docker Compose CLI version probe failed."
}

docker_engine_is_ready() {
  docker_cli_probe info
}

docker_cli_probe() {
  local timeout_seconds="$DOCKER_PROBE_TIMEOUT_SECONDS"
  if [[ ! $timeout_seconds =~ ^[1-9][0-9]*$ ]] || ((timeout_seconds > 60)); then
    timeout_seconds=5
  fi
  python3 - "$timeout_seconds" "$(command -v docker)" "$@" <<'PY'
import subprocess
import sys

try:
    result = subprocess.run(
        sys.argv[2:],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        timeout=int(sys.argv[1]),
    )
except subprocess.TimeoutExpired:
    raise SystemExit(124)
raise SystemExit(result.returncode)
PY
}

ollama_api_is_ready() {
  curl --fail --silent --show-error --max-time 2 "$OLLAMA_API_URL" >/dev/null
}

setup_ollama_runtime() {
  dotfiles_have "$OLLAMA_COMMAND" || dotfiles_die "Ollama is unavailable after nix-darwin activation."
  [[ -x $LAUNCHCTL_COMMAND ]] || dotfiles_die "macOS launchctl is unavailable: $LAUNCHCTL_COMMAND"
  dotfiles_have curl || dotfiles_die "curl is required to verify Ollama."

  if ollama_api_is_ready; then
    return 0
  fi

  dotfiles_log "Starting Ollama..."
  "$LAUNCHCTL_COMMAND" kickstart -k "gui/$(id -u)/com-dotfiles-ollama"
  dotfiles_wait_for "$OLLAMA_WAIT_ATTEMPTS" "Ollama API" ollama_api_is_ready
}

apply_chezmoi() {
  dotfiles_have chezmoi || dotfiles_die "chezmoi is unavailable after nix-darwin activation."
  chezmoi init --source "$ROOT/chezmoi"
  chezmoi apply --force
}

migrate_darwin_providers() {
  local -a migration_args=(--all)
  if ((DOTFILES_WITH_OLLAMA == 1)); then
    migration_args+=(--feature WithOllama)
  fi
  if ((DOTFILES_WITH_DOCKER == 1)); then
    migration_args+=(--feature WithDocker)
  fi
  if ((DOTFILES_WITH_HERMES == 1)); then
    migration_args+=(--feature WithHermes)
  fi
  "$DARWIN_MIGRATION" "${migration_args[@]}"
}

update_darwin_packages() {
  # The pinned/offline installer mode must not advance custom sources either.
  if [[ ${DOTFILES_SKIP_FLAKE_UPDATE:-0} == 1 ]]; then
    dotfiles_log "Skipping custom Darwin package updates (pinned install)."
    return 0
  fi
  dotfiles_log "Updating custom Darwin packages before activation..."
  # Bootstrap dependencies before Home Manager has installed Python and go-task.
  # Reuse the checkout's locked nixpkgs and the public update task.
  nix --extra-experimental-features 'nix-command flakes' shell \
    --inputs-from "$ROOT" nixpkgs#python3 nixpkgs#go-task \
    --command task --dir "$ROOT" darwin:update
}

main() {
  dotfiles_sanitize_incomplete_git_config_environment
  resolve_install_profile "$@"
  preflight
  ensure_command_line_tools
  ensure_nix
  dotfiles_link_checkout "$ROOT"
  dotfiles_update_flake "$ROOT"
  update_darwin_packages
  preserve_shell_rc_for_nix_darwin
  if ((DOTFILES_WITH_DOCKER == 1)); then
    stop_existing_docker_desktop
    prepare_docker_desktop_cask_links
  fi
  repair_homebrew_cask_link_directories
  migrate_unmanaged_wezterm_install
  apply_darwin_system
  ensure_homebrew_cask_link_directories
  if ((DOTFILES_WITH_DOCKER == 1)); then
    repair_and_verify_docker_desktop_cask
    commit_docker_desktop_cask_links
  fi
  migrate_darwin_providers
  dotfiles_install_herdr
  apply_chezmoi
  if ((DOTFILES_WITH_HERMES == 1)); then
    dotfiles_run_task hermes:desktop:install
  fi
  if ((DOTFILES_WITH_OLLAMA == 1)); then
    setup_ollama_runtime
  fi
  if ((DOTFILES_WITH_DOCKER == 1)); then
    setup_docker_runtime
    if ((DOTFILES_WITH_HERMES == 1)); then
      dotfiles_run_task hermes:bootstrap
      DOTFILES_COMPOSE_FILE="$COMPOSE_FILE" "$VERIFY_ENVIRONMENT" --runtime
    else
      dotfiles_run_task hindsight:up
      DOTFILES_COMPOSE_FILE="$HINDSIGHT_COMPOSE_FILE" "$VERIFY_ENVIRONMENT" --runtime
    fi
  else
    "$VERIFY_ENVIRONMENT"
  fi
  dotfiles_log "macOS setup complete."
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
