# Package outputs for nix profile
# Usage:
#   nix profile install github:yourusername/dotfiles#default
#   nix profile install .#minimal
#   nix profile install .#full
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      unfreePkgs = import pkgs.path {
        inherit (pkgs) system;
        config.allowUnfree = true;
      };
      packageSets = import ../packages { inherit pkgs; };
      unfreePackageSets = import ../packages { pkgs = unfreePkgs; };
    in
    {
      packages = {
        # Main package sets (nix profile install .#default)
        default = packageSets.default;
        minimal = packageSets.minimal;
        full = unfreePackageSets.full;

        # Individual sets for selective install
        core = packageSets.core;
        dev = packageSets.dev;
        llm = unfreePackageSets.llm;
        terminal = packageSets.terminal;
        editors = unfreePackageSets.editors;

        # Windows package export (nix build .#winget-export)
        winget-export = import ../packages/winget.nix { inherit pkgs lib; };
      };
    };
}
