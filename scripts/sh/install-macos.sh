#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
COMPOSE_FILE="$ROOT/docker/hermes-agent/compose.yml"
BREW_BIN="${DOTFILES_BREW_BIN:-/opt/homebrew/bin/brew}"
DOCKER_APP="${DOTFILES_DOCKER_APP_PATH:-/Applications/Docker.app}"
DOCKER_SETUP_MARKER="${DOTFILES_DOCKER_SETUP_MARKER:-$HOME/.config/dotfiles/docker-desktop-installed}"
DOCKER_FALLBACK_URL="${DOTFILES_DOCKER_FALLBACK_URL:-https://desktop.docker.com/mac/main/arm64/233772/Docker.dmg}"
DOCKER_FALLBACK_SHA256="${DOTFILES_DOCKER_FALLBACK_SHA256:-a35a0b14fbf182fb2ef9f8e650ace9a8ebcc81ad4872d51bccc4496f5cdb0158}"
NIX_PROFILE_SCRIPT="${DOTFILES_NIX_PROFILE_SCRIPT:-/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh}"
DOCKER_WAIT_ATTEMPTS="${DOTFILES_DOCKER_WAIT_ATTEMPTS:-120}"
SERVICE_WAIT_ATTEMPTS="${DOTFILES_SERVICE_WAIT_ATTEMPTS:-60}"
NIX_BUILD_ATTEMPTS="${DOTFILES_NIX_BUILD_ATTEMPTS:-3}"
WAIT_SLEEP_SECONDS="${DOTFILES_WAIT_SLEEP_SECONDS:-2}"

log() {
  printf '\033[1;34m[macos-install]\033[0m %s\n' "$*"
}

die() {
  printf '\033[1;31m[macos-install]\033[0m %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

wait_for() {
  local attempts="$1"
  local label="$2"
  shift 2
  local attempt
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    if ((attempt < attempts)); then
      sleep "$WAIT_SLEEP_SECONDS"
    fi
  done
  die "Timed out waiting for $label after $attempts attempts."
}

preflight() {
  local os arch version major required
  os="$(uname -s)"
  arch="$(uname -m)"
  [[ $os == "Darwin" ]] || die "macOS is required (detected $os)."
  [[ $arch == "arm64" ]] || die "Apple Silicon is required (detected $arch)."

  version="$(sw_vers -productVersion)"
  major="${version%%.*}"
  [[ $major =~ ^[0-9]+$ ]] || die "Unable to parse macOS version: $version"
  ((major >= 26)) || die "macOS 26 or later is required (detected $version)."

  if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install || true
    die "Command Line Tools installation was requested. Complete it, then rerun ./install.sh."
  fi

  for required in \
    "$ROOT/flake.nix" \
    "$ROOT/chezmoi" \
    "$COMPOSE_FILE"; do
    [[ -e $required ]] || die "Required repository path is missing: $required"
  done
}

ensure_homebrew() {
  if ! have brew; then
    log "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  if have brew; then
    eval "$(brew shellenv)"
  elif [[ -x $BREW_BIN ]]; then
    eval "$("$BREW_BIN" shellenv)"
  else
    die "Homebrew installation completed but brew is unavailable."
  fi
}

ensure_rosetta() {
  if ! pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
    log "Installing Rosetta 2 for linux/amd64 containers..."
    softwareupdate --install-rosetta --agree-to-license
  fi
}

install_docker_desktop_fallback() {
  log "Homebrew could not unpack Docker Desktop; using the verified official DMG fallback..."
  if ! have 7zz; then
    brew install sevenzip
  fi
  have 7zz || die "7-Zip is required for the Docker Desktop fallback."

  local temp_dir dmg_path extract_dir actual_sha source_app
  temp_dir="$(mktemp -d "${TMPDIR:-/private/tmp}/dotfiles-docker.XXXXXX")"
  dmg_path="$temp_dir/Docker.dmg"
  extract_dir="$temp_dir/extracted"

  curl -fL "$DOCKER_FALLBACK_URL" -o "$dmg_path" || {
    rm -rf "$temp_dir"
    die "Docker Desktop fallback download failed."
  }
  actual_sha="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
  if [[ $actual_sha != "$DOCKER_FALLBACK_SHA256" ]]; then
    rm -rf "$temp_dir"
    die "Docker Desktop fallback checksum mismatch."
  fi

  mkdir -p "$extract_dir"
  7zz x -snld20 "-o$extract_dir" "$dmg_path" >/dev/null || {
    rm -rf "$temp_dir"
    die "Docker Desktop fallback DMG extraction failed."
  }
  source_app="$extract_dir/Docker/Docker.app"
  if [[ ! -d $source_app ]]; then
    rm -rf "$temp_dir"
    die "Docker.app was not found in the verified fallback DMG."
  fi

  ditto "$source_app" "$DOCKER_APP" || {
    rm -rf "$temp_dir"
    die "Copying Docker.app to Applications failed."
  }
  codesign --verify --deep --strict "$DOCKER_APP" || {
    rm -rf "$temp_dir"
    die "Docker.app signature verification failed."
  }
  rm -rf "$temp_dir"
}

ensure_docker_desktop() {
  if [[ ! -d $DOCKER_APP ]]; then
    log "Installing Docker Desktop..."
    if ! brew install --cask docker-desktop; then
      install_docker_desktop_fallback
    fi
  fi

  local installer="$DOCKER_APP/Contents/MacOS/install"
  [[ -x $installer ]] || die "Docker Desktop installer not found: $installer"

  if [[ ! -f $DOCKER_SETUP_MARKER ]]; then
    log "Accepting the Docker Desktop license and applying user configuration..."
    sudo "$installer" --accept-license --user="$USER"
    mkdir -p "$(dirname "$DOCKER_SETUP_MARKER")"
    touch "$DOCKER_SETUP_MARKER"
  fi

  ensure_rosetta
  export PATH="$DOCKER_APP/Contents/Resources/bin:$PATH"
  if ! docker info >/dev/null 2>&1; then
    docker desktop start --timeout 120
    wait_for "$DOCKER_WAIT_ATTEMPTS" "Docker Desktop engine" docker info
  fi
  docker compose version >/dev/null
}

load_nix_profile() {
  if [[ -r $NIX_PROFILE_SCRIPT ]]; then
    # shellcheck source=/dev/null
    . "$NIX_PROFILE_SCRIPT"
  fi
}

ensure_nix() {
  load_nix_profile
  if ! have nix; then
    log "Installing Nix in multi-user daemon mode..."
    curl -fsSL https://nixos.org/nix/install | sh -s -- --daemon
    load_nix_profile
  fi

  have nix || die "Nix installation completed but nix is unavailable."
  mkdir -p "$HOME/.config/nix"
  local feature_line="extra-experimental-features = nix-command flakes"
  touch "$HOME/.config/nix/nix.conf"
  grep -Fxq "$feature_line" "$HOME/.config/nix/nix.conf" ||
    printf '%s\n' "$feature_line" >>"$HOME/.config/nix/nix.conf"
}

canonical_directory() {
  (
    cd "$1"
    pwd -P
  )
}

link_dotfiles() {
  local target="$HOME/.dotfiles"
  if [[ -L $target ]] &&
    [[ "$(canonical_directory "$target")" == "$(canonical_directory "$ROOT")" ]]; then
    return
  fi

  if [[ -e $target || -L $target ]]; then
    local backup="$HOME/.dotfiles.backup.$(date +%Y%m%d%H%M%S)"
    mv "$target" "$backup"
    log "Moved existing $target to $backup"
  fi

  ln -s "$ROOT" "$target"
}

activate_home_manager() {
  log "Building Home Manager configuration..."
  local activation attempt built
  activation=""
  built=0
  for ((attempt = 1; attempt <= NIX_BUILD_ATTEMPTS; attempt++)); do
    if activation="$(
      cd "$ROOT"
      nix build --no-link --print-out-paths \
        .#homeConfigurations.aarch64-darwin.activationPackage --impure
    )"; then
      built=1
      break
    fi
    if ((attempt < NIX_BUILD_ATTEMPTS)); then
      log "Home Manager build failed; retrying ($attempt/$NIX_BUILD_ATTEMPTS)..."
      sleep "$WAIT_SLEEP_SECONDS"
    fi
  done
  ((built == 1)) || die "Home Manager build failed after $NIX_BUILD_ATTEMPTS attempts."
  [[ -x "$activation/activate" ]] ||
    die "Home Manager activation script not found: $activation/activate"
  "$activation/activate"
  export PATH="$HOME/.nix-profile/bin:$HOME/.local/state/nix/profile/bin:$PATH"
}

