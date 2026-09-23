{ inputs }:
let
  pkgs = import inputs.nixpkgs {
    system = "aarch64-darwin";
    config.allowUnfree = true;
  };
  fixturePackage = pkgs.hello;
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
    catalogOverride = {
      fixture-without-windows-provider = {
        pkg = fixturePackage;
        category = "test";
      };
      bat = {
        pkg = fixturePackage;
        category = "test";
      };
    };
  };
  windowsErrorsFor = name: builtins.filter
    (pkgs.lib.hasPrefix "${name}: windows:")
    sets.providerErrors;
in
{
  testPackageCatalogRequiresProviderOrReviewedUnsupportedReason = {
    expr = {
      missingProvider = windowsErrorsFor "fixture-without-windows-provider";
      reviewedUnsupported = {
        reason = sets.supportReport.bat.windows.unsupported;
        windowsErrors = windowsErrorsFor "bat";
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
