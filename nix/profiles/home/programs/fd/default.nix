# fd profile - uses settings from myHomeSettings.fd
{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.myHomeSettings.fd;

  # Build extraOptions from module settings
  buildExtraOptions =
    (optional cfg.followSymlinks "--follow")
    ++ (optional cfg.noIgnoreVcs "--no-ignore-vcs")
    ++ (optional (cfg.maxResults != null) "--max-results=${toString cfg.maxResults}")
    ++ (optional (cfg.maxDepth != null) "--max-depth=${toString cfg.maxDepth}")
    ++ cfg.extraOptions;
in
{
  config = mkIf cfg.enable {
    programs.fd = {
      enable = true;
      package = pkgs.fd;
      hidden = cfg.hidden;
      ignores = cfg.ignores;
      extraOptions = buildExtraOptions;
    };
  };
}
