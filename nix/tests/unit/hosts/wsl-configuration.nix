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
