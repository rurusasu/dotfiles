{ fixtures, code }:
let
  pkgs = fixtures.mkPkgs "x86_64-linux";
  release = {
    tag_name = "v9.8.7";
    assets = [
      {
        name = "Strata-9.8.7-linux-x86_64.AppImage";
        browser_download_url = "https://example.invalid/Strata.AppImage";
        digest = "sha256:${pkgs.lib.concatStrings (builtins.genList (_: "a") 64)}";
      }
      {
        name = "strata-control-1.2.3-linux-x86_64.tar.gz";
        browser_download_url = "https://example.invalid/control.tar.gz";
        digest = "sha256:${pkgs.lib.concatStrings (builtins.genList (_: "b") 64)}";
      }
    ];
  };
  packages =
    selected:
    code.nix.modules.ai_agents.strata.package {
      inherit pkgs;
      release = selected;
    };
  selected = packages release;
  darwinPkgs = fixtures.mkPkgs "aarch64-darwin";
  darwinRelease = release // {
    assets = [
      {
        name = "Strata.app.tar.gz";
        browser_download_url = "https://example.invalid/Strata.app.tar.gz";
        digest = "sha256:${pkgs.lib.concatStrings (builtins.genList (_: "c") 64)}";
      }
      {
        name = "strata-control-1.2.3-macos-arm64.tar.gz";
        browser_download_url = "https://example.invalid/control-macos.tar.gz";
        digest = "sha256:${pkgs.lib.concatStrings (builtins.genList (_: "d") 64)}";
      }
    ];
  };
  darwinPackages = code.nix.modules.ai_agents.strata.package {
    pkgs = darwinPkgs;
    release = darwinRelease;
  };
  unsigned = packages (
    release
    // {
      assets = map (asset: builtins.removeAttrs asset [ "digest" ]) release.assets;
    }
  );
  ambiguous = packages (
    release
    // {
      assets = release.assets ++ [ (builtins.elemAt release.assets 1) ];
    }
  );
in
{
  testStrataDarwinSelectsNativeArchives = {
    expr = {
      desktop = darwinPackages.desktop.version;
      control = darwinPackages.control.version;
      product = darwinPackages.control.productVersion;
      desktopHash = darwinPackages.desktop.src.outputHash;
      platforms = darwinPackages.desktop.meta.platforms;
      controlPlatforms = darwinPackages.control.meta.platforms;
    };
    expected = {
      desktop = "9.8.7";
      control = "1.2.3";
      product = "9.8.7";
      desktopHash = pkgs.lib.concatStrings (builtins.genList (_: "c") 64);
      platforms = [ "aarch64-darwin" ];
      controlPlatforms = [ "aarch64-darwin" ];
    };
  };
  testStrataDarwinIsEnabledByThePlatform = {
    expr =
      (fixtures.mkHome "aarch64-darwin" [ (fixtures.homeModule "darwin") ]).config.programs.strata.enable;
    expected = true;
  };
  testStrataFeedIncludesMacDesktopAndControl = {
    expr = code.nix.modules.ai_agents.strata.release {
      app = {
        version = "9.8.7";
        platforms.darwin-aarch64 = {
          url = "https://github.com/Niko1221/Strata/releases/latest/download/Strata.app.tar.gz";
          sha256 = "mac-desktop-hash";
        };
      };
      control.packages = [
        {
          platform = "macos-arm64";
          url = "strata-control-1.2.3-macos-arm64.tar.gz";
          sha256 = "mac-control-hash";
        }
      ];
    };
    expected = {
      tag_name = "v9.8.7";
      assets = [
        {
          name = "Strata.app.tar.gz";
          browser_download_url = "https://github.com/Niko1221/Strata/releases/download/v9.8.7/Strata.app.tar.gz";
          digest = "sha256:mac-desktop-hash";
        }
        {
          name = "strata-control-1.2.3-macos-arm64.tar.gz";
          browser_download_url = "https://github.com/Niko1221/Strata/releases/download/v9.8.7/strata-control-1.2.3-macos-arm64.tar.gz";
          digest = "sha256:mac-control-hash";
        }
      ];
    };
  };
  testStrataFeedResolvesAssetsToItsVersionedRelease = {
    expr = code.nix.modules.ai_agents.strata.release {
      app = {
        version = "9.8.7";
        platforms.linux-x86_64 = {
          url = "https://github.com/Niko1221/Strata/releases/latest/download/Strata-9.8.7-linux-x86_64.AppImage";
          sha256 = "desktop-hash";
        };
      };
      control.packages = [
        {
          platform = "linux-x86_64";
          url = "strata-control-1.2.3-linux-x86_64.tar.gz";
          sha256 = "control-hash";
        }
        {
          platform = "darwin-aarch64";
          url = "unrelated.tar.gz";
          sha256 = "unrelated-hash";
        }
      ];
    };
    expected = release // {
      assets = [
        {
          name = "Strata-9.8.7-linux-x86_64.AppImage";
          browser_download_url = "https://github.com/Niko1221/Strata/releases/download/v9.8.7/Strata-9.8.7-linux-x86_64.AppImage";
          digest = "sha256:desktop-hash";
        }
        {
          name = "strata-control-1.2.3-linux-x86_64.tar.gz";
          browser_download_url = "https://github.com/Niko1221/Strata/releases/download/v9.8.7/strata-control-1.2.3-linux-x86_64.tar.gz";
          digest = "sha256:control-hash";
        }
      ];
    };
  };
  testStrataReleaseMetadataSelectsMatchingDesktopAndControl = {
    expr = {
      desktop = selected.desktop.version;
      control = selected.control.version;
      product = selected.control.productVersion;
      desktopHash = selected.desktop.src.outputHash;
      desktopTag = selected.desktop.releaseTag;
      controlTag = selected.control.releaseTag;
      platforms = selected.desktop.meta.platforms;
    };
    expected = {
      desktop = "9.8.7";
      control = "1.2.3";
      product = "9.8.7";
      desktopHash = pkgs.lib.concatStrings (builtins.genList (_: "a") 64);
      desktopTag = "v9.8.7";
      controlTag = "v9.8.7";
      platforms = [ "x86_64-linux" ];
    };
  };
  testStrataRejectsReleaseAssetsWithoutDigests = {
    expr = (builtins.tryEval unsigned.desktop.src.drvPath).success;
    expected = false;
  };
  testStrataRejectsAmbiguousControlAssets = {
    expr = (builtins.tryEval ambiguous.control.drvPath).success;
    expected = false;
  };
  testStrataRejectsUnsupportedNativeArchitectures = {
    expr =
      (builtins.tryEval (
        code.nix.modules.ai_agents.strata.package {
          pkgs = fixtures.mkPkgs "aarch64-linux";
          inherit release;
        }
      )).success;
    expected = false;
  };
}
