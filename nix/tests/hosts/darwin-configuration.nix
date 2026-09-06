{ inputs }:
let
  system = "aarch64-darwin";
  workmux = import ../../flakes/lib/workmux.nix { inherit inputs; };
  workmuxOverlay = workmux.mkOverlay (_: inputs.workmux.packages.${system}.default);

  mkDarwin =
    {
      withHermes ? false,
      withDocker ? false,
      withOllama ? false,
    }:
    inputs.nix-darwin.lib.darwinSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        dotfilesUser = "test-user";
        dotfilesHome = "/Users/test-user";
        dotfilesWithHermes = withHermes;
        dotfilesWithDocker = withDocker;
        dotfilesWithOllama = withOllama;
      };
      modules = [
        inputs.nix-homebrew.darwinModules.nix-homebrew
        inputs.home-manager.darwinModules.home-manager
        {
          nixpkgs.config.allowUnfree = true;
          nixpkgs.overlays = [ workmuxOverlay ];
        }
        ../../hosts/darwin
      ];
    };

  defaultConfig = (mkDarwin { }).config;
  hermesConfig = (mkDarwin { withHermes = true; }).config;
  ollamaConfig = (mkDarwin { withOllama = true; }).config;
  defaultHome = defaultConfig.home-manager.users.test-user;
  hermesHome = hermesConfig.home-manager.users.test-user;

  hasDarwinCask = name: config: builtins.any (cask: cask.name == name) config.homebrew.casks;
  packageNames =
    config: builtins.map (package: package.name or package.pname) config.environment.systemPackages;
  darwinHomeSource = builtins.readFile ../../home/darwin.nix;
  hasPrefix = prefix: value: builtins.match "${prefix}.*" value != null;
  hasPackage = name: packages: builtins.any (package: package == name) packages;
in
{
  testDarwinConfigurationAcceptsInjectedIdentity = {
    expr = {
      primaryUser = defaultConfig.system.primaryUser;
      systemHome = defaultConfig.users.users.test-user.home;
      homeManagerHome = defaultHome.home.homeDirectory;
    };
    expected = {
      primaryUser = "test-user";
      systemHome = "/Users/test-user";
      homeManagerHome = "/Users/test-user";
    };
  };

  testDarwinConfigurationKeepsSystemIntegrations = {
    expr = {
      homebrew = defaultConfig.homebrew.enable;
      nixHomebrew = defaultConfig.nix-homebrew.enable;
      vscode = builtins.any (name: hasPrefix "vscode" name) (packageNames defaultConfig);
      raycast = builtins.any (name: hasPrefix "raycast" name) (packageNames defaultConfig);
      weztermTerminfo = builtins.match ".*pkgs[.]wezterm[.]terminfo.*" darwinHomeSource != null;
      github = builtins.any (name: builtins.match "^(gh|github-cli)($|[-.].*)" name != null) (
        packageNames defaultConfig
      );
      homeManagerUser = builtins.hasAttr "test-user" defaultConfig.home-manager.users;
      noOptionalOllamaAgent = builtins.hasAttr "com-dotfiles-ollama" defaultConfig.launchd.user.agents;
    };
    expected = {
      homebrew = true;
      nixHomebrew = true;
      vscode = true;
      raycast = true;
      weztermTerminfo = true;
      github = true;
      homeManagerUser = true;
      noOptionalOllamaAgent = false;
    };
  };

  testDarwinConfigurationKeepsDefaultCaskBoundary = {
    expr = {
      chrome = hasDarwinCask "google-chrome" defaultConfig;
      discord = hasDarwinCask "discord" defaultConfig;
      ollama = hasDarwinCask "ollama-app" defaultConfig;
      docker = hasDarwinCask "docker-desktop" defaultConfig;
    };
    expected = {
      chrome = false;
      discord = false;
      ollama = false;
      docker = false;
    };
  };

  testDarwinHomeManagerOwnsPlatformEnvironment = {
    expr = {
      autoUpdate = defaultHome.home.sessionVariables.HOMEBREW_AUTO_UPDATE_SECS;
      onePassword = defaultHome.home.sessionVariables.OP_BIOMETRIC_UNLOCK_ENABLED;
      homebrewPath = builtins.elem "/opt/homebrew/bin" defaultHome.home.sessionPath;
      sharedPath = builtins.elem "$HOME/.local/bin" defaultHome.home.sessionPath;
      terminfo = builtins.match ".*TERMINFO_DIRS.*" defaultHome.programs.zsh.envExtra != null;
    };
    expected = {
      autoUpdate = "86400";
      onePassword = "true";
      homebrewPath = true;
      sharedPath = true;
      terminfo = true;
    };
  };

  testDarwinHermesProfileUsesExpectedProviders = {
    expr = {
      hermesCask = hasDarwinCask "hermes-desktop" hermesConfig;
      chromeSystemPackage = builtins.any (name: hasPrefix "google-chrome" name) (
        packageNames hermesConfig
      );
      discordSystemPackage = builtins.any (name: hasPrefix "discord" name) (packageNames hermesConfig);
      discordAgent = builtins.hasAttr "discord-module-staging" hermesConfig.launchd.user.agents;
    };
    expected = {
      hermesCask = true;
      chromeSystemPackage = true;
      discordSystemPackage = true;
      discordAgent = true;
    };
  };

  testDarwinOllamaProfileUsesNativeLaunchAgent = {
    expr = {
      exists = builtins.hasAttr "com-dotfiles-ollama" ollamaConfig.launchd.user.agents;
      home = ollamaConfig.launchd.user.agents.com-dotfiles-ollama.serviceConfig.EnvironmentVariables.HOME;
      runAtLoad = ollamaConfig.launchd.user.agents.com-dotfiles-ollama.serviceConfig.RunAtLoad;
      keepAlive = ollamaConfig.launchd.user.agents.com-dotfiles-ollama.serviceConfig.KeepAlive;
    };
    expected = {
      exists = true;
      home = "/Users/test-user";
      runAtLoad = true;
      keepAlive = true;
    };
  };

  testDarwinHomebrewActivationControlsRemainDeclarative = {
    expr = {
      greedyCasks = defaultConfig.homebrew.greedyCasks;
      autoUpdate = defaultConfig.homebrew.onActivation.autoUpdate;
      upgrade = defaultConfig.homebrew.onActivation.upgrade;
      interval = defaultConfig.homebrew.onActivation.extraEnv.HOMEBREW_AUTO_UPDATE_SECS;
      hints = defaultConfig.homebrew.onActivation.extraEnv.HOMEBREW_NO_ENV_HINTS;
    };
    expected = {
      greedyCasks = true;
      autoUpdate = true;
      upgrade = true;
      interval = "86400";
      hints = "1";
    };
  };

  testDarwinLegacyOmlxCleanupRemainsInActivation = {
    expr = {
      uninstall =
        builtins.match ".*uninstall --formula omlx.*" defaultConfig.system.activationScripts.removeLegacyOmlx.text
        != null;
      untap =
        builtins.match ".*untap jundot/omlx.*" defaultConfig.system.activationScripts.removeLegacyOmlx.text
        != null;
    };
    expected = {
      uninstall = true;
      untap = true;
    };
  };
}
