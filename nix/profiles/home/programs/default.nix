{ pkgs, ... }:
{
  imports = [
    ./shells
    ./editors
    ./llms
    ./ghq
    ./tmux
  ];

  # Packages for chezmoi-managed configs
  home.packages = with pkgs; [
    # Dotfiles manager
    chezmoi

    # Version control
    git
    gh  # GitHub CLI

    # CLI tools
    fd
    fzf
    ripgrep
    zoxide

    # Terminals
    wezterm
  ];
}
