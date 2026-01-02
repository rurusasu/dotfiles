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
  --sync-mode <mode>   Sync mode: repo|nix|none (default: repo)
  --sync-source <path> Source dir for sync (default: script repo root)
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
SYNC_MODE="repo"
SYNC_SOURCE=""

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
if [[ -z "$SYNC_SOURCE" ]]; then
  SYNC_SOURCE="$SOURCE_ROOT"
fi

mkdir -p "$REPO_DIR"

if [[ "$SYNC_MODE" == "repo" ]]; then
  if [[ ! -d "$SYNC_SOURCE" ]]; then
    echo "Sync source not found: $SYNC_SOURCE" >&2
    exit 1
  fi
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude ".git" --exclude ".direnv" --exclude "result" "$SYNC_SOURCE/" "$REPO_DIR/"
  else
    (cd "$SYNC_SOURCE" && tar --exclude ".git" --exclude ".direnv" --exclude "result" -cf - .) | (cd "$REPO_DIR" && tar -xf -)
  fi
elif [[ "$SYNC_MODE" == "nix" ]]; then
  if [[ -d "$SOURCE_ROOT/nix" ]]; then
    mkdir -p "$REPO_DIR/nix"
    cp -a "$SOURCE_ROOT/nix/." "$REPO_DIR/nix/"
  fi
elif [[ "$SYNC_MODE" != "none" ]]; then
  echo "Unknown sync mode: $SYNC_MODE" >&2
  exit 1
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

NIX_CONFIG="experimental-features = nix-command flakes" \
  nixos-rebuild switch --flake "path:$REPO_DIR#$FLAKE_NAME"

if command -v git >/dev/null 2>&1; then
  git -C "$REPO_DIR" init
  git config --global --add safe.directory "$REPO_DIR"
else
  echo "git is not available yet. You can init later."
fi

echo "Post-install setup completed."
