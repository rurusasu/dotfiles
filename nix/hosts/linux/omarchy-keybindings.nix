# System session enablement, not user key allocation.
{ lib, pkgs, ... }:
let
  sets = import ../../packages/sets.nix { inherit pkgs lib; };
in
{
  programs.hyprland = {
    enable = true;
    package = builtins.head (sets.resolveForInstallFeatures [ "WithDesktop" ] [ "hyprland" ]);
  };
  home-manager.sharedModules = [ ../../home/keybindings/hyprland.nix ];
}
