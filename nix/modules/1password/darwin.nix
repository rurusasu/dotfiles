{
  config,
  lib,
  pkgs,
  ...
}:
let
  home = config.home-manager.users.${config.system.primaryUser};
  cfg = home.dotfiles.onePassword;
in
{
  config = lib.mkIf cfg.enable {
    # Home Manager runs as the login user, who cannot replace root-owned bundles.
    # Install before its activation so it only has to register the application.
    system.activationScripts.postActivation.text = lib.mkBefore ''
      onepasswordApp=${lib.escapeShellArg cfg.darwinAppPath}
      if [[ -L "$onepasswordApp" ]]; then
        /bin/rm "$onepasswordApp"
      fi
      /bin/mkdir -p "$onepasswordApp"
      # Preserve vendor signatures without Nix's epoch timestamps, like copyApps.
      ${lib.getExe pkgs.rsync} --recursive --checksum --perms --links \
        --copy-unsafe-links --specials --delete --chmod=+w \
        ${pkgs._1password-gui}/Applications/1Password.app/ "$onepasswordApp/"
      /usr/bin/codesign --verify --deep --strict \
        --test-requirement='=identifier "com.1password.1password" and anchor apple generic and certificate leaf[subject.OU] = "2BUA8C4S2C"' \
        "$onepasswordApp"
    '';
  };
}
