#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: nixos-wsl-postinstall.sh [options]

Options:
  --user <name>        Target user name (auto-detected if omitted)
  --repo-dir <path>    Config repo directory (default: /home/<user>/.dotfiles)
  --flake-name <name>  Flake name (default: myNixOS)
  --hostname <name>    Set networking.hostName
  --sync-mode <mode>   Sync mode: link|repo|nix|none (default: link)
  --sync-source <path> Source dir for sync (default: script repo root)
  --sync-back <mode>   Sync back: lock|none (default: lock when sync-mode=link)
  --force              Allow non-empty repo dir (no deletion)
  -h, --help           Show help
USAGE
}

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

USER_NAME=""
REPO_DIR=""
FLAKE_NAME="nixos"
HOSTNAME=""
FORCE=0
SYNC_MODE="link"
SYNC_SOURCE=""
SYNC_BACK=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      USER_NAME="${2:-}"
      shift 2
      ;;
    --repo-dir)
      REPO_DIR="${2:-}"
      shift 2
      ;;
    --flake-name)
      FLAKE_NAME="${2:-}"
      shift 2
      ;;
    --hostname)
      HOSTNAME="${2:-}"
      shift 2
      ;;
    --sync-mode)
      SYNC_MODE="${2:-}"
      shift 2
      ;;
    --sync-source)
      SYNC_SOURCE="${2:-}"
      shift 2
      ;;
    --sync-back)
      SYNC_BACK="${2:-}"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$USER_NAME" ]]; then
  USER_NAME="$(getent passwd 1000 | cut -d: -f1 || true)"
  if [[ -z "$USER_NAME" ]]; then
    USER_NAME="$(getent passwd | awk -F: '$3>=1000 && $1!="nobody"{print $1; exit}')"
  fi
  if [[ -z "$USER_NAME" ]]; then
    echo "Could not detect a non-root user. Use --user." >&2
    exit 1
  fi
fi

if [[ -z "$REPO_DIR" ]]; then
  REPO_DIR="/home/$USER_NAME/.dotfiles"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -z "$SYNC_SOURCE" ]]; then
  SYNC_SOURCE="$SOURCE_ROOT"
fi
if [[ -z "$SYNC_BACK" ]]; then
  if [[ "$SYNC_MODE" == "link" ]]; then
    SYNC_BACK="lock"
  elif [[ "$SYNC_MODE" == "repo" ]]; then
    SYNC_BACK="repo"
  else
    SYNC_BACK="none"
  fi
fi

# Handle sync mode
if [[ "$SYNC_MODE" == "link" ]]; then
  # Create symlink to Windows-side dotfiles
  if [[ ! -d "$SYNC_SOURCE" ]]; then
    echo "Sync source not found: $SYNC_SOURCE" >&2
    exit 1
  fi

  # Remove existing REPO_DIR if it's a directory or file (not symlink)
  if [[ -e "$REPO_DIR" && ! -L "$REPO_DIR" ]]; then
    if [[ "$FORCE" -eq 0 ]]; then
      echo "Repo dir exists and is not a symlink: $REPO_DIR" >&2
      echo "Pass --force to remove it and create symlink." >&2
      exit 1
    fi
    rm -rf "$REPO_DIR"
  fi

  # Remove existing symlink if pointing elsewhere
  if [[ -L "$REPO_DIR" ]]; then
    CURRENT_TARGET="$(readlink -f "$REPO_DIR" 2>/dev/null || true)"
    if [[ "$CURRENT_TARGET" != "$SYNC_SOURCE" ]]; then
      rm -f "$REPO_DIR"
    fi
  fi

  # Create symlink
  if [[ ! -e "$REPO_DIR" ]]; then
    ln -s "$SYNC_SOURCE" "$REPO_DIR"
    echo "Created symlink: $REPO_DIR -> $SYNC_SOURCE"
  else
    echo "Symlink already exists: $REPO_DIR -> $SYNC_SOURCE"
  fi

  # Set ownership of the symlink itself
  if id "$USER_NAME" >/dev/null 2>&1; then
    chown -h "$USER_NAME" "$REPO_DIR" 2>/dev/null || true
  fi

elif [[ "$SYNC_MODE" == "repo" ]]; then
  if [[ -e "$REPO_DIR" && "$FORCE" -eq 0 ]]; then
    if [[ -n "$(ls -A "$REPO_DIR" 2>/dev/null)" ]]; then
      echo "Repo dir is not empty: $REPO_DIR" >&2
      echo "Move it or pass --force to continue." >&2
      exit 1
    fi
  fi

  mkdir -p "$REPO_DIR"

  if [[ ! -d "$SYNC_SOURCE" ]]; then
    echo "Sync source not found: $SYNC_SOURCE" >&2
    exit 1
  fi
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude ".git" --exclude ".direnv" --exclude "result" "$SYNC_SOURCE/" "$REPO_DIR/"
  else
    (cd "$SYNC_SOURCE" && tar --exclude ".git" --exclude ".direnv" --exclude "result" -cf - .) | (cd "$REPO_DIR" && tar -xf -)
  fi

  if id "$USER_NAME" >/dev/null 2>&1; then
    USER_GROUP="$(id -gn "$USER_NAME" 2>/dev/null || true)"
    if [[ -n "$USER_GROUP" ]]; then
      chown -R "$USER_NAME:$USER_GROUP" "$REPO_DIR"
    else
      chown -R "$USER_NAME" "$REPO_DIR"
    fi
  fi

