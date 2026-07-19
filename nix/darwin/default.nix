{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  user = builtins.getEnv "DOTFILES_USER";
  home = builtins.getEnv "DOTFILES_HOME";
  sets = import ../packages/sets.nix {
    inherit pkgs lib;
  };
in
{
  assertions = [
    {
      assertion = user != "";
      message = "DOTFILES_USER is required";
    }
    {
      assertion = home != "";
      message = "DOTFILES_HOME is required";
    }
  ];

  system = {
    primaryUser = user;
    stateVersion = 6;
    tools.darwin-uninstaller.enable = false;
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # nix-darwin's generated documentation currently passes a removed
  # nixos-render-docs flag. Omit the optional manual artifacts and the
  # uninstaller's nested default system, which otherwise rebuilds them.
  documentation.enable = false;

  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    inherit user;
    autoMigrate = true;
  };

  homebrew = {
    enable = true;
    casks = sets.darwinCasks;
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };
  };

  users.users.${user}.home = home;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    users.${user} =
      { ... }:
      {
        imports = [ ../home/common.nix ];

        programs.zsh.shellAliases = {
          nrs = "nix_bin=$(command -v nix) && sudo /usr/bin/env \"NIX_CONFIG=extra-experimental-features = nix-command flakes\" \"DOTFILES_USER=$USER\" \"DOTFILES_HOME=$HOME\" \"$nix_bin\" run ~/.dotfiles#darwin-rebuild -- switch --flake ~/.dotfiles#macos --impure";
        };
      };
    extraSpecialArgs = { inherit inputs; };
  };
}
