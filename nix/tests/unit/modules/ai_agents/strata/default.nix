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
  feed = {
    app = {
      version = "9.8.7";
      platforms = {
        linux-x86_64 = {
          url = "https://github.com/Niko1221/Strata/releases/latest/download/Strata-9.8.7-linux-x86_64.AppImage";
          sha256 = builtins.concatStringsSep "" (builtins.genList (_: "a") 64);
        };
        darwin-aarch64 = {
          url = "https://github.com/Niko1221/Strata/releases/latest/download/Strata.app.tar.gz";
          sha256 = builtins.concatStringsSep "" (builtins.genList (_: "b") 64);
        };
      };
    };
    control = {
      version = "1.2.3";
      packages =
        map
          (platform: {
            inherit platform;
            url = "strata-control-1.2.3-${platform}.tar.gz";
            sha256 = builtins.concatStringsSep "" (builtins.genList (_: "c") 64);
          })
          [
            "linux-x86_64"
            "macos-arm64"
          ];
    };
  };
in
{
  testStrataUsesPlatformAssetsFromThePinnedFeedRelease = {
    expr =
      map
        (
          system:
          let
            packages = code.nix.modules.ai_agents.strata.package {
              pkgs = fixtures.mkPkgs system;
              inherit feed;
            };
          in
          {
            desktop = packages.desktop.version;
            control = packages.control.version;
            desktopUrls = packages.desktop.src.urls;
            desktopHash = packages.desktop.src.outputHash;
          }
        )
        [
          "x86_64-linux"
          "aarch64-darwin"
        ];
    expected = [
      {
        desktop = "9.8.7";
        control = "1.2.3";
        desktopUrls = [
          "https://github.com/Niko1221/Strata/releases/download/v9.8.7/Strata-9.8.7-linux-x86_64.AppImage"
        ];
        desktopHash = feed.app.platforms.linux-x86_64.sha256;
      }
      {
        desktop = "9.8.7";
        control = "1.2.3";
        desktopUrls = [ "https://github.com/Niko1221/Strata/releases/download/v9.8.7/Strata.app.tar.gz" ];
        desktopHash = feed.app.platforms.darwin-aarch64.sha256;
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
