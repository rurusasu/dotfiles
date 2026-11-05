#!/usr/bin/env bash
# Render the same login-user override for builds and normal installation.
write_darwin_flake() {
  local destination=$1 primary_user=$2 ci=${3:-false}
  case $ci in
  true | false) ;;
  *)
    printf 'Darwin fixture selection must be true or false.\n' >&2
    return 64
    ;;
  esac
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
  cat >"$destination/flake.nix" <<'FLAKE'
{
  # The caller locks/overrides this input with the exact source snapshot.
  inputs.dotfiles.url = "path:.";
  outputs = { dotfiles, ... }: {
    darwinConfigurations.macos = dotfiles.darwinConfigurations.macos.extendModules {
      modules = [ ({ lib, ... }: {
        system.primaryUser = lib.mkForce (builtins.readFile ./primary-user);
      }) ] ++ (if builtins.pathExists ./ci-settings.nix then [ ./ci-settings.nix ] else [ ]);
    };
  };
}
FLAKE
}
