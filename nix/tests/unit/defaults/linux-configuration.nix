{
  inputs,
  code,
  homeConfigurations,
}:
let
  inherit
    (inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        platform = "linux";
      };
      modules = [ code.nix.hosts.default ];
    })
    config
    pkgs
    ;
in
{
  testNativeLinuxUsesStableLix = {
    expr = config.nix.package == pkgs.lixPackageSets.stable.lix;
    expected = true;
  };

  testNativeLinuxOnePasswordCliHasDesktopIntegrationPermissions = {
    expr = {
      enabled = config.programs._1password.enable;
      group = config.security.wrappers.op.group or null;
      setgid = config.security.wrappers.op.setgid or false;
      privateTmp = config.home-manager.users.nixos.systemd.user.services.hermes-agent.Service.PrivateTmp;
      noNewPrivileges =
        config.home-manager.users.nixos.systemd.user.services.hermes-agent.Service.NoNewPrivileges;
      hermesBinary =
        config.home-manager.users.nixos.services.hermes-agent.settings.secrets.onepassword.binary_path
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

  testNativeLinuxRegistersDconfForGtkSettingsPersistence = {
    expr = config.programs.dconf.enable;
    expected = true;
  };
  testNativeLinuxDoesNotInstallWslgFontBridge = {
    expr = config.system.activationScripts ? wslgFonts;
    expected = false;
  };
  testLinuxEnablesPodmanAndItsUserApi = {
    expr = {
      enabled = config.virtualisation.podman.enable;
      dockerCompat = config.virtualisation.podman.dockerCompat;
      userRuntime = config.home-manager.users.nixos.services.podman.enable;
      userSocket = config.systemd.user.sockets.podman.wantedBy;
      homeSocket = config.home-manager.users.nixos.systemd.user.sockets ? podman;
      standaloneSocket = homeConfigurations.linux.config.systemd.user.sockets.podman.Socket.ListenStream;
      manager = config.home-manager.users.nixos.programs.lazydocker.enable;
    };
    expected = {
      enabled = true;
      dockerCompat = true;
      userRuntime = true;
      userSocket = [ "sockets.target" ];
      homeSocket = false;
      standaloneSocket = "%t/podman/podman.sock";
      manager = true;
    };
  };

  testLinuxConfiguresZshAndUsesOnePasswordAgent = {
    expr = {
      enabled = config.programs.zsh.enable;
      selected = config.users.users.nixos.shell == pkgs.zsh;
      installed = builtins.elem pkgs.zsh config.environment.systemPackages;
      opensshAgentStarted = config.programs.ssh.startAgent;
      gpgSshAgentEnabled = config.programs.gnupg.agent.enableSSHSupport;
    };
    expected = {
      enabled = true;
      selected = true;
      installed = true;
      opensshAgentStarted = false;
      gpgSshAgentEnabled = false;
    };
  };
}
