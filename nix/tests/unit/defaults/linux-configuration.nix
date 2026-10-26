{ inputs }:
let
  inherit
    (inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        platform = "linux";
      };
      modules = [ (import ../../../defaults.nix inputs).systemDefaults ];
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
  testLinuxDockerModulePreservesDaemonAndCliConfiguration = {
    expr = {
      enabled = config.virtualisation.docker.enable;
      logDriver = config.virtualisation.docker.daemon.settings."log-driver";
      logOptions = config.virtualisation.docker.daemon.settings."log-opts";
      compose = builtins.elem pkgs.docker-compose config.virtualisation.docker.package.buildInputs;
      buildx = builtins.elem pkgs.docker-buildx config.virtualisation.docker.package.buildInputs;
      userGroup = builtins.elem "docker" config.users.users.nixos.extraGroups;
      insecureRegistries = config.virtualisation.docker.daemon.settings.insecure-registries or [ ];
    };
    expected = {
      enabled = true;
      logDriver = "json-file";
      logOptions = {
        "max-size" = "10m";
        "max-file" = "3";
      };
      compose = true;
      buildx = true;
      userGroup = true;
      insecureRegistries = [ ];
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
