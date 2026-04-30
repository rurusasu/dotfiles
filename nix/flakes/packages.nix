# Package outputs for nix profile
# Usage:
#   nix profile install .#default   (core + dev + terminal)
#   nix profile install .#minimal   (core only)
#   nix profile install .#full      (everything, unfree allowed)
#   nix profile install .#core      (individual set)
#   nix build .#winget-export       (generate Windows package JSON)
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      unfreePkgs = import pkgs.path {
        inherit (pkgs) system;
        config.allowUnfree = true;
      };
      sets = import ../packages/sets.nix { inherit pkgs lib; };
      unfreeSets = import ../packages/sets.nix {
        pkgs = unfreePkgs;
        inherit lib;
      };
    in
    {
      packages = {
        # Main package sets
        default = pkgs.buildEnv {
          name = "dotfiles-default";
          paths = sets.core ++ sets.dev ++ unfreeSets.terminal;
        };
        minimal = pkgs.buildEnv {
          name = "dotfiles-minimal";
          paths = sets.core;
        };
        full = pkgs.buildEnv {
          name = "dotfiles-full";
          paths = unfreeSets.all;
        };

        # Individual sets for selective install
        core = pkgs.buildEnv {
          name = "dotfiles-core";
          paths = sets.core;
        };
        dev = pkgs.buildEnv {
          name = "dotfiles-dev";
          paths = sets.dev;
        };
        llm = pkgs.buildEnv {
          name = "dotfiles-llm";
          paths = unfreeSets.llm;
        };
        terminal = pkgs.buildEnv {
          name = "dotfiles-terminal";
          paths = unfreeSets.terminal;
        };
        editors = pkgs.buildEnv {
          name = "dotfiles-editors";
          paths = unfreeSets.editors;
        };

        # Windows package export
        winget-export = import ../packages/winget.nix { inherit pkgs lib; };
      };
    };
}
