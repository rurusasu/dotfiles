{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.silverbullet-trial;
  desktop = config.programs.silverbullet;
in
{
  options.programs.silverbullet = {
    enable = lib.mkEnableOption "SilverBullet Desktop";
    package = lib.mkOption {
      type = lib.types.package;
      default = import ./package.nix { inherit pkgs; };
      defaultText = lib.literalExpression "the official SilverBullet Desktop distribution";
      description = "SilverBullet Desktop package for Apple Silicon macOS.";
    };
  };

  options.services.silverbullet-trial = {
    enable = lib.mkEnableOption "the local SilverBullet trial server";
    package = lib.mkPackageOption pkgs "silverbullet" { };
    directory = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/silverbullet-trial";
      description = "Directory holding the SilverBullet server log.";
    };
    space = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/lifelog";
      description = "Space folder served by the SilverBullet server.";
    };
  };

  config = lib.mkMerge [
    {
      programs.silverbullet.enable = lib.mkIf (pkgs.stdenv.hostPlatform.system == "aarch64-darwin") true;
      services.silverbullet-trial.enable = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin true;
    }
    (lib.mkIf desktop.enable {
      home.packages = [ desktop.package ];
    })
    (lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isDarwin) {
      home.activation.silverbulletTrialDirectory =
        lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ]
          ''
            run mkdir -p ${lib.escapeShellArg cfg.directory}
          '';

      home.file."lifelog".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Library/CloudStorage/GoogleDrive-rurusasu153@gmail.com/マイドライブ/lifelog";

      launchd.agents.silverbullet-trial = {
        enable = true;
        config = {
          ProgramArguments = [
            "${cfg.package}/bin/silverbullet"
            "--single"
            "-L"
            "127.0.0.1"
            "-p"
            "3001"
            "${cfg.space}"
          ];
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = "${cfg.directory}/server.log";
          StandardErrorPath = "${cfg.directory}/server.log";
        };
      };
    })
  ];
}
