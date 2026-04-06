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
      packageSets = import ../packages { inherit pkgs; };
    in
    {
      packages = {
        # Main package sets (nix profile install .#default)
        default = packageSets.default;
        minimal = packageSets.minimal;
        full = packageSets.full;

        # Individual sets for selective install
        core = packageSets.core;
        dev = packageSets.dev;
        llm = packageSets.llm;
        terminal = packageSets.terminal;
        editors = packageSets.editors;

        # Windows package export (nix build .#winget-export)
        winget-export = import ../packages/winget.nix { inherit pkgs lib; };
      };
    };
}
