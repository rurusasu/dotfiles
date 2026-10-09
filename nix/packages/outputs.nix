# Export and validation artifacts only. Applications are installed through
# the OS configurations and their Home Manager modules, not Nix profiles.
# Usage: nix build .#winget-export (generate Windows package JSON)
{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      ...
    }:
    let
      unfreePkgs = import pkgs.path {
        system = pkgs.stdenv.hostPlatform.system;
        config.allowUnfree = true;
      };
      unfreeSets = import ./sets.nix {
        pkgs = unfreePkgs;
        inherit lib;
      };
      packageSupportReport = import ./support-report.nix {
        pkgs = unfreePkgs;
        inherit lib;
      };
    in
    {
      packages = {
        # Windows package export
        winget-export = import ./winget.nix {
          inherit pkgs lib;
        };
        windows-keybindings-export = import ../hosts/windows/export.nix { inherit pkgs lib; };
        package-support-report = packageSupportReport;
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin (
        lib.mapAttrs' (name: package: lib.nameValuePair "darwin-${name}" package) unfreeSets.darwinPackages
      );

      # The support report is also a validation derivation; reuse the same output.
      checks.package-provider-coverage = packageSupportReport;
    };
}
