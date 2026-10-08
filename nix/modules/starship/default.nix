_: {
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    # The preserved Bash configuration initializes Starship once.
    enableBashIntegration = false;
  };
}
