{
  # User shell integration is shared by Darwin, Linux, and WSL homes.
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    options = [ "--cmd cd" ];
  };
}
