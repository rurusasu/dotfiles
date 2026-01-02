{ config, pkgs, ... }:
{
  imports = [
    ../nixvim
    ./programs/vscode
    ./programs/wezterm
  ];

  home.stateVersion = "24.05";

  programs = {
    git.enable = true;
    zsh.enable = true;
    tmux.enable = true;
  };

  home.file.".bashrc".source = ./bash/.bashrc;
  home.file.".profile".source = ./bash/.profile;
  home.file.".bash_logout".source = ./bash/.bash_logout;
  home.file.".claude/settings.json".source = ../../../claude/settings.json;
  home.file.".codex/config.toml".source = ../../../codex/config.toml;

  home.packages = [
    pkgs.claude-code
    pkgs.codex
    pkgs.source-han-code-jp
  ];
}
