{ pkgs, ... }:
let
  inherit ((import ../fonts.nix { inherit pkgs; })) fonts;
in
{
  # nix-darwin installs fonts; Home Manager configures fontconfig clients.
  fonts.packages = fonts.packages;
  home-manager.sharedModules = [
    { fonts.fontconfig = fonts.fontconfig; }
  ];
}