elif [[ "$SYNC_MODE" == "nix" ]]; then
  mkdir -p "$REPO_DIR"
  if [[ -d "$SOURCE_ROOT/nix" ]]; then
    mkdir -p "$REPO_DIR/nix"
    cp -a "$SOURCE_ROOT/nix/." "$REPO_DIR/nix/"
  fi

elif [[ "$SYNC_MODE" != "none" ]]; then
  echo "Unknown sync mode: $SYNC_MODE" >&2
  exit 1
fi

# For link mode, use SYNC_SOURCE directly for file generation
# For other modes, use REPO_DIR
if [[ "$SYNC_MODE" == "link" ]]; then
  TARGET_DIR="$SYNC_SOURCE"
else
  TARGET_DIR="$REPO_DIR"
fi

case "$(uname -m)" in
  x86_64)
    SYSTEM="x86_64-linux"
    ;;
  aarch64|arm64)
    SYSTEM="aarch64-linux"
    ;;
  *)
    SYSTEM="x86_64-linux"
    ;;
esac

NIX_DIR="$TARGET_DIR/nix"
HM_DIR="$NIX_DIR/home"
HM_USERS_DIR="$HM_DIR/users"
HM_PROFILES_DIR="$NIX_DIR/profiles/home"
HOST_DIR="$NIX_DIR/hosts/wsl"

mkdir -p "$HM_DIR/wsl" "$HM_USERS_DIR" "$HM_PROFILES_DIR" "$HOST_DIR"

USER_HOME_PATH="$HM_USERS_DIR/$USER_NAME.nix"
HOST_HOME_PATH="$HM_DIR/wsl/default.nix"
HOST_DEFAULT_PATH="$HOST_DIR/default.nix"
HOST_CONFIG_PATH="$HOST_DIR/configuration.nix"
HOST_HW_PATH="$HOST_DIR/hardware-configuration.nix"

cat > "$USER_HOME_PATH" <<EOF
{ config, pkgs, ... }:
{
  home.username = "$USER_NAME";
  home.homeDirectory = "/home/$USER_NAME";
}
EOF

cat > "$HOST_HOME_PATH" <<EOF
{ config, pkgs, ... }:
{
  imports = [
    ../users/$USER_NAME.nix
    ../../profiles/home
  ];
}
EOF

cat > "$HOST_DEFAULT_PATH" <<EOF
{ config, inputs, pkgs, ... }:
{
  imports = [
    ../../modules/host
    ../../modules/wsl
    ./configuration.nix
    inputs.nixos-vscode-server.nixosModules.default
  ];

  users.users.$USER_NAME.shell = pkgs.zsh;

  services.vscode-server = {
    enable = true;
    installPath = [
      "\$HOME/.vscode-server"
      "\$HOME/.vscode-server-insiders"
    ];
  };
EOF

if [[ -n "$HOSTNAME" ]]; then
  echo "  networking.hostName = \"$HOSTNAME\";" >> "$HOST_DEFAULT_PATH"
fi
echo '}' >> "$HOST_DEFAULT_PATH"

if [[ -f /etc/nixos/configuration.nix ]]; then
  cp -f /etc/nixos/configuration.nix "$HOST_CONFIG_PATH"
  sed -i '\|<nixos-wsl/modules>|d' "$HOST_CONFIG_PATH"
fi
if [[ -f /etc/nixos/hardware-configuration.nix ]]; then
  cp -f /etc/nixos/hardware-configuration.nix "$HOST_HW_PATH"
fi

# Run nixos-rebuild
NIX_CONFIG="experimental-features = nix-command flakes" \
  nixos-rebuild switch --flake "path:$TARGET_DIR#$FLAKE_NAME"

# Handle sync-back
if [[ "$SYNC_BACK" == "repo" && "$SYNC_MODE" != "link" ]]; then
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude ".git" --exclude ".direnv" --exclude "result" "$REPO_DIR/" "$SYNC_SOURCE/"
  else
    (cd "$REPO_DIR" && tar --exclude ".git" --exclude ".direnv" --exclude "result" -cf - .) | (cd "$SYNC_SOURCE" && tar -xf -)
  fi
elif [[ "$SYNC_BACK" == "lock" ]]; then
  # For link mode, flake.lock is already in SYNC_SOURCE
  if [[ "$SYNC_MODE" != "link" && -f "$REPO_DIR/flake.lock" ]]; then
    cp -f "$REPO_DIR/flake.lock" "$SYNC_SOURCE/flake.lock"
  fi
elif [[ "$SYNC_BACK" != "none" ]]; then
  echo "Unknown sync-back mode: $SYNC_BACK" >&2
  exit 1
fi

# Git setup (only for non-link mode, link mode uses Windows git)
if [[ "$SYNC_MODE" != "link" ]]; then
  if command -v git >/dev/null 2>&1; then
    git -C "$REPO_DIR" init
    git config --global --add safe.directory "$REPO_DIR"
    git -C "$REPO_DIR" add -A
  else
    echo "git is not available yet. You can init later."
  fi
fi

echo "Post-install setup completed."
