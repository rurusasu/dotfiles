# fzf profile - uses settings from myHomeSettings.fzf and myHomeSettings.fd
{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  fzfCfg = config.myHomeSettings.fzf;
  fdCfg = config.myHomeSettings.fd;

  # Build fd command with all options from fd module
  fdOptions =
    (optional fdCfg.hidden "--hidden")
    ++ (optional fdCfg.followSymlinks "--follow")
    ++ (optional fdCfg.noIgnoreVcs "--no-ignore-vcs")
    ++ (optional (fdCfg.maxResults != null) "--max-results=${toString fdCfg.maxResults}")
    ++ (optional (fdCfg.maxDepth != null) "--max-depth=${toString fdCfg.maxDepth}")
    ++ fdCfg.extraOptions;

  fdOptionsStr = concatStringsSep " " fdOptions;

  # Build fd commands for fzf
  fdCmd = "${pkgs.fd}/bin/fd ${fdOptionsStr}";
  defaultCommand = "${fdCmd} --type f . ${fzfCfg.searchRoot}";
  fileWidgetCommand = "${fdCmd} --type f . ${fzfCfg.searchRoot}";
  changeDirWidgetCommand = "${fdCmd} --type d . ${fzfCfg.searchRoot}";

  # Build fzf default options
  buildDefaultOptions = [
    "--height=${fzfCfg.height}"
  ]
  ++ [ "--layout=${fzfCfg.layout}" ]
  ++ (optional fzfCfg.border "--border")
  ++ [ "--prompt=${fzfCfg.prompt}" ]
  ++ fzfCfg.extraOptions;
in
{
  config = mkIf fzfCfg.enable {
    programs.fzf = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      package = pkgs.fzf;

      # fd commands with shared settings
      inherit defaultCommand fileWidgetCommand changeDirWidgetCommand;

      # UI options
      defaultOptions = buildDefaultOptions;
    };
  };
}
