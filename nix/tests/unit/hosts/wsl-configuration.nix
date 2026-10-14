{ inputs }:
let
  mkWsl = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
    };
    modules = [
      inputs.nixos-wsl.nixosModules.wsl
      ../../../hosts/shared/nixos/platform.nix
      ../../../hosts/x86_64-linux/wsl
    ];
  };

  defaultConfig = mkWsl.config;
in
{
  testWslgFontBridgeCopiesPrimaryAndFallbackFontsWithoutRestartingApplications = {
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
        ${mkWsl.pkgs.coreutils}/bin/install --compare -m 0644 ${mkWsl.pkgs.noto-fonts-cjk-sans}/share/fonts/opentype/noto-cjk/NotoSansCJK-VF.otf.ttc /usr/local/share/fonts/dotfiles-wslg/NotoSansCJK-VF.otf.ttc
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
        path = ../../../hosts/x86_64-linux/wsl/fonts/fontconfig.conf;
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
      sessionAtLogin = builtins.elem "default.target" (
        defaultConfig.systemd.user.targets.graphical-session.wantedBy or [ ]
      );
      sessionOnSwitch = builtins.elem "graphical-session.target" (
        defaultConfig.systemd.user.services.nixos-activation.wants or [ ]
      );
      activationAfterSession = builtins.elem "graphical-session.target" (
        defaultConfig.systemd.user.services.nixos-activation.after or [ ]
      );
      displayEnvironment =
        builtins.all
          (
            value:
            inputs.nixpkgs.lib.hasInfix value
              defaultConfig.environment.etc."environment.d/60-wsl-graphics.conf".text
          )
          [
            "DISPLAY=:0\n"
            "WAYLAND_DISPLAY=wayland-0\n"
          ];
      portal = defaultConfig.xdg.portal.enable;
    };
    expected = {
      sessionAtLogin = true;
      sessionOnSwitch = true;
      activationAfterSession = true;
      displayEnvironment = true;
      portal = true;
    };
  };

  testWslUsesWindowsGpuForOpenGL = {
    expr = {
      graphics = defaultConfig.hardware.graphics.enable;
      windowsDriver = defaultConfig.wsl.useWindowsDriver;
      driverLibraries = builtins.elem defaultConfig.wsl.wslLib defaultConfig.hardware.graphics.extraPackages;
      galliumDriver = defaultConfig.environment.variables.GALLIUM_DRIVER or null;
      libraryPath = defaultConfig.environment.variables.LD_LIBRARY_PATH or null;
      serviceEnvironment =
        defaultConfig.environment.etc."environment.d/60-wsl-graphics.conf".text or null;
    };
    expected = {
      graphics = true;
      windowsDriver = true;
      driverLibraries = true;
      galliumDriver = "d3d12";
      libraryPath = "/run/opengl-driver/lib";
      serviceEnvironment = "DISPLAY=:0\nGALLIUM_DRIVER=d3d12\nLD_LIBRARY_PATH=/run/opengl-driver/lib\nWAYLAND_DISPLAY=wayland-0\n";
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
