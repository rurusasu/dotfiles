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
FLAKE_NAME="myNixOS"
HOSTNAME=""
FORCE=0

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

if [[ -e "$REPO_DIR" && "$FORCE" -eq 0 ]]; then
  if [[ -n "$(ls -A "$REPO_DIR" 2>/dev/null)" ]]; then
    echo "Repo dir is not empty: $REPO_DIR" >&2
    echo "Move it or pass --force to continue." >&2
    exit 1
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

mkdir -p "$REPO_DIR"

if [[ -d "$SOURCE_ROOT/nix" ]]; then
  mkdir -p "$REPO_DIR/nix"
  cp -a "$SOURCE_ROOT/nix/." "$REPO_DIR/nix/"
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

NIX_DIR="$REPO_DIR/nix"
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
    ../../profiles/home/common.nix
  ];
}
EOF

cat > "$HOST_DEFAULT_PATH" <<EOF
{ config, pkgs, ... }:
{
  imports = [
    ../../modules/host
    ../../modules/wsl
    ./configuration.nix
  ];

  users.users.$USER_NAME.shell = pkgs.zsh;
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

if id "$USER_NAME" >/dev/null 2>&1; then
  USER_GROUP="$(id -gn "$USER_NAME" 2>/dev/null || true)"
  if [[ -n "$USER_GROUP" ]]; then
    chown -R "$USER_NAME:$USER_GROUP" "$REPO_DIR"
  else
    chown -R "$USER_NAME" "$REPO_DIR"
  fi
fi

if command -v git >/dev/null 2>&1; then
  git -C "$REPO_DIR" init
  git config --global --add safe.directory "$REPO_DIR"
else
  echo "git is not available yet. You can init later."
fi

NIX_CONFIG="experimental-features = nix-command flakes" \
  nixos-rebuild switch --flake "$REPO_DIR#$FLAKE_NAME"

echo "Post-install setup completed."
