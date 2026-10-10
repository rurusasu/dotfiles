{ inputs }:
let
  system = "aarch64-darwin";

  mkDarwin =
    {
      sudoUser ? "rurusasu",
      currentUser ? "fallback-user",
      extraModules ? [ ],
    }:
    inputs.nix-darwin.lib.darwinSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        inherit sudoUser currentUser;
      };
      modules = [
        inputs.nix-homebrew.darwinModules.nix-homebrew
        inputs.home-manager.darwinModules.home-manager
        {
          nixpkgs.config.allowUnfree = true;
        }
        ../../../hosts/aarch64-darwin
      ]
      ++ extraModules;
    };

  defaultConfig = (mkDarwin { }).config;
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

  hasDarwinCask = name: config: builtins.any (cask: cask.name == name) config.homebrew.casks;
  packageNames =
    config: builtins.map (package: package.name or package.pname) config.environment.systemPackages;
  homePackageNames = home: builtins.map (package: package.name or package.pname) home.home.packages;
  hasPrefix = prefix: value: builtins.match "${prefix}.*" value != null;
in
{
  testOrcaModuleInstallsEditorOnceInDarwinHomeProfile = {
    expr = map (package: package.pname) (
      builtins.filter (package: (package.pname or "") == "orca-editor") defaultHome.home.packages
    );
    expected = [ "orca-editor" ];
  };

  testDarwinConfiguresZshWithoutChangingAccountShell = {
    expr = {
      enabled = defaultConfig.programs.zsh.enable;
      customActivation = builtins.hasAttr "defaultUserShell" defaultConfig.system.activationScripts;
      ownsAdminAccount = builtins.elem "rurusasu" defaultConfig.users.knownUsers;
    };
    expected = {
      enabled = true;
      customActivation = false;
      ownsAdminAccount = false;
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
      onePasswordDesktopCopies = builtins.length (
        builtins.filter (
          package: (package.pname or "") == "1password"
        ) defaultConfig.environment.systemPackages
      );
      agentEnvironment = defaultConfig.launchd.user.envVariables.SSH_AUTH_SOCK;
      gpgSshAgentEnabled = defaultConfig.programs.gnupg.agent.enableSSHSupport;
      homebrew = defaultConfig.homebrew.enable;
      nixHomebrew = defaultConfig.nix-homebrew.enable;
      raycast = builtins.any (name: hasPrefix "raycast" name) (packageNames defaultConfig);
      weztermTerminfo = builtins.any (
        package: toString package == toString defaultHome.programs.wezterm.package.terminfo
      ) defaultHome.home.packages;
      github = builtins.any (name: builtins.match "^(gh|github-cli)($|[-.].*)" name != null) (
        packageNames defaultConfig
      );
      managedFont = builtins.any (
        package: hasPrefix "udev-gothic-nf" (package.name or package.pname)
      ) defaultConfig.fonts.packages;
      homeManagerUser = builtins.hasAttr "rurusasu" defaultConfig.home-manager.users;
    };
    expected = {
      onePasswordDesktopCopies = 1;
      agentEnvironment = "/Users/rurusasu/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
      gpgSshAgentEnabled = false;
      homebrew = true;
      nixHomebrew = true;
      raycast = true;
      weztermTerminfo = true;
      github = true;
      managedFont = true;
      homeManagerUser = true;
    };
  };

  testDarwinConfigurationKeepsDefaultCaskBoundary = {
    expr = {
      chrome = hasDarwinCask "google-chrome" defaultConfig;
      discord = hasDarwinCask "discord" defaultConfig;
      docker = hasDarwinCask "docker-desktop" defaultConfig;
    };
    expected = {
      chrome = false;
      discord = false;
      docker = true;
    };
  };

  testDarwinConfigurationIncludesSteamCask = {
    expr = hasDarwinCask "steam" defaultConfig;
    expected = true;
  };

  testDarwinDockerInitializationUsesConfiguredIdentityAndHome = {
    expr = {
      configuredUser = inputs.nixpkgs.lib.hasInfix "--user=${inputs.nixpkgs.lib.escapeShellArg "ktome1995"}" sudoUserConfig.system.activationScripts.postActivation.text;
      hostHome = inputs.nixpkgs.lib.hasInfix (inputs.nixpkgs.lib.escapeShellArg "/Volumes/Home/alice/.config/dotfiles") nonstandardHomeConfig.system.activationScripts.postActivation.text;
      acceptsLicense = inputs.nixpkgs.lib.hasInfix "--accept-license" defaultConfig.system.activationScripts.postActivation.text;
    };
    expected = {
      configuredUser = true;
      hostHome = true;
      acceptsLicense = true;
    };
  };

  testDarwinDockerInitializationRequiresDeclaredCask = {
    expr =
      let
        withoutDocker =
          (mkDarwin {
            extraModules = [ { homebrew.casks = inputs.nixpkgs.lib.mkForce [ ]; } ];
          }).config;
      in
      inputs.nixpkgs.lib.hasInfix "--accept-license" withoutDocker.system.activationScripts.postActivation.text;
    expected = false;
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

  testDarwinHermesUsesExpectedProviders = {
    expr = {
      hermesCask = hasDarwinCask "hermes-desktop" defaultConfig;
      dockerCask = hasDarwinCask "docker-desktop" defaultConfig;
      chromeSystemPackage = builtins.any (name: hasPrefix "google-chrome" name) (
        packageNames defaultConfig
      );
      discordHomePackage = builtins.any (name: hasPrefix "discord" name) (homePackageNames defaultHome);
      discordAgent = builtins.hasAttr "discord-module-staging" defaultHome.launchd.agents;
    };
    expected = {
      hermesCask = true;
      dockerCask = true;
      chromeSystemPackage = true;
      discordHomePackage = true;
      discordAgent = true;
    };
  };

  testDarwinHomebrewActivationControlsRemainDeclarative = {
    expr = {
      greedyCasks = defaultConfig.homebrew.greedyCasks;
      autoUpdate = defaultConfig.homebrew.onActivation.autoUpdate;
      upgrade = defaultConfig.homebrew.onActivation.upgrade;
      cleanup = defaultConfig.homebrew.onActivation.cleanup;
      interval = defaultConfig.homebrew.onActivation.extraEnv.HOMEBREW_AUTO_UPDATE_SECS;
      hints = defaultConfig.homebrew.onActivation.extraEnv.HOMEBREW_NO_ENV_HINTS;
    };
    expected = {
      greedyCasks = true;
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap";
      interval = "86400";
      hints = "1";
    };
  };

  testDarwinRunsWeeklySystemGarbageCollection = {
    expr = {
      automatic = defaultConfig.nix.gc.automatic;
      interval = map (interval: {
        inherit (interval) Weekday Hour Minute;
      }) defaultConfig.launchd.daemons.nix-gc.serviceConfig.StartCalendarInterval;
      options = defaultConfig.nix.gc.options;
      userGc = defaultConfig.home-manager.users.rurusasu.nix.gc.automatic;
      cacheMaintenance = defaultHome.launchd.agents.tool-cache-maintenance.enable;
      cacheScheduleMatchesGc =
        defaultHome.launchd.agents.tool-cache-maintenance.config.StartCalendarInterval
        == defaultConfig.nix.gc.interval;
      cacheRunsOnActivation = defaultHome.launchd.agents.tool-cache-maintenance.config.RunAtLoad;
      storeOptimise = defaultConfig.nix.optimise.automatic;
      minFree = defaultConfig.nix.settings.min-free;
      maxFreeDeclared = builtins.hasAttr "max-free" defaultConfig.nix.settings;
    };
    expected = {
      automatic = true;
      interval = [
        {
          Weekday = 7;
          Hour = 3;
          Minute = 15;
        }
      ];
      options = "--delete-old";
      userGc = false;
      cacheMaintenance = true;
      cacheScheduleMatchesGc = true;
      cacheRunsOnActivation = false;
      storeOptimise = true;
      minFree = 10737418240;
      maxFreeDeclared = false;
    };
  };

}
