{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  inherit (pkgs) lib;
  merge = import ../../packages/catalog/merge.nix { inherit lib; };
  fixture = {
    pkg = pkgs.hello;
    category = "fixture";
    npm = "fixture-cli";
  };
  sets = import ../../packages/sets.nix {
    inherit pkgs lib;
    catalogOverride = {
      base = fixture;
      optional = fixture;
    };
  };
  actualSets = import ../../packages/sets.nix { inherit pkgs lib; };
in
{
  testFdAndPatinaUseCatalogProviders = {
    expr = {
      fdWindows = actualSets.wingetMap.fd;
      starshipWindows = actualSets.supportReport."Starship.Starship".windows.identity;
      patinaDarwin = actualSets.supportReport.zsh-patina.darwin.provider;
      patinaLinux = actualSets.supportReport.zsh-patina.linux.provider;
      patinaWindows = actualSets.supportReport.zsh-patina.windows.unsupported;
      patinaProviderErrors = builtins.filter (lib.hasPrefix "zsh-patina:") actualSets.providerErrors;
    };
    expected = {
      fdWindows = "sharkdp.fd";
      starshipWindows = "Starship.Starship";
      patinaDarwin = "nix";
      patinaLinux = "nix";
      patinaWindows = "No reviewed MSYS2/Cygwin package provider is selected";
      patinaProviderErrors = [ ];
    };
  };

  testShellPluginPackagesAreOwnedByHomeManagerModules = {
    expr = {
      remainingCatalogIds = builtins.filter (name: builtins.hasAttr name actualSets.supportReport) [
        "fzf"
        "zoxide"
        "eza"
        "bat"
        "ripgrep"
      ];
      windowsPlugins =
        map
          (id: {
            installed = builtins.elem id actualSets.windowsOnly.winget;
            provider = actualSets.supportReport.${id}.windows.provider;
            command = actualSets.wingetVerifyById.${id}.command;
          })
          [
            "junegunn.fzf"
            "ajeetdsouza.zoxide"
            "eza-community.eza"
            "BurntSushi.ripgrep.MSVC"
          ];
      ezaInstallArgs = actualSets.wingetInstallArgs."eza-community.eza";
      ezaDirectInstaller = actualSets.wingetDirectInstallers."eza-community.eza".executable;
      ezaPathEntries = actualSets.wingetPathEntries."eza-community.eza";
    };
    expected = {
      remainingCatalogIds = [ ];
      windowsPlugins =
        map
          (command: {
            installed = true;
            provider = "winget";
            inherit command;
          })
          [
            "fzf"
            "zoxide"
            "eza"
            "rg"
          ];
      ezaInstallArgs = [
        "--scope"
        "user"
      ];
      ezaDirectInstaller = "eza.exe";
      ezaPathEntries = [ "%LOCALAPPDATA%\\Programs\\eza" ];
    };
  };

  testSupportReportPublishesOnlyCurrentProviderMetadata = {
    expr = builtins.attrNames sets.supportReport.base;
    expected = [
      "darwin"
      "installFeature"
      "linux"
      "windows"
    ];
  };

  testPackageCatalogMergesDisjointOwners = {
    expr = merge {
      core.alpha.category = "core";
      dev.beta.category = "dev";
    };
    expected = {
      alpha.category = "core";
      beta.category = "dev";
    };
  };

  testPackageCatalogRejectsDuplicateOwners = {
    expr =
      (builtins.tryEval (merge {
        core.shared.category = "core";
        dev.shared.category = "dev";
      })).success;
    expected = false;
  };

  testPackageCatalogRejectsMisplacedCategory = {
    expr =
      (builtins.tryEval (merge {
        core.misplaced.category = "dev";
      })).success;
    expected = false;
  };

  testPackageCatalogOverrideRemainsIsolated = {
    expr = {
      catalogIds = builtins.filter (name: !(builtins.hasAttr name sets.windowsOnlySupport)) (
        builtins.attrNames sets.supportReport
      );
      inherit (sets) npmMap wingetMap providerErrors;
      baseProvider = sets.supportReport.base.windows;
    };
    expected = {
      catalogIds = [
        "base"
        "optional"
      ];
      npmMap = {
        base = "fixture-cli";
        optional = "fixture-cli";
      };
      wingetMap = { };
      providerErrors = [ ];
      baseProvider = {
        provider = "npm";
        source = "npm";
        identity = "fixture-cli";
      };
    };
  };

  testPackageCatalogOverridePreservesSelection = {
    expr = lib.mapAttrs (_: packages: map (package: package.drvPath) packages) {
      category = sets.fixture;
      inherit (sets) all;
      excluded = sets.allWithout [ "base" ];
      explicit = sets.resolve [
        "optional"
        "base"
      ];
    };
    expected =
      let
        hello = pkgs.hello.drvPath;
      in
      {
        category = [
          hello
          hello
        ];
        all = [
          hello
          hello
        ];
        excluded = [ hello ];
        explicit = [
          hello
          hello
        ];
      };
  };
}
