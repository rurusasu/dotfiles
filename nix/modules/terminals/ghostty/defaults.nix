_: {
  programs.ghostty = {
    enable = true;
    settings = {
      theme = "Catppuccin Mocha";
      font-family = "UDEV Gothic NF";
      font-size = 10;
    };
    enableBashIntegration = true;
    enableFishIntegration = false;
    enableZshIntegration = true;
    installBatSyntax = false;
  };
}
