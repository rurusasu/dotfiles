# macOS GUI installation through nix-darwin, selected by the Darwin host.
{ pkgs, ... }:
{
  environment.systemPackages = [
    (import ./browsers/dia { inherit pkgs; })
    pkgs.obsidian
    pkgs.raycast
    pkgs._1password-gui
  ];
}
