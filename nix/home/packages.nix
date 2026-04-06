# Home Manager module — installs all CLI tools from the SSOT.
{ pkgs, ... }:
let
  allPkgs = import ../packages/all.nix { inherit pkgs; };
in
{
  home.packages = allPkgs.packages;
}
