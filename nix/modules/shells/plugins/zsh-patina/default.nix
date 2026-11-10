{
  config,
  lib,
  pkgs,
  platform,
  ...
}:
{
  options.programs.zsh-patina = {
    enable = lib.mkEnableOption "zsh-patina shell highlighting";
    package = lib.mkPackageOption pkgs "zsh-patina" { };
  };

  config = lib.mkMerge [
    { programs.zsh-patina.enable = true; }
    (lib.mkIf (config.programs.zsh-patina.enable && config.programs.zsh.enable) {
      xdg.configFile."zsh-patina/config.toml" = lib.mkIf (platform == "wsl") {
        text = ''
          [highlighting]
          dynamic = { callables = false, paths = "complete" }
        '';
      };

      programs.zsh-patina.package = lib.mkDefault (
        pkgs.zsh-patina.overrideAttrs (previous: {
          # 1.11.0 performs disabled dynamic lookups before discarding their results.
          patches = (previous.patches or [ ]) ++ [ ./skip-disabled-dynamic-lookups.patch ];
        })
      );

      # Activate after widgets and other shell integrations, as upstream recommends.
      programs.zsh.initContent = lib.mkAfter ''
        eval "$(${lib.getExe config.programs.zsh-patina.package} activate)"
      '';
    })
  ];
}
