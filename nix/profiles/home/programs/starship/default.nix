{ pkgs, ... }:
{
  programs.starship = {
    enable = true;
    package = pkgs.starship;
    enableBashIntegration = true;
    enableZshIntegration = true;
    settings = {
      add_newline = true;
      format = "$os$username$hostname$memory_usage$directory$git_branch$git_status$nix_shell$character";
      character = {
        success_symbol = "[>](bold green)";
        error_symbol = "[x](bold red)";
      };
      os = {
        disabled = false;
        format = "[$symbol]($style) ";
      };
      username = {
        show_always = true;
        format = "[$user]($style)";
      };
      hostname = {
        ssh_only = false;
        format = "@[$hostname]($style) ";
      };
      memory_usage = {
        disabled = false;
        threshold = 0;
        format = "[$ram]($style) ";
      };
      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
      };
      git_branch = {
        symbol = " ";
      };
      git_status = {
        ahead = "";
        behind = "";
        diverged = "";
      };
      nix_shell = {
        symbol = " ";
        format = "[$symbol$state]($style) ";
      };
    };
  };
}
