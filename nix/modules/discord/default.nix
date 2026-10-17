{
  config,
  lib,
  pkgs,
  ...
}:
let
  modulesPath = "share/discord/modules";
in
{
  imports = [ (import ../tools.nix).discord ];
  programs.discord = {
    settings.SKIP_HOST_UPDATE = true;
    package = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
      pkgs.discord.overrideAttrs {
        # Keep the official application signature intact, including its resources.
        # Nixpkgs already installs native modules outside the application bundle.
        dontFixup = true;
      }
    );
  };

  # Launching the app bundle directly does not run nixpkgs' CLI wrapper.
  launchd.agents.discord-module-staging = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "${config.programs.discord.package.passthru.stageModules}"
        "${config.programs.discord.package}/${modulesPath}"
      ];
      RunAtLoad = true;
      KeepAlive.PathState = {
        "${config.home.homeDirectory}/Library/Application Support/discord/${config.programs.discord.package.version}/modules/installed.json" =
          false;
      };
    };
  };
}
