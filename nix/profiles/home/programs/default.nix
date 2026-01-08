{ pkgs, ... }:
{
  imports = [
    ./ghq
    ./tmux
    ./vscode
  ];

  # Packages for chezmoi-managed configs
  home.packages = with pkgs; [
    bash
    zsh
    git
    starship
    fd
    fzf
    ripgrep
    zoxide
    wezterm
    claude-code
    codex
  ];
}
