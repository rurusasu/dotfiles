{
  config,
  inputs,
  lib,
  ...
}:
let
  user = config.system.primaryUser;
  home = config.home-manager.users.${user};
  systemProfile = lib.escapeShellArg config.system.profile;
  currentHome = lib.escapeShellArg "${home.xdg.stateHome}/home-manager/gcroots/current-home";
  homeGeneration = lib.escapeShellArg (toString home.home.activationPackage);
in
{
  imports = [
    ../../modules/1password/darwin.nix
    ../../modules/fonts/darwin.nix
    ../../modules/google-drive
    ../../modules/ssh/darwin.nix
    ../../modules/tailscale/darwin.nix
    inputs.home-manager.darwinModules.home-manager
  ];
  system = {
    primaryUser = lib.mkDefault (import ../../home/settings.nix).username;
    # Apply to battery and AC power together; systemsetup does not select a power source.
    activationScripts.power.text = ''
      /usr/bin/pmset -a sleep 0 displaysleep 0
    '';
    # Run after Home Manager and the other post-activation hooks.
    activationScripts.postActivation.text = lib.mkOrder 2000 ''
      if [[ ! -v DRY_RUN && ''${#hmDryRunArgs[@]} -eq 0 ]] \
        && [[ "$(readlink -f ${systemProfile})" == "$(readlink -f "$systemConfig")" ]] \
        && [[ "$(readlink -f ${currentHome})" == ${homeGeneration} ]]; then
        ${lib.getExe' config.nix.package "nix-env"} --profile ${systemProfile} --delete-generations old
      fi
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
      # Prune the system profile after activation, not during scheduled GC.
      options = "";
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
