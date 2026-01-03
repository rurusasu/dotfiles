{ pkgs, ... }:
{
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    package = pkgs.fzf;
    # fdの設定（ignores, extraOptions）はprograms.fdで管理
    defaultCommand = "${pkgs.fd}/bin/fd --type f";
    fileWidgetCommand = "${pkgs.fd}/bin/fd --type f";
    changeDirWidgetCommand = "${pkgs.fd}/bin/fd --type d";
    defaultOptions = [
      "--height=40%"
      "--layout=reverse"
      "--border"
      "--prompt=> "
    ];
  };
}
