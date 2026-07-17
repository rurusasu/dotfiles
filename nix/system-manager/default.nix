{
  lib,
  inputs,
  ...
}:
let
  user = builtins.getEnv "DOTFILES_USER";
  home = builtins.getEnv "DOTFILES_HOME";
  uidText = builtins.getEnv "DOTFILES_UID";
  gidText = builtins.getEnv "DOTFILES_GID";
  groupText = builtins.getEnv "DOTFILES_GROUP";
  primaryGroup = if groupText == "" then user else groupText;
  isNumericId = value: builtins.match "[0-9]+" value != null;
  uid = if isNumericId uidText then lib.toInt uidText else 0;
  gid = if isNumericId gidText then lib.toInt gidText else 0;
in
{
  assertions = [
    {
      assertion = user != "";
      message = "DOTFILES_USER is required";
    }
    {
      assertion = home != "" && lib.hasPrefix "/" home;
      message = "DOTFILES_HOME must be an absolute path";
    }
    {
      assertion = isNumericId uidText;
      message = "DOTFILES_UID must be a numeric existing-user UID";
    }
    {
      assertion = isNumericId gidText;
      message = "DOTFILES_GID must be a numeric existing-user GID";
    }
    {
      assertion = primaryGroup != "";
      message = "DOTFILES_GROUP or DOTFILES_USER is required";
    }
  ];

  nix.enable = true;
  services.userborn.enable = true;

  # Merge with the host account database and pin the managed identity to the
  # UID/GID discovered by the installer. This prevents account replacement.
  users = {
    mutableUsers = true;
    groups.${primaryGroup}.gid = gid;
    groups.docker = { };
    users.${user} = {
      isNormalUser = true;
      inherit uid home;
      group = primaryGroup;
      extraGroups = [ "docker" ];
    };
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    users.${user} = import ../home/common.nix;
    extraSpecialArgs = { inherit inputs; };
  };
}
