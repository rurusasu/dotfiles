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

}