apply_chezmoi() {
  have chezmoi || die "chezmoi is unavailable after Home Manager activation."
  chezmoi init --source "$ROOT/chezmoi"
  chezmoi apply --force
}

show_compose_diagnostics() {
  docker compose -f "$COMPOSE_FILE" ps || true
  docker compose -f "$COMPOSE_FILE" logs --tail=100 || true
}

start_hermes_stack() {
  log "Validating Hermes Docker Compose configuration..."
  docker compose -f "$COMPOSE_FILE" config
  log "Building Hermes images..."
  docker compose -f "$COMPOSE_FILE" build --pull
  log "Starting Hermes services..."
  if ! docker compose -f "$COMPOSE_FILE" up -d --force-recreate --wait; then
    show_compose_diagnostics
    die "Hermes Docker Compose startup failed."
  fi
  docker compose -f "$COMPOSE_FILE" ps
  wait_for "$SERVICE_WAIT_ATTEMPTS" "Hermes API port" \
    nc -z 127.0.0.1 "${HERMES_API_PORT:-8642}"
  wait_for "$SERVICE_WAIT_ATTEMPTS" "Hermes dashboard port" \
    nc -z 127.0.0.1 "${HERMES_DASHBOARD_PORT:-9119}"
  wait_for "$SERVICE_WAIT_ATTEMPTS" "Hermes browser viewer port" \
    nc -z 127.0.0.1 "${HERMES_BROWSER_VIEW_PORT:-6080}"
}

main() {
  preflight
  log "Docker Desktop is subject to Docker's license terms; continuing for personal use."
  ensure_homebrew
  ensure_docker_desktop
  ensure_nix
  link_dotfiles
  activate_home_manager
  apply_chezmoi
  start_hermes_stack
  log "macOS setup complete."
}

main "$@"
