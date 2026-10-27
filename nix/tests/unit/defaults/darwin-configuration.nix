{ inputs }:
let
  mkDarwin =
    primaryUser: extraModules:
    inputs.nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = {
        inherit inputs;
        platform = "darwin";
      };
      modules = [
        {
          nixpkgs.config.allowUnfree = true;
          system.primaryUser = primaryUser;
        }
        (import ../../../defaults.nix inputs).systemDefaults
      ]
      ++ extraModules;
    };

  defaultSystem = mkDarwin "rurusasu" [ ];
  defaultConfig = defaultSystem.config;
  configuredUserConfig = (mkDarwin "ktome1995" [ ]).config;
  defaultHome = defaultConfig.home-manager.users.rurusasu;
  nonstandardHomeConfig =
    (mkDarwin "alice" [
      { users.users.alice.home = inputs.nixpkgs.lib.mkForce "/Volumes/Home/alice"; }
    ]).config;

  hasDarwinCask = name: config: builtins.any (cask: cask.name == name) config.homebrew.casks;
  packageNames =
    config: builtins.map (package: package.name or package.pname) config.environment.systemPackages;
  hasPrefix = prefix: value: builtins.match "${prefix}.*" value != null;
in
{
  testDarwinUsesStableLix = {
    expr = defaultConfig.nix.package == defaultSystem.pkgs.lixPackageSets.stable.lix;
    expected = true;
  };

  testDarwinInstallsUninstaller = {
    expr = {
      enabled = defaultConfig.system.tools.darwin-uninstaller.enable;
      installed = builtins.any (
        package: (package.pname or package.name) == "darwin-uninstaller"
      ) defaultConfig.environment.systemPackages;
    };
    expected = {
      enabled = true;
      installed = true;
    };
  };

  testDarwinDockPinsManagedApplicationsInOrder = {
    expr = {
      applications = defaultHome.targets.darwin.defaults."com.apple.dock".persistent-apps;
      others = defaultHome.targets.darwin.defaults."com.apple.dock".persistent-others;
      recents = defaultHome.targets.darwin.defaults."com.apple.dock".show-recents;
    };
    expected = {
      applications =
        map
          (path: {
            tile-data.file-data = {
              _CFURLString = path;
              _CFURLStringType = 0;
            };
          })
          [
            "${defaultHome.programs.chatgpt.package}/Applications/ChatGPT.app"
            "${
              import ../../../modules/browsers/dia {
                inherit inputs;
                inherit (defaultSystem) pkgs;
              }
            }/Applications/Dia.app"
            "${defaultHome.programs.ghostty.package}/Applications/Ghostty.app"
            "${defaultSystem.pkgs.obsidian}/Applications/Obsidian.app"
          ];
      others = [ ];
      recents = false;
    };
  };

  testDarwinDockPinsAreIndependentOfTheConfiguredHome = {
    expr =
      nonstandardHomeConfig.home-manager.users.alice.targets.darwin.defaults."com.apple.dock".persistent-apps;
    expected = defaultHome.targets.darwin.defaults."com.apple.dock".persistent-apps;
  };

  testDarwinDoesNotInstallWslgFontBridge = {
    expr = defaultConfig.system.activationScripts ? wslgFonts;
    expected = false;
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
      primaryUser = configuredUserConfig.system.primaryUser;
      homebrewUser = configuredUserConfig.nix-homebrew.user;
      systemHome = configuredUserConfig.users.users.ktome1995.home;
      homeManagerHome = configuredUserConfig.home-manager.users.ktome1995.home.homeDirectory;
      guestLogin = configuredUserConfig.system.defaults.loginwindow.GuestEnabled;
      showFullName = configuredUserConfig.system.defaults.loginwindow.SHOWFULLNAME;
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
      agentEnvironment = builtins.elemAt defaultHome.launchd.agents.onepassword-ssh-environment.config.ProgramArguments 3;
      gpgSshAgentEnabled = defaultConfig.programs.gnupg.agent.enableSSHSupport;
      homebrew = defaultConfig.homebrew.enable;
      nixHomebrew = defaultConfig.nix-homebrew.enable;
      wezterm = defaultHome.programs.wezterm.enable;
      github = builtins.any (name: builtins.match "^(gh|github-cli)($|[-.].*)" name != null) (
        packageNames defaultConfig
      );
      managedFont = builtins.any (
        package: hasPrefix "udev-gothic-nf" (package.name or package.pname)
      ) defaultConfig.fonts.packages;
      homeManagerUser = builtins.hasAttr "rurusasu" defaultConfig.home-manager.users;
    };
    expected = {
      agentEnvironment = "/Users/rurusasu/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
      gpgSshAgentEnabled = false;
      homebrew = true;
      nixHomebrew = true;
      wezterm = true;
      github = true;
      managedFont = true;
      homeManagerUser = true;
    };
  };

  testDarwinConfigurationKeepsDefaultCaskBoundary = {
    expr = {
      casks = map (cask: cask.name) defaultConfig.homebrew.casks;
      chrome = hasDarwinCask "google-chrome" defaultConfig;
      docker = hasDarwinCask "docker-desktop" defaultConfig;
    };
    expected = {
      casks = [
        "docker-desktop"
        "steam"
      ];
      chrome = false;
      docker = true;
    };
  };

  testDarwinConfigurationIncludesSteamCask = {
    expr = hasDarwinCask "steam" defaultConfig;
    expected = true;
  };

  testDarwinDockerInitializationUsesConfiguredIdentityAndHome = {
    expr = {
      configuredUser = inputs.nixpkgs.lib.hasInfix "--user=${inputs.nixpkgs.lib.escapeShellArg "ktome1995"}" configuredUserConfig.system.activationScripts.postActivation.text;
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
      inputs.nixpkgs.lib.hasInfix "--accept-license"
        (mkDarwin "rurusasu" [
          { homebrew.casks = inputs.nixpkgs.lib.mkForce [ ]; }
        ]).config.system.activationScripts.postActivation.text;
    expected = false;
  };

  testDarwinHomeManagerOwnsPlatformEnvironment = {
    expr = {
      autoUpdate = defaultHome.home.sessionVariables.HOMEBREW_AUTO_UPDATE_SECS;
      onePassword = defaultHome.home.sessionVariables.OP_BIOMETRIC_UNLOCK_ENABLED;
      homebrewPath = builtins.elem "/opt/homebrew/bin" defaultHome.home.sessionPath;
      sharedPath = builtins.elem "$HOME/.local/bin" defaultHome.home.sessionPath;
      pathOrder = defaultHome.home.sessionPath;
    };
    expected = {
      autoUpdate = "86400";
      onePassword = "true";
      homebrewPath = true;
      sharedPath = true;
      pathOrder = [
        "$HOME/.bun/bin"
        "$HOME/.local/bin"
        "$HOME/bin"
        "$HOME/.local/npm/bin"
        "/opt/homebrew/bin"
        "/opt/homebrew/sbin"
      ];
    };
  };

  testDarwinHomeManagerConfiguresDefaultFonts = {
    expr = {
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
      fontconfig = true;
      defaultFonts = {
        monospace = [ "UDEV Gothic NF" ];
        sansSerif = [ "UDEV Gothic NF" ];
        serif = [ "UDEV Gothic NF" ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
  };

  testDarwinDesktopPackagesAndDiscordAgent = {
    expr = {
      chromeSystemPackage = builtins.any (name: hasPrefix "google-chrome" name) (
        packageNames defaultConfig
      );
      discordHomePackage = builtins.any (name: hasPrefix "discord" name) (
        (home: builtins.map (package: package.name or package.pname) home.home.packages) defaultHome
      );
      discordAgent = builtins.hasAttr "discord-module-staging" defaultHome.launchd.agents;
    };
    expected = {
      chromeSystemPackage = false;
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

  testDarwinRunsAutomaticStoreOptimisation = {
    expr = defaultConfig.nix.optimise.automatic;
    expected = true;
  };

}
