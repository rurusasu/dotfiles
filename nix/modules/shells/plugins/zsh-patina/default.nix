{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.programs.zsh-patina.enable = lib.mkEnableOption "zsh-patina shell highlighting";

  config = lib.mkIf (config.programs.zsh-patina.enable && config.programs.zsh.enable) {
    # Activate after widgets and other shell integrations, as upstream recommends.
    programs.zsh.initContent = lib.mkAfter ''
      eval "$(${lib.getExe pkgs.zsh-patina} activate)"
    '';
  };
}
