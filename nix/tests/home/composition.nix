{ inputs }:
let
  fixtures = import ../../test-fixtures.nix { inherit inputs; };
  mkPkgs = system: fixtures.mkPkgs system;

  baseModule =
    { ... }:
    {
      home.username = "test-user";
      home.homeDirectory = "/home/test-user";
    };

  mkHome =
    {
      system,
      module,
      specialArgs ? { },
    }:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = mkPkgs system;
      extraSpecialArgs = {
        inherit inputs;
      }
      // specialArgs;
      modules = [
        baseModule
        module
      ];
    };

  common = mkHome {
    system = "x86_64-linux";
    module = ../../home/common.nix;
  };

  linux = mkHome {
    system = "x86_64-linux";
    module = ../../home/linux.nix;
  };

  wsl = mkHome {
    system = "x86_64-linux";
    module = ../../home/wsl.nix;
  };

  darwin = mkHome {
    system = "aarch64-darwin";
    module = ../../home/darwin.nix;
    specialArgs = {
      installFeatures = [ ];
    };
  };

  darwinPackageSets =
    let
      system = "aarch64-darwin";
      pkgs =
        (import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
        }).extend
          (
            _: _: {
              workmux = inputs.workmux.packages.${system}.default;
            }
          );
      sets = import ../../packages/sets.nix {
        inherit pkgs;
        lib = pkgs.lib;
        codexPackage = pkgs.hello;
      };
      contains = package: packages: builtins.elem package packages;
    in
    {
      inherit sets;
      obsidian = pkgs.obsidian;
      contains = contains;
    };
