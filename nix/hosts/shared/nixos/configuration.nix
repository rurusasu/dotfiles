{ lib, pkgs, ... }:
let
  identity = import ./identity.nix { inherit lib; };
  bootstrapUser = identity.user;
  bootstrapHome = identity.home;
  uidText = identity.uid;
  gidText = identity.gid;
  groupText = identity.group;
  user = if bootstrapUser == "" then "nixos" else bootstrapUser;
  home = if bootstrapHome == "" then "/home/${user}" else bootstrapHome;
  primaryGroup = if groupText == "" then "users" else groupText;
  isNumericId = value: builtins.match "[0-9]+" value != null;
  uid = if isNumericId uidText then lib.toInt uidText else null;
  gid = if isNumericId gidText then lib.toInt gidText else null;
in
{
  imports = [
    ../../../modules/docker.nix
    ./omarchy-keybindings.nix
  ];
  assertions = [
    {
      assertion = uidText == "" || isNumericId uidText;
      message = "The host UID must be numeric when provided";
    }
    {
      assertion = gidText == "" || isNumericId gidText;
      message = "The host GID must be numeric when provided";
    }
  ];

  system.stateVersion = "25.05";

  users = {
    mutableUsers = true;
    groups.${primaryGroup} = lib.optionalAttrs (gid != null) { inherit gid; };
    users.${user} = {
      isNormalUser = true;
      # The NixOS module enables and installs zsh before user activation.
      shell = pkgs.zsh;
      inherit home;
      createHome = true;
      linger = true;
      group = primaryGroup;
      extraGroups = [
        "wheel"
        "docker"
      ];
    }
    // lib.optionalAttrs (uid != null) { inherit uid; };
  };

}
