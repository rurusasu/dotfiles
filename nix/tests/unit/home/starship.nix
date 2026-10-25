{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  fixtures = import ../../fixtures/packages.nix { inherit inputs; };
  mkSettings =
    system: extraConfig:
    (fixtures.mkHome system [
      ../../../modules/shells/plugins/starship
      { programs.starship.enable = true; }
      extraConfig
    ]).config.programs.starship.settings;
  nixos = mkSettings "x86_64-linux" { dotfiles.starship.osSymbol = "❄️ "; };
  darwin = mkSettings "aarch64-darwin" { dotfiles.starship.osSymbol = "🍎 "; };
  fallback = mkSettings "x86_64-linux" { };
  homeFixtures = homeConfigurations;
  inherit (homeFixtures) homes lib;
  declaredHostSettings =
    module: pkgs:
    import module {
      inherit inputs lib pkgs;
      config = homeFixtures.sharedConfig;
    };
  hostSettings = [
    (declaredHostSettings ../../../hosts/shared/linux-home.nix homeFixtures.linux.pkgs)
    (declaredHostSettings ../../../hosts/x86_64-linux/wsl/home.nix homeFixtures.wsl.pkgs)
    (declaredHostSettings ../../../hosts/aarch64-darwin/home.nix homeFixtures.darwin.pkgs)
  ];
in
{
  testStarshipStaticNixOSSymbolReplacesRuntimeOsModule = {
    expr = {
      inherit (nixos) format;
      osDisabled = nixos.os.disabled;
    };
    expected = {
      format = "[❄️ ](bold white) $username$hostname$memory_usage$directory$git_branch$git_status$nix_shell$character";
      osDisabled = true;
    };
  };

  testStarshipStaticDarwinSymbolReplacesRuntimeOsModule = {
    expr = {
      inherit (darwin) format;
      osDisabled = darwin.os.disabled;
    };
    expected = {
      format = "[🍎 ](bold white) $username$hostname$memory_usage$directory$git_branch$git_status$nix_shell$character";
      osDisabled = true;
    };
  };

  testStarshipUnknownOsKeepsRuntimeDetection = {
    expr = {
      inherit (fallback) format;
      osDisabled = fallback.os.disabled;
      osFormat = fallback.os.format;
    };
    expected = {
      format = "$os$username$hostname$memory_usage$directory$git_branch$git_status$nix_shell$character";
      osDisabled = false;
      osFormat = "[$symbol]($style) ";
    };
  };

  testStarshipShellIntegrationAcrossHomes = {
    expr = map (home: {
      starshipEnabled = home.config.programs.starship.enable;
      starshipZshIntegration = home.config.programs.starship.enableZshIntegration;
      starshipInit = lib.hasInfix (builtins.unsafeDiscardStringContext ''eval "$(${lib.getExe home.config.programs.starship.package} init zsh)"'') home.config.programs.zsh.initContent;
    }) homes;
    expected = map (_: {
      starshipEnabled = homeFixtures.sharedConfig.programs.starship.enable;
      starshipZshIntegration = homeFixtures.sharedConfig.programs.starship.enableZshIntegration;
      starshipInit = true;
    }) homes;
  };

  testHostPromptsUseKnownOperatingSystems = {
    expr = map (home: {
      symbol = home.config.dotfiles.starship.osSymbol;
      runtimeOsDetection = !home.config.programs.starship.settings.os.disabled;
      windowsStarship = home.config.programs.starship.settings.git_status.windows_starship or null;
    }) homes;
    expected = map (settings: {
      symbol = settings.dotfiles.starship.osSymbol;
      runtimeOsDetection = false;
      windowsStarship = settings.programs.starship.settings.git_status.windows_starship or null;
    }) hostSettings;
  };

  testWslWindowsPromptReadsTheGeneratedConfigDirectly = {
    expr = {
      wslUsesSource =
        homeFixtures.wsl.config.home.sessionVariables.STARSHIP_CONFIG == toString
          homeFixtures.wsl.config.home.file.${homeFixtures.wsl.config.programs.starship.configPath}.source;
      linuxUsesConfigPath =
        homeFixtures.linux.config.home.sessionVariables.STARSHIP_CONFIG
        == homeFixtures.linux.config.programs.starship.configPath;
      darwinUsesConfigPath =
        homeFixtures.darwin.config.home.sessionVariables.STARSHIP_CONFIG
        == homeFixtures.darwin.config.programs.starship.configPath;
    };
    expected = {
      wslUsesSource = true;
      linuxUsesConfigPath = true;
      darwinUsesConfigPath = true;
    };
  };
}
