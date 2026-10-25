# System session enablement, not user key allocation.
{ pkgs, ... }:
{
  imports = [ ./nixos.nix ];

  programs.hyprland = {
    enable = true;
    package = pkgs.hyprland;
  };
  home-manager.sharedModules = [ ../home/keybindings/hyprland.nix ];
}
