{
  config,
  inputs,
  lib,
  ...
}:
let
  user = config.system.primaryUser;
in
{
  imports = [
    ../../modules/fonts/darwin.nix
    ../../modules/google-drive
    inputs.home-manager.darwinModules.home-manager
  ];
  system = {
    primaryUser = lib.mkDefault (import ../../home/settings.nix).username;
    # Apply to battery and AC power together; systemsetup does not select a power source.
    activationScripts.power.text = ''
      /usr/bin/pmset -a sleep 0 displaysleep 0
    '';
    stateVersion = inputs.self.lib.stateVersions.darwin;
    defaults.loginwindow = {
      GuestEnabled = false;
      SHOWFULLNAME = false;
    };
  };
  nix = {
    optimise.automatic = true;
    gc = {
      interval = [
        {
          Hour = 3;
          Minute = 15;
        }
      ];
    };
  };
  # The locked nixos-render-docs rejects nix-darwin's manual flags.
  documentation.enable = false;
  users.users.${user}.home = "/Users/${user}";
  home-manager.users.${user} = { };
}
