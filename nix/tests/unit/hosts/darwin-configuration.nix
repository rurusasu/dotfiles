{ inputs }:
let
  lib = inputs.nixpkgs.lib;
  system = "aarch64-darwin";
  workmux = import ../../../flakes/lib/workmux.nix { inherit inputs; };
  workmuxOverlay = workmux.mkOverlay (_: inputs.workmux.packages.${system}.default);

  mkDarwin =
    {
      withHermes ? false,
      withDocker ? false,
      withOllama ? false,
      sudoUser ? "rurusasu",
      currentUser ? "fallback-user",
      extraModules ? [ ],
    }:
    inputs.nix-darwin.lib.darwinSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        inherit sudoUser currentUser;
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
        ../../../hosts/darwin
      ]
      ++ extraModules;
    };

  defaultConfig = (mkDarwin { }).config;
  dockerConfig = (mkDarwin { withDocker = true; }).config;
  hermesConfig = (mkDarwin { withHermes = true; }).config;
  ollamaConfig = (mkDarwin { withOllama = true; }).config;
  profiles = {
    default = defaultConfig;
    ollama = ollamaConfig;
    docker = dockerConfig;
    hermes = hermesConfig;
  };
  sudoUserConfig =
    (mkDarwin {
      sudoUser = "ktome1995";
      currentUser = "root";
    }).config;
  currentUserFallbackConfig =
    (mkDarwin {
      sudoUser = "";
      currentUser = "ktome1995";
    }).config;
  defaultHome = defaultConfig.home-manager.users.rurusasu;
  nonstandardHomeConfig =
    (mkDarwin {
      sudoUser = "alice";
      extraModules = [
        { users.users.alice.home = inputs.nixpkgs.lib.mkForce "/Volumes/Home/alice"; }
      ];
    }).config;
  hermesHome = hermesConfig.home-manager.users.rurusasu;

  hasDarwinCask = name: config: builtins.any (cask: cask.name == name) config.homebrew.casks;
  packageNames =
    config: builtins.map (package: package.name or package.pname) config.environment.systemPackages;
  homePackageNames = home: builtins.map (package: package.name or package.pname) home.home.packages;
  darwinHomeSource = builtins.readFile ../../../home/darwin.nix;
  hasPrefix = prefix: value: builtins.match "${prefix}.*" value != null;
  hasPackage = name: packages: builtins.any (package: package == name) packages;
