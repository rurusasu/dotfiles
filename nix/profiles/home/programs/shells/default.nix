{ pkgs, ... }:
{
  # Shell packages
  # Configuration files are managed by chezmoi (chezmoi/shells/)
  home.packages = with pkgs; [
    bash
    zsh
  ];

  # Starship prompt
  programs.starship = {
    enable = true;
    # Config is managed by chezmoi (chezmoi/cli/starship/starship.toml)
  };
}
