{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    linux
    wsl
    wslDeclarations
    darwin
    configuredChrome
    ;
  darwinDeclarations = (import ../../../default.nix { }).homeModules.darwin {
    inherit inputs;
    inherit (darwin) pkgs;
    inherit (darwin.pkgs) lib;
    inherit (darwin) config;
  };
in
{
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
    expr = homeConfigurations.common.config.home.username;
    expected = homeConfigurations.testHome.username;
  };

  testNRShellAliasUsesPlatformInstallCommand = {
    expr = {
      wsl = wsl.config.programs.zsh.shellAliases.nrs;
      linux = linux.config.programs.zsh.shellAliases.nrs;
      darwin = darwin.config.programs.zsh.shellAliases.nrs;
    };
    expected = {
      wsl = wslDeclarations.programs.zsh.shellAliases.nrs;
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
      qtInputMethod = wsl.config.home.sessionVariables.QT_IM_MODULE;
      xModifiers = wsl.config.home.sessionVariables.XMODIFIERS;
      globalLanguage = wsl.config.home.sessionVariables.LANG or null;
      globalLocale = wsl.config.home.sessionVariables.LC_ALL or null;
      zoxideExclusion = wsl.config.home.sessionVariables._ZO_EXCLUDE_DIRS;
      onePasswordAccount = wsl.config.home.sessionVariables.OP_ACCOUNT;
      windowsEnvironment = wsl.config.home.sessionVariables.WSLENV;
      signer = wsl.config.programs.git.signing.signer;
      signerBridge = {
        source = wsl.config.home.file.".local/bin/op-ssh-sign-wsl".source;
        executable = wsl.config.home.file.".local/bin/op-ssh-sign-wsl".executable;
      };
    };
    expected = {
      browser = "${configuredChrome wsl}/bin/google-chrome-stable";
      inputMethod = "fcitx";
      qtInputMethod = "fcitx";
      xModifiers = "@im=fcitx";
      globalLanguage = null;
      globalLocale = null;
      zoxideExclusion = wslDeclarations.home.sessionVariables._ZO_EXCLUDE_DIRS;
      onePasswordAccount = wslDeclarations.home.sessionVariables.OP_ACCOUNT;
      windowsEnvironment = wslDeclarations.home.sessionVariables.WSLENV;
      signer = wslDeclarations.programs.git.signing.signer;
      signerBridge = {
        inherit (wslDeclarations.home.file.".local/bin/op-ssh-sign-wsl") source executable;
      };
    };
  };

  testWslAndNativeLinuxDesktopPackageSelection = {
    expr =
      map
        (
          home:
          let
            contains =
              package: builtins.any (candidate: candidate.drvPath == package.drvPath) home.config.home.packages;
          in
          {
            chrome = contains (configuredChrome home);
            rawChrome = contains home.pkgs.google-chrome;
            spotify = contains home.pkgs.spotify;
            signal = contains home.pkgs.signal-desktop;
            obsidian = contains home.pkgs.obsidian;
            onePassword = contains home.pkgs._1password-gui;
            nautilus = contains home.pkgs.nautilus;
            browser = home.config.home.sessionVariables.BROWSER or null;
          }
        )
        [
          wsl
          linux
        ];
    expected = [
      {
        chrome = true;
        rawChrome = false;
        spotify = true;
        signal = true;
        obsidian = true;
        onePassword = true;
        nautilus = true;
        browser = "${configuredChrome wsl}/bin/google-chrome-stable";
      }
      {
        chrome = false;
        rawChrome = true;
        spotify = false;
        signal = false;
        obsidian = true;
        onePassword = true;
        nautilus = true;
        browser = null;
      }
    ];
  };

  testWslDesktopExtrasGuardUnsupportedPlatforms = {
    expr =
      map
        (
          system:
          builtins.filter
            (
              package:
              builtins.elem (package.pname or package.name) [
                "spotify"
                "signal-desktop"
              ]
            )
            ((import ../../fixtures/packages.nix { inherit inputs; }).mkHome system [
              (import ../../../modules/tools.nix).wslDesktop
            ]).config.home.packages
        )
        [
          "aarch64-linux"
          "aarch64-darwin"
        ];
    expected = [
      [ ]
      [ ]
    ];
  };

  testDarwinHomeDoesNotInstallLinuxGuiPackages = {
    expr = builtins.filter (
      package:
      builtins.elem (package.pname or package.name) [
        "google-chrome"
        "nautilus"
      ]
    ) darwin.config.home.packages;
    expected = [ ];
  };

  testWSLHomeModuleExcludesNativeDesktopPackages =
    let
      pkgs = homeConfigurations.mkPkgs "x86_64-linux";
      contains = needle: packages: builtins.any (package: package.drvPath == needle.drvPath) packages;
    in
    {
      expr = {
        sharedTools =
          builtins.all (package: contains package wsl.config.home.packages)
            ((import ../../../modules/tools.nix).homeManager {
              inherit (wsl) config;
              inherit inputs pkgs;
              inherit (pkgs) lib;
            }).home.packages;
        excludesDiscord = !(contains pkgs.discord wsl.config.home.packages);
        excludesCompositor = !(contains pkgs.hyprland wsl.config.home.packages);
        excludesLauncher = !(contains pkgs.fuzzel wsl.config.home.packages);
      };
      expected = {
        sharedTools = true;
        excludesDiscord = true;
        excludesCompositor = true;
        excludesLauncher = true;
      };
    };

  testDarwinHomeModuleOwnsDarwinSessionVariables = {
    expr = {
      homebrew = darwin.config.home.sessionVariables.HOMEBREW_AUTO_UPDATE_SECS;
      onePassword = darwin.config.home.sessionVariables.OP_BIOMETRIC_UNLOCK_ENABLED;
      homebrewPaths = builtins.all (
        path: builtins.elem path darwin.config.home.sessionPath
      ) darwinDeclarations.home.sessionPath;
    };
    expected = {
      homebrew = darwinDeclarations.home.sessionVariables.HOMEBREW_AUTO_UPDATE_SECS;
      onePassword = darwinDeclarations.home.sessionVariables.OP_BIOMETRIC_UNLOCK_ENABLED;
      homebrewPaths = true;
    };
  };

  testTerminalKeybindingHelpersHavePlatformScopedPackages = {
    expr = {
      darwinHome = builtins.any (
        package: package.drvPath == darwin.pkgs.aerospace.drvPath
      ) darwin.config.home.packages;
      linuxHome = builtins.any (package: (package.pname or "") == "aerospace") linux.config.home.packages;
      wslHome = builtins.any (package: (package.pname or "") == "aerospace") wsl.config.home.packages;
    };
    expected = {
      darwinHome = true;
      linuxHome = false;
      wslHome = false;
    };
  };
}
