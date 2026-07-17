# Package outputs for nix profile
# Usage:
#   nix profile install .#default   (core + dev + terminal)
#   nix profile install .#minimal   (core only)
#   nix profile install .#full      (everything, unfree allowed)
#   nix profile install .#core      (individual set)
#   nix build .#winget-export       (generate Windows package JSON)
{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      inputs',
      ...
    }:
    let
      workmuxOverlay = _: _: {
        workmux = inputs'.workmux.packages.default.overrideAttrs (_: {
          doCheck = false;
        });
      };
      unfreePkgs =
        (import pkgs.path {
          system = pkgs.stdenv.hostPlatform.system;
          config.allowUnfree = true;
        }).extend
          workmuxOverlay;
      sets = import ../packages/sets.nix {
        pkgs = pkgs.extend workmuxOverlay;
        inherit lib;
        gwqSrc = inputs.gwq-src;
      };
      unfreeSets = import ../packages/sets.nix {
        pkgs = unfreePkgs;
        inherit lib;
        gwqSrc = inputs.gwq-src;
      };
      packageSupportReport = import ../packages/support-report.nix {
        pkgs = unfreePkgs;
        inherit lib;
        gwqSrc = inputs.gwq-src;
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
        fonts = pkgs.buildEnv {
          name = "dotfiles-fonts";
          paths = sets.fonts;
        };

        # Windows package export
        winget-export = import ../packages/winget.nix {
          inherit pkgs lib;
          gwqSrc = inputs.gwq-src;
        };
        package-support-report = packageSupportReport;
      };

      checks = {
        package-provider-coverage = packageSupportReport;
      }
      // lib.optionalAttrs pkgs.stdenv.isLinux {
        bootstrap-nixos-vm = import ../tests/bootstrap-nixos.nix {
          inherit inputs pkgs;
        };
      };
    };
}
