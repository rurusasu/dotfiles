{ inputs }:
let
  fixtures = import ../../fixtures/packages.nix { inherit inputs; };
  mkPkgs = system: fixtures.mkPkgs system;

  baseModule = _: {
    home = {
      username = "test-user";
      homeDirectory = "/home/test-user";
      stateVersion = "25.05";
    };
  };

  mkHome =
    {
      system,
      module,
      specialArgs ? { },
    }:
    let
      pkgs = mkPkgs system;
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs;
        installFeatures = [ ];
      }
      // specialArgs;
      modules = [
        baseModule
        module
      ]
      ++ ((import (
        if pkgs.stdenv.hostPlatform.isDarwin then
          ../../../modules/darwin/default.nix
        else
          ../../../modules/nixos/default.nix
      ) { inherit pkgs inputs; }).home-manager.sharedModules or [ ]
      );
    };

  common = mkHome {
    system = "x86_64-linux";
    module = ../../../home/common.nix;
  };

  linux = mkHome {
    system = "x86_64-linux";
    module = ../../../home/linux.nix;
  };

  wsl = mkHome {
    system = "x86_64-linux";
    module = ../../../home/wsl.nix;
  };

  darwin = mkHome {
    system = "aarch64-darwin";
    module = ../../../home/darwin.nix;
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
      sets = import ../../../packages/sets.nix {
        inherit pkgs;
        inherit (pkgs) lib;
        codexPackage = pkgs.hello;
      };
      contains = package: packages: builtins.elem package packages;
    in
    {
      inherit sets;
      inherit (pkgs) obsidian;
      inherit contains;
    };
in
{
  testCursorLspUsesHomeManagerAndOrdinaryPath = {
    expr =
      builtins.map
        (
          home:
          let
            cursor = home.config.programs.cursor;
            settings = cursor.profiles.default.userSettings or { };
            keybindings = cursor.profiles.default.keybindings;
            bindings =
              if builtins.isPath keybindings then
                builtins.fromJSON (builtins.readFile keybindings)
              else
                keybindings;
          in
          {
            enabled = cursor.enable;
            existingPackage = cursor.package == null;
            nixServer = settings."nix.serverPath" or "";
            formatter = settings."nix.serverSettings".nixd.formatting.command or [ ];
            ruffPath = settings."ruff.path" or [ ];
            gofumpt = settings.gopls."formatting.gofumpt" or false;
            rustCheck = settings."rust-analyzer.check.command" or "";
            theme = settings."workbench.colorTheme" or "";
            editorSplitKey = builtins.any (
              binding: binding.key == "ctrl+alt+\\" && binding.command == "workbench.action.splitEditorRight"
            ) bindings;
          }
        )
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      enabled = true;
      existingPackage = true;
      nixServer = "nixd";
      formatter = [ "nixfmt" ];
      ruffPath = [ "ruff" ];
      gofumpt = true;
      rustCheck = "clippy";
      theme = "Catppuccin Mocha";
      editorSplitKey = true;
    }) 3;
  };

  testRustToolsOutrankRetainedRustupAcrossHomes = {
    expr =
      map
        (
          home:
          let
            packages = home.config.home.packages;
            copies = target: builtins.filter (package: package.drvPath == target.drvPath) packages;
            priority = target: (builtins.head (copies target)).meta.priority or 5;
          in
          {
            rustupCopies = builtins.length (copies home.pkgs.rustup);
            analyzerCopies = builtins.length (copies home.pkgs.rust-analyzer);
            formatterCopies = builtins.length (copies home.pkgs.rustfmt);
            analyzerWins = priority home.pkgs.rust-analyzer < priority home.pkgs.rustup;
            formatterWins = priority home.pkgs.rustfmt < priority home.pkgs.rustup;
          }
        )
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      rustupCopies = 1;
      analyzerCopies = 1;
      formatterCopies = 1;
      analyzerWins = true;
      formatterWins = true;
    }) 3;
  };

  testNeovimMigrationGuardsForcedLinksBeforeWriting = {
    expr =
      map
        (
          home:
          let
            activation = home.config.home.activation;
          in
          {
            legacyActivator = home.config.home.fileActivator;
            initForced = home.config.xdg.configFile."nvim/init.lua".force;
            luaForced = home.config.xdg.configFile."nvim/lua".force;
            preflightBeforeLinks = builtins.elem "checkLinkTargets" activation.checkNeovimLegacyConfig.before;
            migrationAfterBoundary = builtins.elem "writeBoundary" activation.migrateNeovimLegacyConfig.after;
            migrationBeforeLinks = builtins.elem "linkGeneration" activation.migrateNeovimLegacyConfig.before;
          }
        )
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      legacyActivator = "legacy";
      initForced = true;
      luaForced = true;
      preflightBeforeLinks = true;
      migrationAfterBoundary = true;
      migrationBeforeLinks = true;
    }) 3;
  };

  testNeovimHomeManagerOwnership = {
    expr =
      builtins.map
        (
          home:
          let
            cfg = home.config.programs.neovim;
          in
          {
            enabled = cfg.enable;
            sideloadInit = cfg.sideloadInitLua;
            packageCopies = builtins.length (
              builtins.filter (package: package.drvPath == cfg.finalPackage.drvPath) home.config.home.packages
            );
            basePackageInstalled = builtins.any (
              package: package.drvPath == home.pkgs.neovim.drvPath
            ) home.config.home.packages;
            writesInit = home.config.xdg.configFile."nvim/init.lua".enable or false;
            pluginData = home.config.xdg.dataFile."nvim/site/pack/hm".enable;
            internalPackages = cfg.extraPackages == [ ];
            serverDependencies =
              builtins.all
                (package: builtins.any (extra: extra.drvPath == package.drvPath) home.config.home.packages)
                [
                  home.pkgs.gopls
                  home.pkgs.ruff
                  home.pkgs.ty
                  home.pkgs.lua-language-server
                  home.pkgs.typescript-language-server
                  home.pkgs.nixfmt
                ];
            remoteInstalled = builtins.any (
              package: package.drvPath == home.pkgs.neovim-remote.drvPath
            ) home.config.home.packages;
            globalServerPackages = builtins.any (
              package:
              builtins.elem package.drvPath (
                map (server: server.drvPath) [
                  home.pkgs.nixd
                  home.pkgs.gopls
                  home.pkgs.ruff
                ]
              )
            ) home.config.home.packages;
          }
        )
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      enabled = true;
      sideloadInit = false;
      packageCopies = 1;
      basePackageInstalled = false;
      writesInit = true;
      pluginData = true;
      internalPackages = true;
      serverDependencies = true;
      remoteInstalled = true;
      globalServerPackages = true;
    }) 3;
  };

  testHeadlessHomesDoNotEnableNativeCompositor = {
    expr =
      map
        (home: {
          enabled = home.config.wayland.windowManager.hyprland.enable;
          desktopPackages = builtins.filter (
            name:
            builtins.elem name [
              "hyprland"
              "fuzzel"
              "firefox"
              "nautilus"
            ]
          ) (map (package: package.pname or package.name) home.config.home.packages);
        })
        [
          linux
          wsl
        ];
    expected = [
      {
        enabled = false;
        desktopPackages = [ ];
      }
      {
        enabled = false;
        desktopPackages = [ ];
      }
    ];
  };
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
      sets = import ../../../packages/sets.nix {
        inherit pkgs;
        inherit (pkgs) lib;
        codexPackage = pkgs.hello;
      };
      catalogDrvPaths = builtins.map (package: package.drvPath) sets.all;
      selectedCatalogDrvPaths = builtins.sort builtins.lessThan (
        pkgs.lib.unique (
          builtins.filter (drvPath: builtins.elem drvPath catalogDrvPaths) (
            builtins.map (package: package.drvPath) wsl.config.home.packages
          )
        )
      );
      expectedCatalogDrvPaths = builtins.sort builtins.lessThan (
        pkgs.lib.unique (
          builtins.map (package: package.drvPath) (
            sets.allWithout (
              sets.nativeDesktopPackageNames
              ++ [
                "discord"
                "ollama"
              ]
            )
          )
        )
      );
      containsDrvPath =
        needle: packages: builtins.any (package: package.drvPath == needle.drvPath) packages;
    in
    {
      expr = {
        inherit selectedCatalogDrvPaths;
        excludesDiscord = !(containsDrvPath pkgs.discord wsl.config.home.packages);
        excludesOllama = !(containsDrvPath pkgs.ollama wsl.config.home.packages);
      };
      expected = {
        selectedCatalogDrvPaths = expectedCatalogDrvPaths;
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
        aerospace = {
          inTerminal = builtins.any (
            package: (package.pname or null) == "aerospace"
          ) darwinPackageSets.sets.terminal;
          darwin = {
            provider = report.aerospace.darwin.provider;
            source = report.aerospace.darwin.source;
            appName = report.aerospace.darwin.identity.appName;
          };
          linuxUnsupported = report.aerospace.linux.unsupported;
          windowsUnsupported = report.aerospace.windows.unsupported;
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
        aerospace = {
          inTerminal = true;
          darwin = {
            provider = "nix";
            source = "nixpkgs";
            appName = "AeroSpace.app";
          };
          linuxUnsupported = "AeroSpace is only available on macOS";
          windowsUnsupported = "AeroSpace is only available on macOS";
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
