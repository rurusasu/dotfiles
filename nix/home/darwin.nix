{ ... }:
{
  imports = [ ./common.nix ];

  programs.zsh.shellAliases = {
    nrs = "~/.dotfiles/install.sh";
  };
}
