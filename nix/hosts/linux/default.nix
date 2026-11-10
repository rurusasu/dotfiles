{
  config,
  inputs,
  lib,
  pkgs,
  platform,
  ...
}:
let
  user = if platform == "wsl" then config.wsl.defaultUser else "nixos";
in
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    ../../modules/1password/nixos.nix
    ../../modules/podman/nixos.nix
    ../../modules/steam/nixos.nix
    ../../modules/hyprland/nixos.nix
    ../../modules/fonts/nixos.nix
    ../../modules/nvidia/nixos.nix
  ];
  fonts.fontDir.enable = true;
  system.stateVersion = inputs.self.lib.stateVersions.nixos;
  users.users.${user} = {
    isNormalUser = true;
    shell = pkgs.zsh;
    linger = true;
    extraGroups = [
      "wheel"
    ];
  };
  home-manager.users.${user} = { };
}
