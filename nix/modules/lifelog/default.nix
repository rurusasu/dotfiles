{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.lifelog;
in
{
  options.programs.lifelog = {

    enable = lib.mkEnableOption "Lifelog local workspace";
    sourceDirectory = lib.mkOption {
      type = lib.types.str;
      default =
        config.programs.ghq.root
        + "/github.com/"
        + config.programs.git.settings.user.name
        + "/lifelog-core";
      description = "Local checkout containing the selected Lifelog release tag.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = import ./package.nix {
        inherit pkgs;
        inherit (cfg) sourceDirectory;
      };
      description = "Lifelog package to install.";
    };
  };

  config = lib.mkMerge [
    {
      programs.lifelog.enable = lib.mkIf (
        config.programs.git.enable
        && pkgs.stdenv.hostPlatform.system == "x86_64-linux"
        && builtins.pathExists (cfg.sourceDirectory + "/.git/lifelog-release-tag")
      ) true;
    }
    (lib.mkIf cfg.enable {
      home.packages = [ cfg.package ];
      xdg.desktopEntries.lifelog = {
        name = "Lifelog";
        genericName = "Local file workspace";
        exec = "${cfg.package}/bin/lifelog";
        categories = [
          "Office"
          "Utility"
        ];
        terminal = false;
      };
    })
  ];
}
