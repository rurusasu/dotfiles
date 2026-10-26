{ inputs }:
let
  mkWsl = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
      platform = "wsl";
    };
    modules = [
      (import ../../../defaults.nix inputs).systemDefaults
    ];
  };

  defaultConfig = mkWsl.config;
  home = (import ../../fixtures/home-configurations.nix { inherit inputs; }).wsl;
in
{
  testWslUsesTheDeclaredDefaultUserWithoutBootstrapMetadata = {
    expr =
      let
        inherit
          (mkWsl.extendModules {
            modules = [ { wsl.defaultUser = "alice"; } ];
          })
          config
          ;
      in
      {
        user = config.wsl.defaultUser;
        uid = config.users.users.alice.uid;
        home = config.users.users.alice.home;
        homeManagerUser = config.home-manager.users.alice.home.username;
        homeManagerHome = config.home-manager.users.alice.home.homeDirectory;
        persistedIdentity = config.system.activationScripts ? dotfilesHostState;
        trustedCheckouts = builtins.concatMap (
          gitConfig: gitConfig.safe.directory or [ ]
        ) config.programs.git.config;
      };
    expected = {
      user = "alice";
      uid = 1000;
      home = "/home/alice";
      homeManagerUser = "alice";
      homeManagerHome = "/home/alice";
      persistedIdentity = false;
      trustedCheckouts = [ "/home/alice/.dotfiles" ];
    };
  };

  testWslUsesStableLix = {
    expr = defaultConfig.nix.package == mkWsl.pkgs.lixPackageSets.stable.lix;
    expected = true;
  };

  testWslOnePasswordCliHasDesktopIntegrationPermissions = {
    expr = {
      enabled = defaultConfig.programs._1password.enable;
      group = defaultConfig.security.wrappers.op.group or null;
      setgid = defaultConfig.security.wrappers.op.setgid or false;
      privateTmp =
        defaultConfig.home-manager.users.nixos.systemd.user.services.hermes-agent.Service.PrivateTmp;
      noNewPrivileges =
        defaultConfig.home-manager.users.nixos.systemd.user.services.hermes-agent.Service.NoNewPrivileges;
      hermesBinary =
        defaultConfig.home-manager.users.nixos.services.hermes-agent.settings.secrets.onepassword.binary_path
          or null;
    };
    expected = {
      enabled = true;
      group = "onepassword-cli";
      setgid = true;
      privateTmp = false;
      noNewPrivileges = false;
      hermesBinary = "/run/wrappers/bin/op";
    };
  };

  testWslOnePasswordPermissionsFollowEnabledHermesServices = {
    expr =
      map
        (
          settings:
          let
            inherit
              (mkWsl.extendModules {
                modules = [
                  { home-manager.users.nixos.services.hermes-agent = inputs.nixpkgs.lib.mkForce settings; }
                ];
              })
              config
              ;
            services = config.home-manager.users.nixos.systemd.user.services;
          in
          {
            gatewayExists = services ? hermes-agent;
            backendExists = services ? hermes-backend;
            backendNoNewPrivileges = services.hermes-backend.Service.NoNewPrivileges or null;
            backendPrivateTmp = services.hermes-backend.Service.PrivateTmp or null;
          }
        )
        [
          {
            gateway.enable = false;
            backend.mode = "serve";
          }
          { enable = false; }
        ];
    expected = [
      {
        gatewayExists = false;
        backendExists = true;
        backendNoNewPrivileges = false;
        backendPrivateTmp = false;
      }
      {
        gatewayExists = false;
        backendExists = false;
        backendNoNewPrivileges = null;
        backendPrivateTmp = null;
      }
    ];
  };

  testWslRegistersDconfForGtkSettingsPersistence = {
    expr = defaultConfig.programs.dconf.enable;
    expected = true;
  };
  testWslgFontBridgeCopiesUdevAndEmojiAndRetiresNoto = {
    expr =
      let
        activation = defaultConfig.system.activationScripts.wslgFonts or { };
      in
      {
        deps = activation.deps or [ ];
        text = activation.text or "";
      };
    expected = {
      deps = [ "specialfs" ];
      text = ''
        ${mkWsl.pkgs.coreutils}/bin/install -d -m 0755 /usr/local/share/fonts/dotfiles-wslg
        # Retire the Noto CJK file previously distributed by this module.
        ${mkWsl.pkgs.coreutils}/bin/rm -f -- /usr/local/share/fonts/dotfiles-wslg/NotoSansCJK-VF.otf.ttc
        ${mkWsl.pkgs.coreutils}/bin/install --compare -m 0644 ${mkWsl.pkgs.udev-gothic-nf}/share/fonts/truetype/UDEVGothicNF-Regular.ttf /usr/local/share/fonts/dotfiles-wslg/UDEVGothicNF-Regular.ttf
        ${mkWsl.pkgs.coreutils}/bin/install --compare -m 0644 ${mkWsl.pkgs.udev-gothic-nf}/share/fonts/truetype/UDEVGothicNF-Bold.ttf /usr/local/share/fonts/dotfiles-wslg/UDEVGothicNF-Bold.ttf
        ${mkWsl.pkgs.coreutils}/bin/install --compare -m 0644 ${mkWsl.pkgs.noto-fonts-color-emoji}/share/fonts/noto/NotoColorEmoji.ttf /usr/local/share/fonts/dotfiles-wslg/NotoColorEmoji.ttf
      '';
    };
  };
  testWslgServerFontconfigPrependsUdevAndPreservesFallbacks = {
    expr =
      let
        inherit (inputs.nixpkgs) lib;
        path = ../../../modules/fonts/wsl-fontconfig.conf;
        xml = if builtins.pathExists path then builtins.readFile path else "";
        systemInclude = "<include>/etc/fonts/fonts.conf</include>";
        pieces = lib.splitString systemInclude xml;
      in
      {
        includesSystemDefaults = lib.hasInfix systemInclude xml;
        systemDefaultsBeforeOverride =
          builtins.length pieces == 2 && lib.hasInfix "<match target=\"pattern\">" (builtins.elemAt pieces 1);
        targetsNormalizedSans = builtins.all (token: lib.hasInfix token xml) [
          "<test name=\"family\">"
          "<string>sans-serif</string>"
        ];
        prependsPrimaryFamily = builtins.all (token: lib.hasInfix token xml) [
          "<edit name=\"family\" mode=\"prepend_first\" binding=\"strong\">"
          "<string>UDEV Gothic NF</string>"
        ];
        editCount = builtins.length (lib.splitString "<edit " xml) - 1;
        hasStorePaths = lib.hasInfix "/nix/store/" xml;
      };
    expected = {
      includesSystemDefaults = true;
      systemDefaultsBeforeOverride = true;
      targetsNormalizedSans = true;
      prependsPrimaryFamily = true;
      editCount = 1;
      hasStorePaths = false;
    };
  };
  testWslGeneratesJapaneseLocaleWithoutChangingDefaultOrInputMethod = {
    expr = {
      defaultLocale = defaultConfig.i18n.defaultLocale;
      japanese = builtins.elem "ja_JP.UTF-8/UTF-8" defaultConfig.i18n.extraLocales;
      inputMethod = defaultConfig.i18n.inputMethod.enable;
    };
    expected = {
      defaultLocale = "en_US.UTF-8";
      japanese = true;
      inputMethod = false;
    };
  };
  testWslStartsGraphicalSessionForPortals = {
    expr = {
      sessionAtLogin = builtins.elem "default.target" defaultConfig.systemd.user.services.nixos-activation.wantedBy;
      customHomeTarget = home.config.systemd.user.targets ? graphical-session;
      customSystemTarget = defaultConfig.systemd.user.targets ? graphical-session;
      standardTarget =
        inputs.nixpkgs.lib.hasInfix "graphical-session.target"
          defaultConfig.environment.etc."systemd/user".source.buildCommand;
      sessionOnSwitch = builtins.elem "graphical-session.target" (
        defaultConfig.systemd.user.services.nixos-activation.wants or [ ]
      );
      activationAfterSession = builtins.elem "graphical-session.target" (
        defaultConfig.systemd.user.services.nixos-activation.after or [ ]
      );
      displayEnvironment = {
        inherit (home.config.systemd.user.sessionVariables) DISPLAY WAYLAND_DISPLAY;
      };
      portal = defaultConfig.xdg.portal.enable;
    };
    expected = {
      sessionAtLogin = true;
      customHomeTarget = false;
      customSystemTarget = false;
      standardTarget = true;
      sessionOnSwitch = true;
      activationAfterSession = true;
      displayEnvironment = {
        DISPLAY = ":0";
        WAYLAND_DISPLAY = "wayland-0";
      };
      portal = true;
    };
  };

  testWslUsesWindowsGpuForOpenGL = {
    expr = {
      graphics = defaultConfig.hardware.graphics.enable;
      windowsDriver = defaultConfig.wsl.useWindowsDriver;
      driverLibraries = builtins.elem defaultConfig.wsl.wslLib defaultConfig.hardware.graphics.extraPackages;
      galliumDriver = home.config.home.sessionVariables.GALLIUM_DRIVER or null;
      libraryPath = home.config.home.sessionVariables.LD_LIBRARY_PATH or null;
      wayland = home.config.home.sessionVariables.WARP_ENABLE_WAYLAND or null;
      serviceEnvironment = {
        inherit (home.config.systemd.user.sessionVariables)
          GALLIUM_DRIVER
          LD_LIBRARY_PATH
          WARP_ENABLE_WAYLAND
          ;
      };
    };
    expected = {
      graphics = true;
      windowsDriver = true;
      driverLibraries = true;
      galliumDriver = "d3d12";
      libraryPath = "/run/opengl-driver/lib";
      wayland = "1";
      serviceEnvironment = {
        GALLIUM_DRIVER = "d3d12";
        LD_LIBRARY_PATH = "/run/opengl-driver/lib";
        WARP_ENABLE_WAYLAND = "1";
      };
    };
  };

  testWslDockerModulePreservesNativeDaemonAndRegistry = {
    expr = {
      enabled = defaultConfig.virtualisation.docker.enable;
      insecureRegistries = defaultConfig.virtualisation.docker.daemon.settings.insecure-registries;
      logDriver = defaultConfig.virtualisation.docker.daemon.settings."log-driver" or null;
      userGroup = builtins.elem "docker" defaultConfig.users.users.nixos.extraGroups;
    };
    expected = {
      enabled = true;
      insecureRegistries = [ "registry.localhost" ];
      logDriver = "journald";
      userGroup = true;
    };
  };

  testWslOwnsExactCheckoutTrustInSystemGit = {
    expr = {
      enabled = defaultConfig.programs.git.enable;
      directories = builtins.concatMap (
        gitConfig: gitConfig.safe.directory or [ ]
      ) defaultConfig.programs.git.config;
    };
    expected = {
      enabled = true;
      directories = [ "/home/nixos/.dotfiles" ];
    };
  };

  testWslConfiguresZshAndUsesOnePasswordAgent = {
    expr = {
      enabled = defaultConfig.programs.zsh.enable;
      selected = defaultConfig.users.users.nixos.shell == mkWsl.pkgs.zsh;
      installed = builtins.elem mkWsl.pkgs.zsh defaultConfig.environment.systemPackages;
      opensshAgentStarted = defaultConfig.programs.ssh.startAgent;
      gpgSshAgentEnabled = defaultConfig.programs.gnupg.agent.enableSSHSupport;
    };
    expected = {
      enabled = true;
      selected = true;
      installed = true;
      opensshAgentStarted = false;
      gpgSshAgentEnabled = false;
    };
  };

  testWslHermesEnablesUserLinger = {
    expr = defaultConfig.users.users.nixos.linger;
    expected = true;
  };
  testWslUsesNativeInteropWithoutDockerDesktop = {
    expr = {
      registerInterop = defaultConfig.wsl.interop.register;
      registrations = builtins.attrNames defaultConfig.boot.binfmt.registrations;
      dockerDesktop = defaultConfig.wsl.docker-desktop.enable;
    };
    expected = {
      registerInterop = false;
      registrations = [ ];
      dockerDesktop = false;
    };
  };

}
