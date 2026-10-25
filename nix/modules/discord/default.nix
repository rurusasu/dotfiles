{
  config,
  lib,
  pkgs,
  ...
}:
let
  discordPackage = pkgs.discord.override { disableUpdates = false; };
in
{
  imports = [ (import ../tools.nix).discord ];
  programs.discord = {
    package =
      if pkgs.stdenv.hostPlatform.isDarwin then
        discordPackage.overrideAttrs {
          # Keep the official application signature intact, including its resources.
          # Nixpkgs already installs native modules outside the application bundle.
          dontFixup = true;
        }
      else
        discordPackage;
  };

  # Launching the app bundle directly does not run nixpkgs' CLI wrapper.
  launchd.agents.discord-module-staging = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "${config.programs.discord.package.passthru.stageModules}"
        "${config.programs.discord.package}/share/discord/modules"
      ];
      RunAtLoad = true;
      KeepAlive.PathState = {
        "${config.home.homeDirectory}/Library/Application Support/discord/${config.programs.discord.package.version}/modules/installed.json" =
          false;
      };
    };
  };
}