in
{
  testDarwinInstallsAndRegistersManagedUserZsh = {
    expr = {
      enabled = defaultConfig.programs.zsh.enable;
      shell = defaultConfig.users.users.rurusasu.shell;
      installed = builtins.elem (mkDarwin { }).pkgs.zsh defaultConfig.environment.systemPackages;
      registered =
        builtins.elem defaultConfig.users.users.rurusasu.shell defaultConfig.environment.shells;
      ownsAdminAccount = builtins.elem "rurusasu" defaultConfig.users.knownUsers;
    };
    expected = {
      enabled = true;
      shell = lib.getExe (mkDarwin { }).pkgs.zsh;
      installed = true;
      registered = true;
      ownsAdminAccount = false;
    };
  };

  testDarwinDefaultShellFollowsSelectedUser = {
    expr = {
      sudoUserShell = sudoUserConfig.users.users.ktome1995.shell;
      fallbackUserShell = currentUserFallbackConfig.users.users.ktome1995.shell;
      nonstandardHome = nonstandardHomeConfig.users.users.alice.home;
      ownsRoot = builtins.elem "root" sudoUserConfig.users.knownUsers;
    };
    expected = {
      sudoUserShell = lib.getExe (mkDarwin { }).pkgs.zsh;
      fallbackUserShell = lib.getExe (mkDarwin { }).pkgs.zsh;
      nonstandardHome = "/Volumes/Home/alice";
      ownsRoot = false;
    };
  };

  testDarwinConfigurationUsesConfiguredIdentity = {
    expr = {
      primaryUser = sudoUserConfig.system.primaryUser;
      homebrewUser = sudoUserConfig.nix-homebrew.user;
      systemHome = sudoUserConfig.users.users.ktome1995.home;
      homeManagerHome = sudoUserConfig.home-manager.users.ktome1995.home.homeDirectory;
      guestLogin = sudoUserConfig.system.defaults.loginwindow.GuestEnabled;
      showFullName = sudoUserConfig.system.defaults.loginwindow.SHOWFULLNAME;
    };
    expected = {
      primaryUser = "ktome1995";
      homebrewUser = "ktome1995";
      systemHome = "/Users/ktome1995";
      homeManagerHome = "/Users/ktome1995";
      guestLogin = false;
      showFullName = false;
    };
  };

  testDarwinConfigurationFallsBackToCurrentUser = {
    expr = {
      primaryUser = currentUserFallbackConfig.system.primaryUser;
      homebrewUser = currentUserFallbackConfig.nix-homebrew.user;
      home = currentUserFallbackConfig.users.users.ktome1995.home;
      homeManagerHome = currentUserFallbackConfig.home-manager.users.ktome1995.home.homeDirectory;
    };
    expected = {
      primaryUser = "ktome1995";
      homebrewUser = "ktome1995";
      home = "/Users/ktome1995";
      homeManagerHome = "/Users/ktome1995";
    };
  };

  # A conventional /Users/<name> fallback cannot substitute for the host home.
  testDarwinHomeManagerUsesNonstandardHostHome = {
    expr = {
      systemHome = nonstandardHomeConfig.users.users.alice.home;
      homeManagerHome = nonstandardHomeConfig.home-manager.users.alice.home.homeDirectory;
    };
    expected = {
      systemHome = "/Volumes/Home/alice";
      homeManagerHome = "/Volumes/Home/alice";
    };
  };

  testDarwinConfigurationKeepsSystemIntegrations = {
    expr = {
      homebrew = defaultConfig.homebrew.enable;
      nixHomebrew = defaultConfig.nix-homebrew.enable;
      raycast = builtins.any (name: hasPrefix "raycast" name) (packageNames defaultConfig);
      weztermTerminfo = builtins.match ".*pkgs[.]wezterm[.]terminfo.*" darwinHomeSource != null;
      github = builtins.any (name: builtins.match "^(gh|github-cli)($|[-.].*)" name != null) (
        packageNames defaultConfig
      );
      managedFont = builtins.any (
        package: hasPrefix "udev-gothic-nf" (package.name or package.pname)
      ) defaultConfig.fonts.packages;
      homeManagerUser = builtins.hasAttr "rurusasu" defaultConfig.home-manager.users;
      noOptionalOllamaAgent = builtins.hasAttr "com-dotfiles-ollama" defaultConfig.launchd.user.agents;
    };
    expected = {
      homebrew = true;
      nixHomebrew = true;
      raycast = true;
      weztermTerminfo = true;
      github = true;
      managedFont = true;
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

  testDarwinConfigurationIncludesSteamCask = {
    expr = hasDarwinCask "steam" defaultConfig;
    expected = true;
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

  testDarwinHomeManagerLeavesSystemFontToNixDarwin = {
    expr = {
      fontPackage = builtins.any (name: hasPrefix "udev-gothic-nf" name) (homePackageNames defaultHome);
      fontActivation = builtins.hasAttr "installDotfilesFonts" defaultHome.home.activation;
      fontconfig = defaultHome.fonts.fontconfig.enable;
      defaultFonts = {
        inherit (defaultHome.fonts.fontconfig.defaultFonts)
          monospace
          sansSerif
          serif
          emoji
          ;
      };
    };
    expected = {
      fontPackage = false;
      fontActivation = false;
      fontconfig = true;
      defaultFonts = {
        monospace = [ "UDEV Gothic NF" ];
        sansSerif = [ "UDEV Gothic NF" ];
        serif = [ "UDEV Gothic NF" ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
  };

  testDarwinHermesProfileUsesExpectedProviders = {
    expr = {
      hermesCask = hasDarwinCask "hermes-desktop" hermesConfig;
      dockerCask = hasDarwinCask "docker-desktop" hermesConfig;
      chromeSystemPackage = builtins.any (name: hasPrefix "google-chrome" name) (
        packageNames hermesConfig
      );
      discordSystemPackage = builtins.any (name: hasPrefix "discord" name) (packageNames hermesConfig);
      discordAgent = builtins.hasAttr "discord-module-staging" hermesConfig.launchd.user.agents;
    };
    expected = {
      hermesCask = true;
      dockerCask = true;
      chromeSystemPackage = true;
      discordSystemPackage = true;
      discordAgent = true;
    };
  };

  testDarwinDockerProfileUsesHomebrewCask = {
    expr = {
      dockerCask = hasDarwinCask "docker-desktop" dockerConfig;
      ollamaCask = hasDarwinCask "ollama-app" dockerConfig;
      chromeCask = hasDarwinCask "google-chrome" dockerConfig;
      discordCask = hasDarwinCask "discord" dockerConfig;
    };
    expected = {
      dockerCask = true;
      ollamaCask = false;
      chromeCask = false;
      discordCask = false;
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
      home = "/Users/rurusasu";
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

  testDarwinLegacyOmlxCleanupDefinitionIsAbsent = {
    expr = lib.mapAttrs (
      _: config: builtins.hasAttr "removeLegacyOmlx" config.system.activationScripts
    ) profiles;
    expected = {
      default = false;
      ollama = false;
      docker = false;
      hermes = false;
    };
  };

  # Check every evaluated fragment so renaming or moving the old commands cannot
  # restore the cleanup through another activation hook.
  testDarwinActivationScriptsDoNotReferenceLegacyOmlx = {
    expr = lib.mapAttrs (
      _: config:
      builtins.filter (
        name:
        let
          text = config.system.activationScripts.${name}.text;
        in
        # Avoid an unbounded regex over large generated activation scripts.
        builtins.replaceStrings [ "omlx" ] [ "" ] text != text
      ) (builtins.attrNames config.system.activationScripts)
    ) profiles;
    expected = {
      default = [ ];
      ollama = [ ];
      docker = [ ];
      hermes = [ ];
    };
  };
}
