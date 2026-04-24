# Home Manager module — installs all CLI tools from the SSOT.
{ pkgs, lib, ... }:
let
  sets = import ../packages/sets.nix { inherit pkgs lib; };
in
{
  home.packages = sets.all;
}
