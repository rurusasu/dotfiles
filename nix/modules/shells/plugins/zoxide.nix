{
  # User shell integration is shared by Darwin, Linux, and WSL homes.
  programs.zoxide = {
    enableBashIntegration = true;
    enableZshIntegration = true;
    options = [ "--cmd cd" ];
  };
}
