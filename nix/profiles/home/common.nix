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
  home.file.".claude/settings.json".source = ../../../claude/settings.json;
  home.file.".codex/config.toml".source = ../../../codex/config.toml;

  home.packages = [
    pkgs.claude-code
    pkgs.codex
    pkgs.source-han-code-jp
  ];
}
