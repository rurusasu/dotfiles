{ config, pkgs, ... }:
{
  home.stateVersion = "24.05";

  programs = {
    git.enable = true;
    bash.enable = true;
    zsh.enable = true;
    neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
    };
    tmux.enable = true;
    vscode.enable = true;
  };

  programs.wezterm.enable = true;

  home.file.".config/wezterm/wezterm.lua".source = ../../home/config/wezterm/wezterm.lua;

  home.packages = [
    pkgs.source-han-code-jp
  ];
}
