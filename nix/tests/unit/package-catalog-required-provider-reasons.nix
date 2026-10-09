{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  fixturePackage = pkgs.hello;
  sets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
    catalogOverride = {
      fixture-without-windows-provider = {
        pkg = fixturePackage;
        category = "test";
      };
      netcat = {
        pkg = fixturePackage;
        category = "test";
      };
    };
  };
  windowsErrorsFor =
    name: builtins.filter (pkgs.lib.hasPrefix "${name}: windows:") sets.providerErrors;
in
{
  testPackageCatalogRequiresProviderOrReviewedUnsupportedReason = {
    expr = {
      missingProvider = windowsErrorsFor "fixture-without-windows-provider";
      reviewedUnsupported = {
        reason = sets.supportReport.netcat.windows.unsupported;
        windowsErrors = windowsErrorsFor "netcat";
      };
    };
    expected = {
      missingProvider = [
        "fixture-without-windows-provider: windows: missing provider or reviewed unsupported reason"
      ];
      reviewedUnsupported = {
        reason = "No reviewed Windows package provider is selected";
        windowsErrors = [ ];
      };
    };
  };
}
