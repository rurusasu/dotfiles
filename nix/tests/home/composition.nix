{ inputs }:
let
  mkPkgs =
    system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

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
    specialArgs = {
      isWSL = false;
    };
  };

  wsl = mkHome {
    system = "x86_64-linux";
    module = ../../home/wsl.nix;
    specialArgs = {
      isWSL = true;
    };
  };

  darwin = mkHome {
    system = "aarch64-darwin";
    module = ../../home/darwin.nix;
    specialArgs = {
      installFeatures = [ ];
      isWSL = false;
    };
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
}
