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
    expr = builtins.mapAttrs (_: package: {
      dontFixup = package.dontFixup or false;
      sourceUrl = package.src.url;
      platforms = package.meta.platforms;
    }) packages;
    expected = {
      hammerspoon = {
        dontFixup = true;
        sourceUrl = "https://github.com/Hammerspoon/hammerspoon/releases/download/${packages.hammerspoon.version}/Hammerspoon-${packages.hammerspoon.version}.zip";
        platforms = [ "aarch64-darwin" ];
      };
      dia-browser = {
        dontFixup = true;
        sourceUrl = "https://releases.diabrowser.com/release/Dia-${packages.dia-browser.version}.zip";
        platforms = [ "aarch64-darwin" ];
      };
      orca-editor = {
        dontFixup = true;
        sourceUrl = "https://github.com/stablyai/orca/releases/download/v${packages.orca-editor.version}/orca-macos-arm64.dmg";
        platforms = [ "aarch64-darwin" ];
      };
    };
  };
}
