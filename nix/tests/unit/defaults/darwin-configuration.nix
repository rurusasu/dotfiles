{ inputs, code }:
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
        code.nix.hosts.default
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
      systemHome = configuredUserConfig.users.users.ktome1995.home;
      homeManagerHome = configuredUserConfig.home-manager.users.ktome1995.home.homeDirectory;
      guestLogin = configuredUserConfig.system.defaults.loginwindow.GuestEnabled;
      showFullName = configuredUserConfig.system.defaults.loginwindow.SHOWFULLNAME;
    };
    expected = {
      primaryUser = "ktome1995";
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
      codexEnvironment = builtins.elemAt defaultHome.launchd.agents.codex-environment.config.ProgramArguments 3;
      agentEnvironment = builtins.elemAt defaultHome.launchd.agents.onepassword-ssh-environment.config.ProgramArguments 3;
      gpgSshAgentEnabled = defaultConfig.programs.gnupg.agent.enableSSHSupport;
      github = builtins.any (name: builtins.match "^(gh|github-cli)($|[-.].*)" name != null) (
        map (package: package.name) defaultHome.home.packages
      );
      managedFont = builtins.any (
        package: hasPrefix "udev-gothic-nf" (package.name or package.pname)
      ) defaultConfig.fonts.packages;
      homeManagerUser = builtins.hasAttr "rurusasu" defaultConfig.home-manager.users;
    };
    expected = {
      codexEnvironment = "/Users/rurusasu/.config/codex";
      agentEnvironment = "/Users/rurusasu/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
      gpgSshAgentEnabled = false;
      github = true;
      managedFont = true;
      homeManagerUser = true;
    };
  };

  testDarwinHomeManagerOwnsPlatformEnvironment = {
    expr = {
      onePassword = defaultHome.home.sessionVariables.OP_BIOMETRIC_UNLOCK_ENABLED;
      sharedPath = builtins.elem "${defaultHome.home.homeDirectory}/.local/bin" defaultHome.home.sessionPath;
      managedPackagesFirst =
        builtins.head defaultHome.home.sessionPath == defaultHome.home.profileDirectory + "/bin";
    };
    expected = {
      onePassword = "true";
      sharedPath = true;
      managedPackagesFirst = true;
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

  testDarwinRunsAutomaticStoreOptimisation = {
    expr = defaultConfig.nix.optimise.automatic;
    expected = true;
  };

}
