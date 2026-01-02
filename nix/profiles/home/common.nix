{ config, pkgs, dotfilesPath, ... }:
{
  imports = [
    ../nixvim
    ./programs/fzf
    ./programs/vscode
    ./programs/wezterm
  ];

  home.stateVersion = "24.05";

  programs = {
    git.enable = true;
    zsh = {
      enable = true;
      shellAliases = {
        nrs = "sudo nixos-rebuild switch --flake ~/dotfiles --impure";
        nrt = "sudo nixos-rebuild test --flake ~/dotfiles --impure";
        nrb = "sudo nixos-rebuild boot --flake ~/dotfiles --impure";
      };
    };
    tmux.enable = true;
  };

  home.file.".bashrc".source = ./bash/.bashrc;
  home.file.".profile".source = ./bash/.profile;
  home.file.".bash_logout".source = ./bash/.bash_logout;
  home.file.".claude/settings.json".source = ../../../claude/settings.json;
  home.file.".codex/config.toml".source = ../../../codex/config.toml;
  home.file."dotfiles".source = config.lib.file.mkOutOfStoreSymlink dotfilesPath;

  home.packages = [
    pkgs.claude-code
    pkgs.codex
    pkgs.fzf
    pkgs.ghq
    pkgs.source-han-code-jp
  ];
}
