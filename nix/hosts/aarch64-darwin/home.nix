{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  sets = import ../../packages/sets.nix {
    inherit pkgs lib;
  };
  inherit ((import ../../modules/fonts.nix { inherit pkgs; })) fonts;
in
{
  imports = [
    ../../modules/editors/nvim
    ../../modules/discord
    ../../home/common.nix
  ];

  home = {
    # System integration supplies the host home with higher priority.
    homeDirectory = lib.mkDefault "/Users/${config.home.username}";

    packages = lib.unique (
      sets.darwinHomePackages
      ++ [
        pkgs.coreutils
      ]
      # nix-darwin installs system fonts; standalone uses Home Manager's
      # native Darwin font copying from home.packages.
      ++ lib.optionals (!config.submoduleSupport.enable) fonts.packages
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

  fonts.fontconfig = fonts.fontconfig;

  programs.git.signing.signer = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";

  programs.zsh.shellAliases = {
    nrs = "~/.dotfiles/install.sh";
  };
}
