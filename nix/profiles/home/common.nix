{ config, pkgs, ... }:
{
  home.stateVersion = "24.05";

  programs = {
    git.enable = true;
    zsh.enable = true;
    nixvim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
    };
    tmux.enable = true;
    vscode.enable = true;
  };

  programs.wezterm.enable = true;

  home.file.".bashrc".source = ../../home/config/bash/.bashrc;
  home.file.".profile".source = ../../home/config/bash/.profile;
  home.file.".bash_logout".source = ../../home/config/bash/.bash_logout;

  home.file.".config/wezterm/wezterm.lua".source = ../../home/config/wezterm/wezterm.lua;
  home.file.".claude/settings.json".source = ../../../claude/settings.json;
  home.file.".codex/config.toml".source = ../../../codex/config.toml;

  home.packages = [
    pkgs.claude-code
    pkgs.codex
    pkgs.source-han-code-jp
  ];
}
