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
cp -a /etc/nixos/. "$REPO_DIR/"

if [[ -d "$SOURCE_ROOT/nix" ]]; then
  mkdir -p "$REPO_DIR/nix"
  cp -a "$SOURCE_ROOT/nix/." "$REPO_DIR/nix/"
fi

if [[ -f "$REPO_DIR/configuration.nix" ]]; then
  sed -i '\|<nixos-wsl/modules>|d' "$REPO_DIR/configuration.nix"
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
HM_HOSTS_DIR="$HM_DIR/hosts"
HM_PROFILES_DIR="$NIX_DIR/profiles/home"

mkdir -p "$HM_USERS_DIR" "$HM_HOSTS_DIR" "$HM_PROFILES_DIR"

COMMON_HOME_PATH="$HM_PROFILES_DIR/common.nix"
USER_HOME_PATH="$HM_USERS_DIR/$USER_NAME.nix"
HOST_HOME_PATH="$HM_HOSTS_DIR/wsl.nix"
MODULE_PATH="$REPO_DIR/wsl-postinstall.nix"

cat > "$COMMON_HOME_PATH" <<'EOF'
{ config, pkgs, ... }:
{
  home.stateVersion = "24.05";

  programs = {
    git.enable = true;
    bash.enable = true;
    zsh.enable = true;
    neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
    };
    tmux.enable = true;
    vscode.enable = true;
  };

  programs.wezterm.enable = true;

  home.file.".config/wezterm/wezterm.lua".source = ../../home/config/wezterm/wezterm.lua;
}
EOF

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
    ../../profiles/home/common.nix
    ../users/$USER_NAME.nix
  ];
}
EOF

{
  echo '{ config, pkgs, ... }:'
  echo '{'
  echo '  nix = {'
  echo '    settings = {'
  echo '      experimental-features = [ "nix-command" "flakes" ];'
  echo '      auto-optimise-store = true;'
  echo '    };'
  echo '    gc = {'
  echo '      automatic = true;'
  echo '      dates = "weekly";'
  echo '      options = "--delete-older-than 7d";'
  echo '    };'
  echo '  };'
  echo ''
  echo '  nixpkgs.config.allowUnfree = true;'
  echo '  programs.zsh.enable = true;'
  echo '  environment.systemPackages = ['
  echo '    pkgs.coreutils'
  echo '  ];'
  echo ''
  echo "  users.users.\"$USER_NAME\".shell = pkgs.zsh;"
  if [[ -n "$HOSTNAME" ]]; then
    echo "  networking.hostName = \"$HOSTNAME\";"
  fi
  echo '}'
} > "$MODULE_PATH"

cat > "$REPO_DIR/flake.nix" <<EOF
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
  };

  outputs = { self, nixpkgs, home-manager, nixos-wsl }:
  {
    nixosConfigurations.$FLAKE_NAME = nixpkgs.lib.nixosSystem {
      system = "$SYSTEM";
      modules = [
        nixos-wsl.nixosModules.wsl
        ./configuration.nix
        ./wsl-postinstall.nix
        ./nix/hosts/wsl.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.$USER_NAME = import ./nix/home/hosts/wsl.nix;
        }
      ];
    };
  };
}
EOF

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
else
  echo "git is not available yet. You can init later."
fi

NIX_CONFIG="experimental-features = nix-command flakes" \
  nixos-rebuild switch --flake "$REPO_DIR#$FLAKE_NAME"

echo "Post-install setup completed."
