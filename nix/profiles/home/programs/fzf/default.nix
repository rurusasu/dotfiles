{ pkgs, ... }:
{
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    package = pkgs.fzf;
    defaultOptions = [
      "--height=40%"
      "--layout=reverse"
      "--border"
      "--prompt=> "
    ];
  };
}
