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
