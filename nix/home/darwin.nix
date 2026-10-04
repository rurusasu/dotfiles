{
  pkgs,
  lib,
  inputs,
  installFeatures ? [ ],
  ...
}:
let
  sets = import ../packages/sets.nix {
    inherit pkgs lib;
  };
in
{
  imports = [
    ../modules/nvim
    ./common.nix
    ./hermes-agent.nix
  ];

  home = {
    packages = lib.unique (
      (sets.darwinHomePackagesForInstallFeatures installFeatures)
      ++ [
        pkgs.coreutils
      ]
    );

    sessionVariables = {
      # Homebrew's default is already 24 hours; keep that interval explicit
      # for interactive shells and tools launched from the Home Manager session.
      HOMEBREW_AUTO_UPDATE_SECS = "86400";
      # Let native op use the unlocked 1Password desktop app integration.
      OP_BIOMETRIC_UNLOCK_ENABLED = "true";
    };

    sessionPath = [
      "/opt/homebrew/bin"
      "/opt/homebrew/sbin"
    ];
  };

  programs.zsh.shellAliases = {
    nrs = "~/.dotfiles/install.sh";
  };
}
