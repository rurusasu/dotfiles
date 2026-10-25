args@{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  nativeIdentity = args.nativeIdentity or null;
  identity =
    if nativeIdentity == null then import ./identity.nix { inherit lib; } else nativeIdentity;
  user = if identity.user == "" then "nixos" else identity.user;
  primaryGroup = if identity.group == "" then "users" else identity.group;
  isNumericId = value: builtins.match "[0-9]+" value != null;
  uid = if isNumericId identity.uid then lib.toInt identity.uid else null;
  gid = if isNumericId identity.gid then lib.toInt identity.gid else null;
in
{
  imports = [
    ../modules/fonts.nix
    ../modules/docker.nix
    inputs.home-manager.nixosModules.home-manager
  ];

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      extra-substituters = [ "https://cache.numtide.com" ];
      extra-trusted-public-keys = [
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      ];
    };
  };
  nixpkgs.config.allowUnfree = true;
  # Home Manager connects SSH clients to the 1Password desktop agent.
  programs = {
    ssh.startAgent = false;
    gnupg.agent.enableSSHSupport = false;
    zsh = {
      enable = true;
      # Home Manager の zsh-autocomplete に補完初期化を任せる。
      enableGlobalCompInit = false;
    };
  };
  fonts.fontDir.enable = true;
  system.stateVersion = "26.05";

  assertions = [
    {
      assertion = identity.uid == "" || isNumericId identity.uid;
      message = "The host UID must be numeric when provided";
    }
    {
      assertion = identity.gid == "" || isNumericId identity.gid;
      message = "The host GID must be numeric when provided";
    }
  ];

  users = {
    mutableUsers = true;
    groups.${primaryGroup} = lib.optionalAttrs (gid != null) { inherit gid; };
    users.${user} = {
      isNormalUser = true;
      # NixOS installs zsh before Home Manager activates the account.
      shell = pkgs.zsh;
      home = if identity.home == "" then "/home/${user}" else identity.home;
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
