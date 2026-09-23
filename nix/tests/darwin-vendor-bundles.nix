{ inputs }:
let
  pkgs = import inputs.nixpkgs {
    system = "aarch64-darwin";
    config.allowUnfree = true;
  };
  packages = {
    hammerspoon = pkgs.callPackage ../packages/hammerspoon { };
    dia-browser = pkgs.callPackage ../packages/dia-browser { };
    orca-editor = pkgs.callPackage ../packages/orca-editor { };
  };
in
{
  testCustomDarwinPackagesPreserveVendorBundleDerivationAttributes = {
    expr = builtins.mapAttrs (
      _: package: {
        dontFixup = package.dontFixup or false;
        sourceUrl = package.src.url;
        platforms = package.meta.platforms;
      }
    ) packages;
    expected = {
      hammerspoon = {
        dontFixup = true;
        sourceUrl = "https://github.com/Hammerspoon/hammerspoon/releases/download/1.1.1/Hammerspoon-1.1.1.zip";
        platforms = [ "aarch64-darwin" ];
      };
      dia-browser = {
        dontFixup = true;
        sourceUrl = "https://releases.diabrowser.com/release/Dia-1.48.0-86796.zip";
        platforms = [ "aarch64-darwin" ];
      };
      orca-editor = {
        dontFixup = true;
        sourceUrl = "https://github.com/stablyai/orca/releases/download/v1.4.200/orca-macos-arm64.dmg";
        platforms = [ "aarch64-darwin" ];
      };
    };
  };
}
