{
  fixtures,
  code,
  homeConfigurations,
}:
let
  darwin = fixtures.mkHome "aarch64-darwin" [
    (fixtures.homeModule "darwin")
    ({ lib, ... }: {
      targets.darwin.copyApps.enable = lib.mkDefault true;
      targets.darwin.linkApps.enable = lib.mkDefault false;
    })
  ];
  hash = builtins.concatStringsSep "" (builtins.genList (_: "a") 64);
  manifest =
    builtins.concatStringsSep "\n" (
      map (name: "${hash}  ${name}") [
        "Strata-9.8.7-linux-x86_64.AppImage"
        "Strata.app.tar.gz"
        "strata-control-1.2.3-linux-x86_64.tar.gz"
        "strata-control-1.2.3.1-linux-x86_64.tar.gz"
        "strata-control-1.2.3-macos-arm64.tar.gz"
      ]
    )
    + "\n";
in
{
  testStrataUsesLatestControlForEachPlatformFromThePinnedRelease = {
    expr =
      map
        (
          system:
          let
            packages = code.nix.modules.ai_agents.strata.package {
              pkgs = fixtures.mkPkgs system;
              inherit manifest;
            };
          in
          {
            desktop = packages.desktop.version;
            control = packages.control.version;
            desktopUrls = packages.desktop.src.urls;
            desktopHash = packages.desktop.src.outputHash;
            controlUrls = packages.control.controlContents.src.urls;
          }
        )
        [
          "x86_64-linux"
          "aarch64-darwin"
        ];
    expected = [
      {
        desktop = "9.8.7";
        control = "1.2.3.1";
        desktopUrls = [
          "https://github.com/Niko1221/Strata/releases/download/v9.8.7/Strata-9.8.7-linux-x86_64.AppImage"
        ];
        desktopHash = hash;
        controlUrls = [
          "https://github.com/Niko1221/Strata/releases/download/v9.8.7/strata-control-1.2.3.1-linux-x86_64.tar.gz"
        ];
      }
      {
        desktop = "9.8.7";
        control = "1.2.3";
        desktopUrls = [ "https://github.com/Niko1221/Strata/releases/download/v9.8.7/Strata.app.tar.gz" ];
        desktopHash = hash;
        controlUrls = [
          "https://github.com/Niko1221/Strata/releases/download/v9.8.7/strata-control-1.2.3-macos-arm64.tar.gz"
        ];
      }
    ];
  };
  testStrataProtectsTheCopiedBundleAfterCopyApps = {
    expr = darwin.config.home.activation.strataProtectSignedBundle.after;
    expected = [ "copyApps" ];
  };
  testStrataDoesNotProtectAnUnmanagedOrDisabledBundle = {
    expr = map (home: home.config.home.activation ? strataProtectSignedBundle) [
      (darwin.extendModules {
        modules = [ { programs.strata.enable = darwin.pkgs.lib.mkForce false; } ];
      })
      (darwin.extendModules {
        modules = [ { targets.darwin.copyApps.enable = false; } ];
      })
      homeConfigurations.linux
    ];
    expected = [
      false
      false
      false
    ];
  };
}
