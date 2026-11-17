{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.silverbullet-trial;
in
{
  options.services.silverbullet-trial = {
    enable = lib.mkEnableOption "the local SilverBullet trial server";
    package = lib.mkPackageOption pkgs "silverbullet" { };
    directory = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/silverbullet-trial";
      description = "Trial directory containing the space folder and server.log.";
    };
  };

  config = lib.mkMerge [
    { services.silverbullet-trial.enable = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin true; }
    (lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isDarwin) {
      home.activation.silverbulletTrialDirectory =
        lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ]
          ''
            run mkdir -p ${lib.escapeShellArg "${cfg.directory}/space"}
          '';

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
            "${cfg.directory}/space"
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
