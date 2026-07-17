{ lib, pkgs, ... }:
let
  bootstrapUser = builtins.getEnv "DOTFILES_USER";
  bootstrapHome = builtins.getEnv "DOTFILES_HOME";
  uidText = builtins.getEnv "DOTFILES_UID";
  gidText = builtins.getEnv "DOTFILES_GID";
  groupText = builtins.getEnv "DOTFILES_GROUP";
  user = if bootstrapUser == "" then "nixos" else bootstrapUser;
  home = if bootstrapHome == "" then "/home/${user}" else bootstrapHome;
  primaryGroup = if groupText == "" then "users" else groupText;
  isNumericId = value: builtins.match "[0-9]+" value != null;
  uid = if isNumericId uidText then lib.toInt uidText else null;
  gid = if isNumericId gidText then lib.toInt gidText else null;
in
{
  assertions = [
    {
      assertion = uidText == "" || isNumericId uidText;
      message = "DOTFILES_UID must be numeric when provided";
    }
    {
      assertion = gidText == "" || isNumericId gidText;
      message = "DOTFILES_GID must be numeric when provided";
    }
  ];

  system.stateVersion = "25.05";

  users = {
    mutableUsers = true;
    groups.${primaryGroup} = lib.optionalAttrs (gid != null) { inherit gid; };
    users.${user} = {
      isNormalUser = true;
      inherit home;
      createHome = true;
      group = primaryGroup;
      extraGroups = [
        "wheel"
        "docker"
      ];
    }
    // lib.optionalAttrs (uid != null) { inherit uid; };
  };

  environment.systemPackages = with pkgs; [
    docker-compose
    docker-buildx
  ];

  virtualisation.docker.enable = true;
  virtualisation.docker.daemon.settings = {
    "log-driver" = "json-file";
    "log-opts" = {
      "max-size" = "10m";
      "max-file" = "3";
    };
  };
}
