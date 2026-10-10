{ inputs }:
let
  host = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules = [ ../../../hosts/x86_64-linux/nixos ];
  };
  inherit (host) config pkgs;
in
{
  testLinuxDockerModulePreservesDaemonAndCliConfiguration = {
    expr = {
      enabled = config.virtualisation.docker.enable;
      logDriver = config.virtualisation.docker.daemon.settings."log-driver";
      logOptions = config.virtualisation.docker.daemon.settings."log-opts";
      compose = builtins.elem pkgs.docker-compose config.environment.systemPackages;
      buildx = builtins.elem pkgs.docker-buildx config.environment.systemPackages;
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

  testLinuxRunsWeeklySystemGarbageCollection = {
    expr = {
      automatic = config.nix.gc.automatic;
      dates = config.systemd.services.nix-gc.startAt;
      options = config.nix.gc.options;
    };
    expected = {
      automatic = true;
      dates = [ "weekly" ];
      options = "--delete-old";
    };
  };
}
