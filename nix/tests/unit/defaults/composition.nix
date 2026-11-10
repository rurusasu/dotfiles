{ homeConfigurations, files }:
let
  inherit (homeConfigurations)
    linux
    wsl
    darwin
    configuredChrome
    ;

in
{
  testStrataInstallsNativeDesktopAndCommandLineApplications = {
    expr =
      map
        (home: {
          desktop = builtins.any (p: (p.pname or "") == "strata-desktop") home.config.home.packages;
          cli = builtins.any (p: (p.pname or "") == "strata-control") home.config.home.packages;
        })
        [
          linux
          wsl
        ];
    expected =
      map
        (_: {
          desktop = true;
          cli = true;
        })
        [
          linux
          wsl
        ];
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
    expected = "test-user";
  };

  testWslApplicationsSupplyPlatformEnvironment = {
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
      zoxideExclusion = "/mnt/wsl/*:/mnt/wslg/*";
      onePasswordAccount = wsl.config.dotfiles.onePassword.account;
      windowsEnvironment = "OP_ACCOUNT/u";
      signer = "${wsl.config.home.homeDirectory}/.local/bin/op-ssh-sign-wsl";
      signerBridge = {
        source = files.nix.modules.ssh.op-ssh-sign-wsl;
        executable = true;
      };
    };
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
