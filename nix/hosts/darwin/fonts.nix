{ pkgs, lib, ... }:
let
  sets = import ../../packages/sets.nix {
    inherit pkgs lib;
  };
in
{
  fonts.packages = sets.fonts;
}
