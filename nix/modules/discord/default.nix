{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.discord = {
    enable = true;
    settings.SKIP_HOST_UPDATE = true;
  };

  # Launching the app bundle directly does not run nixpkgs' CLI wrapper.
  launchd.agents.discord-module-staging = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "${config.programs.discord.package.passthru.stageModules}"
        "${config.programs.discord.package}/Applications/Discord.app/Contents/Resources/modules"
      ];
      RunAtLoad = true;
      KeepAlive.PathState = {
        "${config.home.homeDirectory}/Library/Application Support/discord/${config.programs.discord.package.version}/modules/installed.json" =
          false;
      };
    };
  };
}
