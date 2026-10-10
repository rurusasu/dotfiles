{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  identity = import ../../shared/nixos/identity.nix { inherit lib; };
  inherit (identity) user home group;
in
{
  imports = [
    ./integration.nix
    ./configuration.nix
    inputs.nixos-vscode-server.nixosModules.default
  ];

  users.groups.${group} = lib.optionalAttrs (identity.gid != "") { gid = lib.toInt identity.gid; };
  users.users.${user} = {
    isNormalUser = true;
    inherit home group;
    createHome = true;
    linger = true;
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "docker"
    ];
  }
  // lib.optionalAttrs (identity.uid != "") { uid = lib.toInt identity.uid; };

  services.vscode-server = {
    enable = true;
    installPath = [
      "$HOME/.vscode-server"
      "$HOME/.vscode-server-insiders"
    ];
  };
}