in
{
  testCommonHomeModuleEvaluatesWithoutOSSpecialArgs = {
    expr = common.config.home.username;
    expected = "test-user";
  };

  testLinuxHomeModuleRetainsSharedShellConfiguration = {
    expr = linux.config.programs.zsh.shellAliases.l;
    expected = "eza -lhaT --level=2 --icons=auto --hyperlink -F --group-directories-first --color=auto";
  };

  testNRShellAliasUsesPlatformInstallCommand = {
    expr = {
      wsl = wsl.config.programs.zsh.shellAliases.nrs;
      linux = linux.config.programs.zsh.shellAliases.nrs;
      darwin = darwin.config.programs.zsh.shellAliases.nrs;
    };
    expected = {
      wsl = "task --dir ~/.dotfiles nrs";
      linux = "~/.dotfiles/install.sh";
      darwin = "~/.dotfiles/install.sh";
    };
  };

  testLinuxHomeModuleDoesNotReceiveDarwinSessionVariables = {
    expr = builtins.hasAttr "HOMEBREW_AUTO_UPDATE_SECS" linux.config.home.sessionVariables;
    expected = false;
  };

  testWSLHomeModuleOwnsWSLSessionVariables = {
    expr = {
      browser = wsl.config.home.sessionVariables.BROWSER;
      inputMethod = wsl.config.home.sessionVariables.GTK_IM_MODULE;
      zoxideExclusion = wsl.config.home.sessionVariables._ZO_EXCLUDE_DIRS;
    };
    expected = {
      browser = "explorer.exe";
      inputMethod = "fcitx";
      zoxideExclusion = "/mnt/wsl/*:/mnt/wslg/*";
    };
  };

  testWSLHomeModuleExcludesNativeDesktopPackages =
    let
      pkgs = mkPkgs "x86_64-linux";
      sets = import ../../packages/sets.nix {
        inherit pkgs;
        lib = pkgs.lib;
        codexPackage = inputs."llm-agents".packages.${pkgs.stdenv.hostPlatform.system}.codex;
      };
      packageDrvPaths =
        packages: builtins.sort builtins.lessThan (builtins.map (package: package.drvPath) packages);
      containsDrvPath =
        needle: packages: builtins.any (package: package.drvPath == needle.drvPath) packages;
    in
    {
      expr = {
        packageComposition = packageDrvPaths wsl.config.home.packages;
        excludesDiscord = !(containsDrvPath pkgs.discord wsl.config.home.packages);
        excludesOllama = !(containsDrvPath pkgs.ollama wsl.config.home.packages);
      };
      expected = {
        packageComposition = packageDrvPaths (
          sets.allWithout [
            "discord"
            "ollama"
          ]
        );
        excludesDiscord = true;
        excludesOllama = true;
      };
    };

  testDarwinHomeModuleOwnsDarwinSessionVariables = {
    expr = {
      homebrew = darwin.config.home.sessionVariables.HOMEBREW_AUTO_UPDATE_SECS;
      onePassword = darwin.config.home.sessionVariables.OP_BIOMETRIC_UNLOCK_ENABLED;
      homebrewPath = builtins.elem "/opt/homebrew/bin" darwin.config.home.sessionPath;
      terminfo = builtins.match ".*TERMINFO_DIRS.*" darwin.config.programs.zsh.envExtra != null;
    };
    expected = {
      homebrew = "86400";
      onePassword = "true";
      homebrewPath = true;
      terminfo = true;
    };
  };

  testObsidianDeclaresCrossPlatformProviders = {
    expr = {
      windows = darwinPackageSets.sets.supportReport.obsidian.windows;
      darwin = darwinPackageSets.sets.supportReport.obsidian.darwin;
      linux = darwinPackageSets.sets.supportReport.obsidian.linux;
    };
    expected = {
      windows = {
        provider = "winget";
        source = "winget";
        identity = "Obsidian.Obsidian";
      };
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "obsidian";
        identity = {
          homepage = "https://obsidian.md/";
          appName = "Obsidian.app";
          bundleId = "md.obsidian";
          executable = "Obsidian";
        };
      };
      linux = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "obsidian";
        identity = "obsidian";
      };
    };
  };

  testObsidianDarwinGuiUsesSystemPackage = {
    expr = {
      system = darwinPackageSets.contains darwinPackageSets.obsidian (
        darwinPackageSets.sets.darwinSystemPackagesForInstallFeatures [ ]
      );
      home = darwinPackageSets.contains darwinPackageSets.obsidian (
        darwinPackageSets.sets.darwinHomePackagesForInstallFeatures [ ]
      );
    };
    expected = {
      system = true;
      home = false;
    };
  };

  testTerminalKeybindingHelpersHavePlatformScopedProviders =
    let
      report = darwinPackageSets.sets.supportReport;
    in
    {
      expr = {
        hammerspoon = {
          inTerminal = builtins.any (
            package: (package.pname or null) == "hammerspoon"
          ) darwinPackageSets.sets.terminal;
          darwin = {
            provider = report.hammerspoon.darwin.provider;
            source = report.hammerspoon.darwin.source;
            appName = report.hammerspoon.darwin.identity.appName;
            legacyName = report.hammerspoon.legacyDarwin.name;
          };
          linuxUnsupported = report.hammerspoon.linux.unsupported;
          windowsUnsupported = report.hammerspoon.windows.unsupported;
        };
        autohotkey = {
          wingetId = darwinPackageSets.sets.wingetMap.autohotkey;
          windows = {
            provider = report.autohotkey.windows.provider;
            source = report.autohotkey.windows.source;
            identity = report.autohotkey.windows.identity;
          };
          darwinUnsupported = report.autohotkey.darwin.unsupported;
          linuxUnsupported = report.autohotkey.linux.unsupported;
        };
      };
      expected = {
        hammerspoon = {
          inTerminal = true;
          darwin = {
            provider = "nix";
            source = "custom";
            appName = "Hammerspoon.app";
            legacyName = "hammerspoon";
          };
          linuxUnsupported = "Hammerspoon is only available on macOS";
          windowsUnsupported = "Hammerspoon is only available on macOS";
        };
        autohotkey = {
          wingetId = "AutoHotkey.AutoHotkey";
          windows = {
            provider = "winget";
            source = "winget";
            identity = "AutoHotkey.AutoHotkey";
          };
          darwinUnsupported = "AutoHotkey is only available on Windows";
          linuxUnsupported = "AutoHotkey is only available on Windows";
        };
      };
    };
}
