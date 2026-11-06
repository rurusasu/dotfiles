#!/usr/bin/env bash
# Render the same login-user override for builds and normal installation.
write_darwin_flake() {
  local destination=$1 primary_user=$2 source_path=$3 ci=${4:-false} source_url character encoded index
  local LC_ALL=C
  case $ci in
  true | false) ;;
  *)
    printf 'Darwin fixture selection must be true or false.\n' >&2
    return 64
    ;;
  esac
  [[ $source_path == /* ]] || {
    printf 'Darwin source path must be absolute.\n' >&2
    return 64
  }
  # URL-encode filesystem characters as bytes. The result is also safe inside
  # a Nix string, including paths with spaces, quotes or interpolation syntax.
  source_url=path:
  for ((index = 0; index < ${#source_path}; index++)); do
    character=${source_path:index:1}
    case $character in
    [a-zA-Z0-9/._~-]) source_url+=$character ;;
    *)
      printf -v encoded '%%%02X' "'$character"
      source_url+=$encoded
      ;;
    esac
  done
  mkdir -p "$destination"
  printf '%s' "$primary_user" >"$destination/primary-user"
  if [[ $ci == true ]]; then
    cat >"$destination/ci-settings.nix" <<'SETTINGS'
{ config, lib, ... }:
{
  home-manager.users.${config.system.primaryUser} = {
    programs.mcp.servers = lib.mkForce { };
    services.hermes-agent.settings.secrets.onepassword.enabled = lib.mkForce false;
  };
}
SETTINGS
  else
    rm -f "$destination/ci-settings.nix"
  fi
  {
    # Persist the source in the declaration, so archive/eval never re-lock the
    # input back to the wrapper's own directory after a temporary override.
    printf '{\n  inputs.dotfiles.url = "%s";\n' "$source_url"
    cat <<'FLAKE'
  outputs = { dotfiles, ... }: {
    darwinConfigurations.macos = dotfiles.darwinConfigurations.macos.extendModules {
      modules = [ ({ lib, ... }: {
        system.primaryUser = lib.mkForce (builtins.readFile ./primary-user);
      }) ] ++ (if builtins.pathExists ./ci-settings.nix then [ ./ci-settings.nix ] else [ ]);
    };
  };
}
FLAKE
  } >"$destination/flake.nix"
}
